"""Public-source guardrails, not a substitute for SDK or on-router testing."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT/'firmware/packages/luci-app-netscope-setup'
FILES = PACKAGE/'files'
CORE = ROOT/'firmware/packages/luci-app-netscope/files'
THEME = ROOT/'firmware/packages/luci-theme-netscope/files'

class FirmwareSourceTests(unittest.TestCase):
    def test_release_is_explicitly_not_flashable(self):
        p = json.loads((ROOT/'firmware/profiles/xiaomi-be7000-qwrt.json').read_text())
        self.assertFalse(p['flashable'])
        self.assertIsNone(p['build_base_sha256'])
        self.assertTrue(p['missing_gates'])

    def test_public_overlay_is_source_derived_and_non_flashable(self):
        builder = (ROOT/'tools/build_overlay.py').read_text(encoding='utf-8')
        installer = (ROOT/'firmware/overlay/install.sh').read_text(encoding='utf-8')
        self.assertIn('"flashable": False', builder)
        self.assertIn('exact QWRT R26.2.2 base required', installer)
        self.assertIn('xiaomi,be7000', installer)
        self.assertNotIn('sysupgrade', installer)
        self.assertNotIn('mtd write', installer)
        for forbidden in ('/etc/config/network', '/etc/config/firewall', 'network restart', 'firewall restart'):
            self.assertNotIn(forbidden, installer)
        self.assertIn('Capture did not recover to OFF', installer)
        self.assertIn('before.tar.gz', installer)

    def test_overlay_components_are_present(self):
        required = {
            CORE/'usr/libexec/netscope-capture',
            CORE/'usr/lib/lua/luci/model/netscope_capture.lua',
            CORE/'usr/lib/lua/luci/model/netscope_capture_proxy.lua',
            THEME/'usr/lib/lua/luci/view/themes/netscope/header.htm',
            THEME/'www/luci-static/netscope/netscope.js',
        }
        self.assertTrue(all(path.is_file() for path in required))
        model = (CORE/'usr/lib/lua/luci/model/netscope.lua').read_text(encoding='utf-8')
        self.assertNotIn('192.168.10.208', model)
        self.assertNotIn('/tmp/netscope-lab', model)
        self.assertIn('Temporary lab retired', model)
        theme = (THEME/'www/luci-static/netscope/netscope.js').read_text(encoding='utf-8')
        self.assertIn("passwordActions.id = 'ns-password-save'", theme)
        self.assertIn("passwordSave.name = 'cbi.apply'", theme)

    def test_package_is_standalone_and_contains_no_credentials(self):
        expected = {
            'usr/lib/lua/luci/controller/netscope_setup.lua',
            'usr/lib/lua/luci/model/netscope_setup.lua',
            'usr/lib/lua/luci/model/netscope_setup_runtime.lua',
            'usr/lib/lua/luci/view/netscope/setup.htm',
            'usr/libexec/netscope-vpn-profile',
            'www/luci-static/netscope/setup.js',
        }
        actual = {p.relative_to(FILES).as_posix() for p in FILES.rglob('*') if p.is_file()}
        self.assertEqual(expected, actual)
        for relative in actual:
            text = (FILES/relative).read_text(encoding='utf-8')
            self.assertNotIn('luci.model.netscope_capture', text)
            self.assertNotIn('BEGIN '+'PRIVATE KEY', text)
            self.assertNotIn('BEGIN CERTIFICATE', text)

    def test_wizard_transactional_activation_and_no_secret_persistence(self):
        controller = (FILES/'usr/lib/lua/luci/controller/netscope_setup.lua').read_text(encoding='utf-8')
        self.assertIn("post('prepare')", controller)
        self.assertIn("post('activate')", controller)
        self.assertIn("post('deactivate')", controller)
        js = (FILES/'www/luci-static/netscope/setup.js').read_text(encoding='utf-8')
        self.assertNotIn('localStorage', js)
        self.assertNotIn('sessionStorage', js)
        self.assertIn("params.set('token'", js)
        self.assertIn('AbortController', js)
        model = (FILES/'usr/lib/lua/luci/model/netscope_setup.lua').read_text(encoding='utf-8')
        for forbidden in ('uci commit', '/etc/init.d/', 'wg-quick up'):
            self.assertNotIn(forbidden, model)
        self.assertIn("post('preflight')", controller)
        self.assertIn("post('delete')", controller)
        self.assertIn("socks5ListenLAN=false", model)
        manager = (FILES/'usr/libexec/netscope-vpn-profile').read_text(encoding='utf-8')
        for forbidden in ('uci commit', 'firewall restart', 'network restart', 'ip route add default', 'iptables -F', 'iptables -t nat -F'):
            self.assertNotIn(forbidden, manager)
        for owned in ('NS_WG_INPUT', 'NS_WG_FORWARD', 'NS_WG_NAT', 'NS_AWG_INPUT', 'NS_AWG_FORWARD', 'NS_AWG_NAT'):
            self.assertIn(owned, manager)
        for protocol in ('wg', 'awg', 'vless', 'mieru', 'hy2'):
            self.assertIn(protocol, manager)
        self.assertIn('HYSTERIA=${NETSCOPE_VPN_HYSTERIA', manager)
        self.assertIn('hysteria.yaml', manager)
        self.assertIn('status [kind]', manager)
        self.assertIn("stop|rollback)", manager)
        self.assertIn("confirm)", manager)
        self.assertIn("sleep \"$GUARD_SECONDS\"", manager)

    def test_menu_and_device_identity(self):
        view = (FILES/'usr/lib/lua/luci/view/netscope/setup.htm').read_text(encoding='utf-8')
        self.assertIn('<h2>Быстрая настройка VPN</h2>', view)
        for protocol in ('wg', 'awg', 'vless', 'mieru', 'hy2'):
            self.assertIn('value="'+protocol+'"', view)
        self.assertIn('явного подтверждения', view)

    def test_hysteria2_draft_is_loopback_only_and_tls_guarded(self):
        model = (FILES/'usr/lib/lua/luci/model/netscope_setup.lua').read_text(encoding='utf-8')
        js = (FILES/'www/luci-static/netscope/setup.js').read_text(encoding='utf-8')
        self.assertIn("uri:match('^hysteria2://')", model)
        self.assertIn("uri:match('^hy2://')", model)
        self.assertIn("listen: 127.0.0.1:2083", model)
        self.assertIn("disableUDP: false", model)
        self.assertIn("Нельзя отключать проверку TLS без pinSHA256", model)
        self.assertIn("el('hy2-uri').value=''", js)
        self.assertNotIn('localStorage', js)

if __name__ == '__main__': unittest.main()
