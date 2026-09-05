"""Public-source guardrails, not a substitute for SDK or on-router testing."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT/'firmware/packages/luci-app-netscope-setup'
FILES = PACKAGE/'files'

class FirmwareSourceTests(unittest.TestCase):
    def test_release_is_explicitly_not_flashable(self):
        p = json.loads((ROOT/'firmware/profiles/xiaomi-be7000-qwrt.json').read_text())
        self.assertFalse(p['flashable'])
        self.assertIsNone(p['build_base_sha256'])
        self.assertTrue(p['missing_gates'])

    def test_package_is_standalone_and_contains_no_credentials(self):
        expected = {
            'usr/lib/lua/luci/controller/netscope_setup.lua',
            'usr/lib/lua/luci/model/netscope_setup.lua',
            'usr/lib/lua/luci/model/netscope_setup_runtime.lua',
            'usr/lib/lua/luci/view/netscope/setup.htm',
            'www/luci-static/netscope/setup.js',
        }
        actual = {p.relative_to(FILES).as_posix() for p in FILES.rglob('*') if p.is_file()}
        self.assertEqual(expected, actual)
        for relative in actual:
            text = (FILES/relative).read_text(encoding='utf-8')
            self.assertNotIn('luci.model.netscope_capture', text)
            self.assertNotIn('BEGIN '+'PRIVATE KEY', text)
            self.assertNotIn('BEGIN CERTIFICATE', text)

    def test_wizard_no_activation_or_secret_persistence(self):
        controller = (FILES/'usr/lib/lua/luci/controller/netscope_setup.lua').read_text()
        self.assertIn("post('prepare')", controller)
        self.assertNotIn("post('activate')", controller)
        js = (FILES/'www/luci-static/netscope/setup.js').read_text()
        self.assertNotIn('localStorage', js)
        self.assertNotIn('sessionStorage', js)
        self.assertIn("params.set('token'", js)
        self.assertIn('AbortController', js)
        model = (FILES/'usr/lib/lua/luci/model/netscope_setup.lua').read_text()
        for forbidden in ('uci commit', '/etc/init.d/', 'wg-quick up'):
            self.assertNotIn(forbidden, model)
        self.assertNotIn("post('activate')", controller)
        self.assertIn("post('preflight')", controller)
        self.assertIn("post('delete')", controller)
        self.assertIn("socks5ListenLAN=false", model)
        self.assertIn("mode='prepare-only'", model)

    def test_menu_and_device_identity(self):
        view = (FILES/'usr/lib/lua/luci/view/netscope/setup.htm').read_text()
        self.assertIn('<h2>VPN Quick setup</h2>', view)
        for protocol in ('wg', 'awg', 'vless', 'mieru'):
            self.assertIn('value="'+protocol+'"', view)
        self.assertIn('not released yet', view)

if __name__ == '__main__': unittest.main()
