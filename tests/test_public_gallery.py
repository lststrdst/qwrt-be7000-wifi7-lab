"""Exact screenshot review gates; binary hashes do not replace visual review."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('public_check', ROOT/'tools/check_public.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class PublicGalleryTests(unittest.TestCase):
    def test_only_reviewed_images_match(self):
        self.assertEqual(len(check.REVIEWED_SCREENSHOTS), 2)
        for relative in check.REVIEWED_SCREENSHOTS:
            self.assertTrue(check.reviewed_screenshot(ROOT/relative, relative))
            self.assertFalse(check.reviewed_screenshot(ROOT/relative, 'docs/screenshots/unreviewed.jpg'))

    def test_modified_bytes_fail_even_with_reviewed_name(self):
        relative = next(iter(check.REVIEWED_SCREENSHOTS))
        with tempfile.TemporaryDirectory() as directory:
            changed = Path(directory)/'changed.jpg'
            changed.write_bytes((ROOT/relative).read_bytes() + b'not-reviewed')
            self.assertFalse(check.reviewed_screenshot(changed, relative))

    def test_gallery_is_local_read_only_and_uses_production_views(self):
        source = (ROOT/'tools/preview-gallery.cjs').read_text(encoding='utf-8')
        self.assertIn("listen(4190,'127.0.0.1'", source)
        self.assertIn("req.method !== 'GET'", source)
        self.assertIn('res.writeHead(405', source)
        self.assertIn('view/themes/netscope/monitor.htm', source)
        self.assertIn('view/netscope/setup.htm', source)
        self.assertIn("connect-src 'self'", source)
        self.assertNotIn('child_process', source)
        self.assertNotIn('fetch(', source)


if __name__ == '__main__':
    unittest.main()
