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
        self.assertIn('wg awg vless mieru hy2', installer)
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
            'usr/libexec/netscope-install-hysteria',
            'usr/libexec/netscope-install-mieru',
            'usr/libexec/netscope-hy2-udp-probe',
            'usr/libexec/netscope-voice-route',
            'usr/libexec/netscope-voice-update',
            'usr/libexec/netscope-voice-monitor',
            'usr/libexec/netscope-voice-boot',
            'usr/libexec/netscope-l2tp-watchdog',
            'etc/init.d/netscope-voice',
            'etc/init.d/netscope-l2tp-watchdog',
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
        for forbidden in ('uci commit', 'wg-quick up', 'network restart', 'firewall restart'):
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

    def test_hysteria2_draft_has_loopback_socks_isolated_tun_and_tls_guard(self):
        model = (FILES/'usr/lib/lua/luci/model/netscope_setup.lua').read_text(encoding='utf-8')
        js = (FILES/'www/luci-static/netscope/setup.js').read_text(encoding='utf-8')
        self.assertIn("source:match('^hysteria2://')", model)
        self.assertIn("source:match('^hy2://')", model)
        self.assertIn("out.protocol=='hysteria'", model)
        self.assertIn("stream.network=='hysteria'", model)
        self.assertIn("tls.alpn[1]=='h3'", model)
        self.assertIn("listen: 127.0.0.1:2083", model)
        self.assertIn("disableUDP: false", model)
        self.assertIn("tun:\\n  name: nshy2\\n  mtu: 1380", model)
        self.assertIn("ipv4: 198.18.10.1/30", model)
        self.assertIn("Нельзя отключать проверку TLS без pinSHA256", model)
        self.assertIn("el('hy2-uri').value=''", js)
        self.assertNotIn('localStorage', js)
        manager = (FILES/'usr/libexec/netscope-vpn-profile').read_text(encoding='utf-8')
        self.assertIn('NETSCOPE_VPN_HY2_TUN_IFACE:-nshy2', manager)
        self.assertIn('link show dev "$TUN_IFACE"', manager)
        self.assertIn('HYSTERIA_DISABLE_UPDATE_CHECK=1', manager)
        self.assertIn('HYSTERIA=/mnt/sda1/qwrt-services/hysteria/bin/hysteria', manager)
        self.assertIn('MIERU=/mnt/sda1/qwrt-services/mieru/bin/mieru', manager)
        self.assertIn('NETSCOPE_SOCKS_PORT="$LOCAL_PORT" "$UDP_PROBE"', manager)
        self.assertIn('Mieru failed the end-to-end UDP probe', manager)

    def test_voice_route_is_narrow_atomic_and_fail_open(self):
        route = (FILES/'usr/libexec/netscope-voice-route').read_text(encoding='utf-8')
        update = (FILES/'usr/libexec/netscope-voice-update').read_text(encoding='utf-8')
        probe = (FILES/'usr/libexec/netscope-hy2-udp-probe').read_text(encoding='utf-8')
        self.assertIn('NS_VOICE_HY2', route)
        self.assertIn('ns_voice_discord', route)
        self.assertIn('ns_voice_discord_nets', route)
        self.assertIn("DISCORD_VOICE_NETS='66.22.192.0/18 104.29.128.0/19'", route)
        self.assertIn('ns_voice_telegram_nets', route)
        self.assertIn('discord.media', route)
        self.assertIn('route add default dev "$TUN_IFACE" table "$TABLE"', route)
        self.assertIn('-j MARK --set-xmark "$MARK"', route)
        self.assertIn('-m mark --mark "$MARK" -j ACCEPT', route)
        self.assertIn('"discord_nets":%s', route)
        self.assertIn('NS_VOICE_HY2_FWD', route)
        self.assertIn('-I PREROUTING 1 -i br-lan', route)
        self.assertIn('/usr/libexec/netscope-hy2-udp-probe', route)
        self.assertIn("os.getenv('NETSCOPE_SOCKS_PORT')", probe)
        self.assertIn('sleep 10', route)
        self.assertIn("HY2 or route unhealthy; voice interception removed (fail open)", route)

    def test_voice_autostart_and_l2tp_watchdog_are_opt_in_and_scoped(self):
        boot = (FILES/'usr/libexec/netscope-voice-boot').read_text(encoding='utf-8')
        monitor = (FILES/'usr/libexec/netscope-voice-monitor').read_text(encoding='utf-8')
        l2tp = (FILES/'usr/libexec/netscope-l2tp-watchdog').read_text(encoding='utf-8')
        voice_init = (FILES/'etc/init.d/netscope-voice').read_text(encoding='utf-8')
        l2tp_init = (FILES/'etc/init.d/netscope-l2tp-watchdog').read_text(encoding='utf-8')
        route = (FILES/'usr/libexec/netscope-voice-route').read_text(encoding='utf-8')
        update = (FILES/'usr/libexec/netscope-voice-update').read_text(encoding='utf-8')
        self.assertIn('autostart.conf', boot)
        self.assertIn('valid_id', boot)
        self.assertIn("$ROUTE\" stop", boot)
        self.assertIn('fail-open', boot)
        self.assertNotIn('network restart', boot)
        self.assertNotIn('firewall restart', boot)
        self.assertIn('health.jsonl', monitor)
        self.assertIn('MAX_HISTORY', monitor)
        self.assertIn('/proc/net/nf_conntrack', monitor)
        self.assertNotIn('payload', monitor.lower().replace('never reads packet payloads',''))
        self.assertIn('NS_L2TP_MSS', l2tp)
        self.assertIn('failures" -ge 3', l2tp)
        self.assertIn('office-vpn-up', l2tp)
        self.assertNotIn('network restart', l2tp)
        self.assertNotIn('firewall restart', l2tp)
        self.assertNotIn('/etc/rc.d/', voice_init)
        self.assertNotIn('/etc/rc.d/', l2tp_init)
        self.assertIn('start_service', voice_init)
        self.assertIn('start_service', l2tp_init)
        self.assertNotIn('TPROXY', route)
        self.assertNotIn('network restart', route)
        self.assertIn('core.telegram.org/resources/cidr.txt', update)
        self.assertIn('MetaCubeX/meta-rules-dat', update)
        self.assertIn('Loyalsoldier/geoip', update)
        self.assertIn("cmp -s \"$WORK/primary.txt\" \"$WORK/secondary.txt\"", update)
        self.assertIn("cmp -s \"$WORK/primary.txt\" \"$WORK/official.txt\"", update)
        self.assertNotIn('eval ', update)

    def test_hysteria_runtime_installer_is_pinned_and_never_starts_vpn(self):
        installer = (FILES/'usr/libexec/netscope-install-hysteria').read_text(encoding='utf-8')
        self.assertIn('VERSION=v2.11.0', installer)
        self.assertIn('SHA256=fa19cad58c8d2d93aae9be31bfbb75e40f8f8ee7563fbd9ae9f775334d46cd69', installer)
        self.assertIn('hysteria-linux-arm64', installer)
        self.assertIn('checksum mismatch', installer)
        self.assertNotIn('| sh', installer)
        self.assertNotIn('eval ', installer)
        self.assertNotIn('/etc/init.d/', installer)
        self.assertNotIn('iptables', installer)

    def test_mieru_runtime_installer_is_pinned_and_never_starts_vpn(self):
        installer = (FILES/'usr/libexec/netscope-install-mieru').read_text(encoding='utf-8')
        self.assertIn('VERSION=v3.36.1', installer)
        self.assertIn('SHA256=b11bd3ac2ad5f7f948a49bb5ff58ef24fed309fbe7a48594755e60fe72eb2477', installer)
        self.assertIn('BINARY_SHA256=0d27b450efc1970106c47ad3bd3bd7fdbfec56f22159382c92d270dd3feb3bfe', installer)
        self.assertIn('mieru_3.36.1_linux_arm64.tar.gz', installer)
        self.assertIn('archive checksum mismatch', installer)
        self.assertIn('extracted binary checksum mismatch', installer)
        self.assertNotIn('| sh', installer)
        self.assertNotIn('eval ', installer)
        self.assertNotIn('/etc/init.d/', installer)
        self.assertNotIn('iptables', installer)

if __name__ == '__main__': unittest.main()
