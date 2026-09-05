"""Bounded streaming exporter for mitmdump. No payloads go to stdout/logs."""
import asyncio
import hashlib
import json
import os
import time
from pathlib import Path

from mitmproxy import ctx

BODY_LIMIT = 65536
MAX_FLOWS = 64
SLOTS = 512
JOURNAL_SIZE = 262144
JOURNALS = 16


def atomic(path, data):
    tmp = path.with_name(path.name + ".new")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=True, separators=(",", ":"))
    os.chmod(tmp, 0o600)
    tmp.replace(path)


class Exporter:
    def __init__(self):
        self.root = Path(os.environ.get("NETSCOPE_EXPORT", "/capture/flows"))
        self.pending = {}
        self.seq = self.part = self.journal_bytes = self.decrypted = self.failed = self.omitted = 0
        self.task = None
        self.storage_failed = False

    def running(self):
        os.umask(0o077)
        self.part = 1
        self.task = asyncio.create_task(self.heartbeat())

    async def heartbeat(self):
        while not self.storage_failed:
            try:
                atomic(self.root / "https-health.json", {"heartbeat": time.time(), "ready": True,
                    "decrypted": self.decrypted, "failed": self.failed, "omitted": self.omitted})
            except OSError:
                # Supervisor sees the missing heartbeat and removes redirect first.
                ctx.master.shutdown()
                return
            await asyncio.sleep(1)

    def done(self):
        if self.task:
            self.task.cancel()

    @staticmethod
    def message(msg):
        # Bounded header retention; forwarding itself is unchanged.
        headers, used = [], 0
        for name, value in msg.headers.items(multi=True):
            if len(headers) >= 128 or used >= 32768:
                break
            value = value[:8192]
            headers.append({"name": name[:256], "value": value})
            used += len(name) + len(value)
        return {"headers": headers, "headers_truncated": len(headers) < len(msg.headers),
            "content_type": msg.headers.get("content-type", "")[:512],
            "content_encoding": msg.headers.get("content-encoding"),
            "http_version": msg.http_version, "timestamp_start": msg.timestamp_start,
            "size": 0, "body_captured": 0, "truncated": False}

    def stream(self, record):
        body = bytearray()
        record["_body"] = body
        def receive(chunk):
            record["size"] += len(chunk)
            body.extend(chunk[:max(0, BODY_LIMIT - len(body))])
            record["body_captured"] = len(body)
            record["truncated"] = record["size"] > len(body)
            return chunk  # Never alter forwarded application data.
        return receive

    def requestheaders(self, flow):
        if len(self.pending) >= MAX_FLOWS:
            self.omitted += 1
            flow.request.stream = True
            return
        request = self.message(flow.request)
        request.update(method=flow.request.method, host=flow.request.host,
                       path=flow.request.path[:16384], scheme=flow.request.scheme)
        self.pending[flow.id] = {"request": request}
        flow.request.stream = self.stream(request)

    def responseheaders(self, flow):
        entry = self.pending.get(flow.id)
        if entry is None:
            flow.response.stream = True
            return
        response = self.message(flow.response)
        response["status"] = flow.response.status_code
        entry["response"] = response
        flow.response.stream = self.stream(response)

    def export(self, flow, failed=False):
        entry = self.pending.pop(flow.id, None)
        if entry is None:
            return
        client, server = flow.client_conn, flow.server_conn
        source = client.peername or ("unknown", 0)
        destination = server.peername or server.address or ("unknown", 0)
        decrypted = bool(client.tls_established and server.tls_established)
        entry.update(timestamp=flow.request.timestamp_start, source=source[0], sport=source[1],
            destination=destination[0], dport=destination[1],
            inspection="TLS FAILED" if failed else "HTTPS DECRYPTED" if decrypted else "PLAIN HTTP",
            tls={"sni": client.sni, "client_version": client.tls_version,
                 "server_version": server.tls_version, "decrypted": decrypted,
                 "alpn": (client.alpn or b"").decode("ascii", "replace")},
            timing={"request_end": flow.request.timestamp_end,
                    "response_end": flow.response.timestamp_end if flow.response else None})
        if failed:
            entry["failure"] = "Proxy connection failed; see TLS metadata. Pinning is not established."
        self.decrypted += int(decrypted and not failed)
        self.failed += int(failed)
        self.store(entry)

    def store(self, entry):
        if self.storage_failed:
            return
        try:
            self._store(entry)
        except (OSError, ValueError, KeyError):
            # Do not report a healthy proxy when flow export is broken. Do not
            # let framework exception logging include captured request values.
            self.storage_failed = True
            if self.task:
                self.task.cancel()
            try:
                atomic(self.root / "https-health.json", {"ready": False,
                    "heartbeat": time.time(), "error": "Flow storage failed"})
            except OSError:
                pass
            ctx.master.shutdown()

    def _store(self, entry):
        self.seq += 1
        entry["id"] = self.seq
        path = self.root / f"https-{self.seq % SLOTS:04d}.json"
        if path.exists():
            old = json.loads(path.read_text())
            # File names derive only from our numeric ID, never an HTTP URL.
            for side in ("request", "response"):
                previous = self.root / f"https-body-{old['id']}-{side}.bin"
                previous.unlink(missing_ok=True)
        for side in ("request", "response"):
            msg = entry.get(side)
            if msg is not None:
                data = bytes(msg.pop("_body", b""))
                name = f"https-body-{self.seq}-{side}.bin"
                (self.root / name).write_bytes(data)
                msg.update(body_ref=name, sha256=hashlib.sha256(data).hexdigest())
        atomic(path, entry)
        req, res = entry.get("request", {}), entry.get("response", {})
        summary = {k: entry.get(k) for k in ("id", "timestamp", "source", "destination", "dport", "inspection")}
        summary.update(method=req.get("method", "—"), host=req.get("host") or entry.get("sni"), status=res.get("status"), size=res.get("size"))
        line = json.dumps(summary, ensure_ascii=True, separators=(",", ":")) + "\n"
        if self.journal_bytes + len(line) > JOURNAL_SIZE:
            self.part += 1
            self.journal_bytes = 0
            if self.part > JOURNALS:
                (self.root / f"https-{self.part-JOURNALS:08d}.jsonl").unlink(missing_ok=True)
        with (self.root / f"https-{self.part:08d}.jsonl").open("a") as f:
            f.write(line)
        self.journal_bytes += len(line)

    def response(self, flow):
        self.export(flow)

    def error(self, flow):
        self.export(flow, True)

    def tls_failed_client(self, data):
        client = data.context.client
        server = data.context.server
        self.failed += 1
        self.store({"timestamp": time.time(), "source": (client.peername or ("unknown", 0))[0],
            "destination": (server.address or ("unknown", 0))[0], "dport": 443,
            "sni": client.sni, "inspection": "TLS FAILED", "failure":
            "Client TLS handshake failed. CA trust or certificate pinning may be a cause; not proven."})

    def websocket_message(self, flow):
        # Do not let mitmproxy retain an unbounded WebSocket message history.
        # This version records the HTTP upgrade, not application messages.
        flow.websocket.messages.clear()


addons = [Exporter()]
