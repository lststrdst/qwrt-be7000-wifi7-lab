"""Build a deterministic, source-derived NETSCOPE overlay release."""
from __future__ import annotations

import gzip
import hashlib
import json
import re
import shutil
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE = json.loads((ROOT / "firmware/profiles/xiaomi-be7000-qwrt.json").read_text(encoding="utf-8"))
VERSION = PROFILE["project_version"]
if not re.fullmatch(r"\d+\.\d+\.\d+(?:-beta\.\d+)?", VERSION) or PROFILE["flashable"] is not False:
    raise SystemExit("invalid overlay version/profile; a flashable image needs its own validated builder")
BASE = "QWRT R26.2.2"
PACKAGES = (
    "luci-app-netscope",
    "luci-theme-netscope",
    "luci-app-netscope-setup",
    "netscope-wifi7-lab",
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def source_bytes(path: Path) -> bytes:
    """All bundled payloads are UTF-8 source, never binaries or device dumps."""
    raw = path.read_bytes().replace(b"\r\n", b"\n")
    raw.decode("utf-8")
    if b"\0" in raw:
        raise SystemExit(f"binary source refused: {path.name}")
    return raw


def write_text_lf(path: Path, value: str, *, encoding: str = "utf-8") -> None:
    with path.open("w", encoding=encoding, newline="\n") as stream:
        stream.write(value)


def collect() -> list[dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for package in PACKAGES:
        source = ROOT / "firmware" / "packages" / package / "files"
        if not source.is_dir():
            raise SystemExit(f"missing package payload: {package}")
        for path in sorted(source.rglob("*")):
            if not path.is_file() or path.is_symlink():
                continue
            target = path.relative_to(source).as_posix()
            if target in result:
                raise SystemExit(f"duplicate target: {target}")
            if target.startswith("etc/config/") or ".." in Path(target).parts:
                raise SystemExit(f"unsafe target: {target}")
            mode = "0755" if target.startswith(("usr/libexec/", "etc/init.d/")) else "0644"
            result[target] = {"target": target, "sha256": hashlib.sha256(source_bytes(path)).hexdigest(), "mode": mode, "component": package}
    return [result[name] for name in sorted(result)]


def add_tree(archive: tarfile.TarFile, root: Path) -> None:
    for path in sorted(root.rglob("*"), key=lambda p: p.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        info = archive.gettarinfo(str(path), arcname=f"netscope-overlay/{relative}")
        info.uid = info.gid = 0
        info.uname = info.gname = "root"
        info.mtime = 0
        if path.is_dir():
            info.mode = 0o755
            archive.addfile(info)
        else:
            info.mode = 0o755 if relative == "install.sh" else 0o644
            with path.open("rb") as stream:
                archive.addfile(info, stream)


def main() -> int:
    entries = collect()
    output_dir = ROOT / "dist"
    output_dir.mkdir(exist_ok=True)
    output = output_dir / f"netscope-xiaomi-be7000-qwrt-r26.2.2-overlay-{VERSION}.tar.gz"
    with tempfile.TemporaryDirectory(prefix="netscope-overlay-") as temporary:
        stage = Path(temporary) / "netscope-overlay"
        stage.mkdir()
        for entry in entries:
            source = ROOT / "firmware" / "packages" / entry["component"] / "files" / entry["target"]
            destination = stage / "payload" / entry["target"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(source_bytes(source))
        for source, name in [(ROOT / "firmware/overlay/install.sh", "install.sh"), (ROOT / "LICENSE", "LICENSE"), (ROOT / "docs/INSTALL-OVERLAY.md", "INSTALL-OVERLAY.md")]:
            (stage / name).write_bytes(source_bytes(source))
        write_text_lf(stage / "manifest.json", json.dumps({
            "project": "NETSCOPE", "version": VERSION, "kind": "installable-overlay",
            "device": "Xiaomi BE7000", "base": BASE, "flashable": False,
            "capture_default": "OFF", "entries": entries,
        }, ensure_ascii=False, indent=2) + "\n")
        write_text_lf(stage / "manifest.tsv", "".join(
            f'{entry["target"]}\t{entry["sha256"]}\t{entry["mode"]}\t{entry["component"]}\n'
            for entry in entries
        ))
        write_text_lf(stage / "README.txt",
            "NETSCOPE installable overlay for Xiaomi BE7000 on exact QWRT R26.2.2.\n"
            "This is not a factory image or sysupgrade archive and never writes NAND/UBI.\n"
            "Review manifest.json, then run: sh install.sh\n",
        )
        checked = [stage / "install.sh", stage / "manifest.json", stage / "manifest.tsv", stage / "README.txt"]
        checked.extend([stage / "LICENSE", stage / "INSTALL-OVERLAY.md"])
        checked.extend(stage / "payload" / entry["target"] for entry in entries)
        write_text_lf(stage / "SHA256SUMS", "".join(
            f"{digest(path)}  {path.relative_to(stage).as_posix()}\n" for path in sorted(checked)
        ))
        with output.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as archive:
                    add_tree(archive, stage)
    checksum = digest(output)
    write_text_lf(output.with_suffix(output.suffix + ".sha256"), f"{checksum}  {output.name}\n", encoding="ascii")
    print(f"OVERLAY={output}")
    print(f"SHA256={checksum}")
    print(f"FILES={len(entries)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
