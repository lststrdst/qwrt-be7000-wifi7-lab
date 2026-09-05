from __future__ import annotations

import ipaddress
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {"", ".conf", ".example", ".json", ".md", ".py", ".sh", ".txt", ".toml", ".yml", ".yaml", ".lua", ".htm", ".js", ".cjs", ".css"}
FORBIDDEN_SUFFIXES = {".bin", ".img", ".ipk", ".key", ".pem", ".png", ".qr", ".squashfs", ".tar", ".ubi", ".ubifs", ".pcap", ".pcapng", ".mobileconfig", ".p12", ".pfx"}
URI_SECRET = re.compile(r"(?i)\b(?:vless|happ|hy2|ss|ssr)://[A-Za-z0-9]")
KEY_VALUE = re.compile(r"(?im)^\s*(?:PrivateKey|PresharedKey|PublicKey)\s*=\s*([A-Za-z0-9+/]{40,}={0,2})\s*$")
UUID_VALUE = re.compile(r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b")
WINDOWS_HOME = re.compile(r"(?i)[A-Z]:\\Users\\[^\\\s]+")
MAC = re.compile(r"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b")
IPV4 = re.compile(r"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9.])")
SPECIAL_USE = tuple(ipaddress.ip_network(value) for value in (
    "100.64.0.0/10", "169.254.0.0/16", "192.0.0.0/24", "198.18.0.0/15",
    "224.0.0.0/4", "240.0.0.0/4",
))


def allowed_ip(value: str) -> bool:
    ip = ipaddress.ip_address(value)
    return (
        ip.is_private
        or ip.is_loopback
        or ip.is_unspecified
        or value == "1.1.1.1"
        or any(ip in network for network in SPECIAL_USE)
        or ip in ipaddress.ip_network("192.0.2.0/24")
        or ip in ipaddress.ip_network("198.51.100.0/24")
        or ip in ipaddress.ip_network("203.0.113.0/24")
    )


def main() -> int:
    errors: list[str] = []
    for path in sorted(ROOT.rglob("*")):
        if any(part in {".git", "build", "dist"} for part in path.parts) or not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if relative.as_posix() == "tools/check_public.py":
            continue
        if path.suffix.lower() in FORBIDDEN_SUFFIXES:
            errors.append(f"forbidden artifact: {relative}")
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES and "." in path.name:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if URI_SECRET.search(text):
            errors.append(f"secret-bearing URI scheme: {relative}")
        if KEY_VALUE.search(text):
            errors.append(f"key-looking value: {relative}")
        for match in UUID_VALUE.finditer(text):
            context = text[max(0, match.start() - 40):match.end() + 40]
            if "REPLACE" not in context:
                errors.append(f"UUID-looking value: {relative}")
        if WINDOWS_HOME.search(text):
            errors.append(f"absolute Windows user path: {relative}")
        for match in MAC.finditer(text):
            if not match.group(0).lower().startswith("02:00:00:00:00:"):
                errors.append(f"non-example MAC: {relative}")
        for match in IPV4.finditer(text):
            try:
                if not allowed_ip(match.group(0)):
                    errors.append(f"public IPv4 outside documentation ranges: {relative}")
            except ValueError:
                continue

    if errors:
        print("PUBLIC_CHECK=FAIL")
        for error in sorted(set(errors)):
            print(error)
        return 1
    print("PUBLIC_CHECK=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
