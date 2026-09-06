"""Run the production browser parser without DOM or network access."""
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class EasyImportTests(unittest.TestCase):
    def test_production_parser(self):
        node = shutil.which('node')
        self.assertIsNotNone(node, 'Node.js is required for importer verification')
        result = subprocess.run([node, '--test', 'tests/import.test.cjs'], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_no_storage_or_activation_in_parser(self):
        source = (ROOT/'firmware/packages/luci-app-netscope-setup/files/www/luci-static/netscope/import.js').read_text(encoding='utf-8')
        for forbidden in ['localStorage', 'sessionStorage', 'fetch(', 'innerHTML', 'eval(', 'activate(']:
            self.assertNotIn(forbidden, source)

    def test_authenticated_post_and_packaged_asset(self):
        package = ROOT/'firmware/packages/luci-app-netscope-setup'
        controller = (package/'files/usr/lib/lua/luci/controller/netscope_setup.lua').read_text(encoding='utf-8')
        self.assertIn("'subscription'},post('subscription')", controller)
        self.assertIn('import.js', (package/'Makefile').read_text(encoding='utf-8'))
        view = (package/'files/usr/lib/lua/luci/view/netscope/setup.htm').read_text(encoding='utf-8')
        self.assertLess(view.index('import.js?v='), view.index('setup.js?v='))
