# NETSCOPE — firmware for Xiaomi BE7000, based on QWRT

[Русский](README.md) | **English**

[![Tests](https://github.com/lststrdst/qwrt-be7000-wifi7-lab/actions/workflows/tests.yml/badge.svg)](https://github.com/lststrdst/qwrt-be7000-wifi7-lab/actions/workflows/tests.yml)

I am developing NETSCOPE as a firmware project for Xiaomi BE7000 (RC06),
based on QWRT R26.02.02 / QSDK 12.5. The goal is a coherent home gateway:
an English LuCI shell, network visibility, guarded VPN setup, documented
recovery and an explicitly experimental Wi‑Fi 7/MLO lab.

NETSCOPE keeps its base visible as `Based on QWRT` and preserves the original
QWRT attribution. It is not an official QWRT project.

> There is no public flashable NETSCOPE image yet. This repository contains
> component sources, tests, sanitized examples and release gates. A firmware
> image will only be published after the build base, backup slot and recovery
> path are reproducible.

## Why I built this

The BE7000 is my primary home gateway. It carries direct internet traffic,
remote access, IoT devices, an office tunnel and selective routing. QWRT is the
low-level base I need, but daily operation benefits from safer transactions,
one consistent UI and diagnostics that do not require ad-hoc shell commands.

The project follows four rules:

- keep the original QWRT functionality reachable;
- give every network change a preflight, isolated scope and rollback path;
- keep live credentials and device-specific data out of Git;
- keep experimental features off by default and label them honestly.

## Current components

| Component | Purpose | Status |
|---|---|---|
| NETSCOPE Dark | English LuCI shell, login, menu search and base version | running on the test router; image packaging pending |
| Traffic / NETSCOPE | devices, conntrack, directions, ports, PCAP sessions | prototype and runtime components available |
| VPN Quick setup | WG, AWG, VLESS/Xray and Mieru from LuCI | drafts and preflight; plain WG has an isolated watchdog runtime |
| Recovery | known-good state, backups and return procedure | documented; no image released |
| IoT monitor | rolling Wi‑Fi, WAN and DNS evidence | available as a standalone tool |
| Wi‑Fi 7 / MLO Lab | restore the vendor 5G-low + 5G-high topology | model and tests only; no live apply |

See [firmware/README.md](firmware/README.md) for the source layout and
[firmware/RELEASE-CHECKLIST.md](firmware/RELEASE-CHECKLIST.md) for release
gates. The test-only interface is available as the
[Wi-Fi 7 Lab Figma screen](https://www.figma.com/design/SlXSi90WevQOkB78HuLdFp?node-id=56-318).

## IoT network rationale

Low-power 2.4 GHz devices intermittently lost internet connectivity on the
combined network while WAN remained healthy. A speaker was moved to a separate
2.4 GHz IoT SSID for diagnosis and stability; a vacuum was later added. The
main LAN should get only the local control paths it needs, and IoT remains
outside MLO experiments. This is evidence from this client/firmware
combination, not a claim that the MLO standard itself is broken.

The sanitized design is documented in [docs/IOT-NETWORK.md](docs/IOT-NETWORK.md).

## Wi‑Fi 7 / MLO boundary

The Xiaomi firmware can split the external radio into two 5 GHz PHYs and join
them into one MLD. The current QWRT boot uses the QCN9224 in single-PHY mode.
Reproducing the vendor topology requires a coherent GPIO, BDF, ART offset,
CNSS and MLO startup sequence.

The repository now models a no-UART runtime trial as well as the original
UART-gated hardware transaction. The no-UART model only accepts post-boot RAM
state: no UCI commit, autostart, boot files, boot environment, MTD or ART
writes. Ordinary failures roll back in the model; a kernel hang is explicitly
classified as requiring a local cold power cycle. This reduces persistent
brick risk but does not prove GPIO electrical safety or RF behavior.

The full topology, failure matrix and acceptance gates are in
[docs/WIFI7-MLO.md](docs/WIFI7-MLO.md). Live activation remains absent.

## Run the tests

```bash
python -m pip install -e .
python -m unittest discover -s tests -v
python -m be7000_wifi7_lab profiles/be7000-rc06-qwrt-r26.02.02.json
python tools/check_public.py
```

The matrix covers driver, PHY, MLD, LAN, WAN and confirmation failures,
kernel hang, reboot before confirmation, baseline drift and every forbidden
persistence path. The public helper still exposes only `status`, `preflight`
and `render`.

## Repository scope

- [`firmware`](firmware) — future image profile, LuCI packages and release gates.
- [`src/be7000_wifi7_lab`](src/be7000_wifi7_lab) — hardware and RAM-only control-flow models.
- [`tests`](tests) — positive, negative and recovery cases.
- [`openwrt-package`](openwrt-package) — render-only MLO Lab package.
- [`docs/WIFI7-MLO.md`](docs/WIFI7-MLO.md) — dedicated Wi‑Fi 7 engineering note.
- [`docs/IOT-NETWORK.md`](docs/IOT-NETWORK.md) — IoT isolation rationale and diagnostics.
- [`docs/INSTALL-SSH-XMIR.md`](docs/INSTALL-SSH-XMIR.md) — XMiR/SSH preparation notes.
- [`docs/RECOVERY.md`](docs/RECOVERY.md) — Russian administrator recovery runbook.
- [`examples`](examples) — sanitized L2TP/IPsec, VLESS and AmneziaWG templates.
- [`tools/iot-monitor`](tools/iot-monitor) — rolling evidence collector for IoT faults.
- [`SECURITY.md`](SECURITY.md) — data that must never be published.

## References

- [OpenWrt source and build system](https://openwrt.org/docs/guide-developer/source-code/start)
- [OpenWrt Xiaomi BE7000 support work](https://github.com/openwrt/openwrt/pull/20604)
- [Xiaomi Wi‑Fi 7 FAQ](https://www.mi.com/global/support/article/KA-12725/)
- [NETSCOPE repository](https://github.com/lststrdst/qwrt-be7000-wifi7-lab)
