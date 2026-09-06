"""Verify release inventory, checksums, safe paths and byte-for-byte rebuild."""
import hashlib
import json
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
profile = json.loads((ROOT/'firmware/profiles/xiaomi-be7000-qwrt.json').read_text(encoding='utf-8'))
asset = ROOT/'dist'/f'netscope-xiaomi-be7000-qwrt-r26.2.2-overlay-{profile["project_version"]}.tar.gz'
before = hashlib.sha256(asset.read_bytes()).hexdigest()
assert asset.with_suffix('.gz.sha256').read_text().split()[0] == before
with tarfile.open(asset, 'r:gz') as archive:
    files = {}
    for entry in archive.getmembers():
        path = PurePosixPath(entry.name)
        assert not path.is_absolute() and '..' not in path.parts
        assert path.parts[0] == 'netscope-overlay'
        assert entry.isfile() or entry.isdir(), 'links and special files are not allowed'
        if entry.isfile():
            name = str(path.relative_to('netscope-overlay'))
            assert name not in files
            files[name] = archive.extractfile(entry).read()
    manifest = json.loads(files['manifest.json'])
    assert manifest['version'] == profile['project_version']
    assert manifest['flashable'] is False and manifest['capture_default'] == 'OFF'
    assert b'MIT License' in files['LICENSE']
    listed = {}
    for line in files['SHA256SUMS'].decode().splitlines():
        sha, name = line.split('  ', 1)
        assert name not in listed and name in files
        assert hashlib.sha256(files[name]).hexdigest() == sha
        listed[name] = sha
    assert set(files) == set(listed) | {'SHA256SUMS'}
    payload = {name.removeprefix('payload/') for name in files if name.startswith('payload/')}
    assert payload == {entry['target'] for entry in manifest['entries']}
    for entry in manifest['entries']:
        assert not entry['target'].startswith('etc/config/')
        assert hashlib.sha256(files['payload/'+entry['target']]).hexdigest() == entry['sha256']
        assert entry['mode'] in ('0644', '0755')
subprocess.run([sys.executable, 'tools/build_overlay.py'], cwd=ROOT, check=True, capture_output=True)
assert hashlib.sha256(asset.read_bytes()).hexdigest() == before, 'non-reproducible rebuild'
print('OVERLAY_VERIFIED: paths, full inventory, license, SHA-256, deterministic rebuild; NOT FLASHABLE')
