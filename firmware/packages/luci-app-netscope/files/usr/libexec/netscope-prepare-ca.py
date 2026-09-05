"""Generate the persistent CA once, or validate the existing one. Never print keys."""
import os
from pathlib import Path
from mitmproxy.certs import CertStore
from cryptography import x509
from cryptography.hazmat.primitives import serialization

def prepare(root: Path) -> None:
    os.umask(0o077)
    root = Path(root)
    if any(p.is_symlink() for p in [root, *root.parents]) or not root.is_dir():
        raise ValueError('Unsafe CA directory')
    root.chmod(0o700)
    lock = root / '.netscope-ca.lock'
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        os.close(fd)
        if any(p.is_symlink() for p in root.iterdir()):
            raise ValueError('Unsafe CA directory')
        private = root / 'mitmproxy-ca.pem'
        public = root / 'mitmproxy-ca-cert.pem'
        if not private.exists() and not public.exists():
            if any(p.name != lock.name for p in root.iterdir()):
                raise ValueError('CA directory is not empty; explicit recovery required')
            CertStore.create_store(root, 'mitmproxy', 2048, 'NETSCOPE', 'NETSCOPE Inspection CA')
        if not private.is_file() or not public.is_file():
            raise ValueError('Incomplete CA; explicit recovery required')
        key = serialization.load_pem_private_key(private.read_bytes(), password=None)
        cert = x509.load_pem_x509_certificate(public.read_bytes())
        encoding, form = serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
        if key.public_key().public_bytes(encoding, form) != cert.public_key().public_bytes(encoding, form):
            raise ValueError('CA key/certificate mismatch')
        if b'PRIVATE KEY' in public.read_bytes():
            raise ValueError('Public CA contains private data')
        CertStore.from_store(root, 'mitmproxy', 2048)
        for path in root.iterdir():
            if path.is_file():
                path.chmod(0o600)
    finally:
        lock.unlink()


if __name__ == '__main__':
    prepare(Path('/ca'))
    print('Persistent NETSCOPE CA ready; no private data emitted.')
