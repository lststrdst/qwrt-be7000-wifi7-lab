# QWRT BE7000 Wi-Fi 7 / MLO Lab

[Русский](README.md) | **English**

[![Tests](https://github.com/lststrdst/qwrt-be7000-wifi7-lab/actions/workflows/tests.yml/badge.svg)](https://github.com/lststrdst/qwrt-be7000-wifi7-lab/actions/workflows/tests.yml)

An independent, fail-closed research scaffold for bringing the Xiaomi BE7000
(RC06) stock-like Wi-Fi 7 topology to QWRT R26.02.02 / QSDK 12.5.

> This repository is **not an official QWRT source fork**, a ready-to-flash
> firmware image, or a one-click Wi-Fi 7 enabler.

## Why I built this

I use the BE7000 as a real home gateway, not as a disposable test board. The
stock Xiaomi firmware can expose three radios — 2.4 GHz, 5 GHz low and 5 GHz
high — and combine the two 5 GHz links into one MLD. QWRT R26.02.02 contains
substantial EHT/MLO machinery, but its default boot state exposes only two PHYs
and loads the external QCN9224 in single-PHY mode.

The tempting solution is to copy a few forum commands into an init script.
That is also an easy way to lose every management path to the router. I built
this project to turn that experiment into a reviewable transaction with exact
inputs, explicit gates, negative tests and a defined rollback state.

## What is known

The vendor control flow recovered from a Xiaomi BE7000 RC06 firmware image uses
the following state:

| State | GPIO 453 | GPIO 454 | ART offset | CNSS BDF | MLO |
|---|---:|---:|---:|---:|---:|
| Split / three PHY | 1 | 0 | `0x33000` | `0x1008` | enabled, mask 2 |
| Single / rollback | 0 | 1 | `0x65000` | `0x2` | disabled |

Both calibration slices are 184,320 bytes. In split mode, the target topology
is 5 GHz low at 160 MHz plus 5 GHz high at 80 MHz, joined as `5g + 5gh` under a
single MLD. This is not a 320 MHz or 6 GHz implementation.

The repository records the behavior, hashes locally supplied evidence during
private testing, and models state transitions. It does not redistribute vendor
firmware, extracted scripts, board-data files or device calibration material.

## Current status

- Exact vendor split and rollback constants documented.
- Deterministic state-machine model with success, block and rollback cases.
- CI tests require missing UART/electrical confirmation to fail closed.
- Wrong calibration and failed health checks restore the single-PHY model.
- No live `insmod`, GPIO writes, Wi-Fi reload, MTD writes or boot-variable
  changes are implemented.

The private hardware-specific lab completed 39 checks and a real QWRT
`opkg --offline-root` test without changing the live router. That result is
evidence for the packaging and control flow, not proof that RF/MLO works.

## Safety boundary

A virtual machine cannot emulate the BE7000's QCN9224 RF path, PCIe power
sequencing, board GPIO electrical behavior, EHT beaconing or client
association. A real hardware probe therefore requires:

1. A working 1.8 V UART console.
2. Verified backups of ART, boot metadata and the active configuration.
3. A RAM-first experiment with no autostart.
4. An out-of-band watchdog that restores the known single-PHY state.
5. A Wi-Fi 7 client capable of the required 5 GHz low + high MLO combination.

Until those gates pass, this project intentionally stops before activation.

## Run the model

```bash
python -m pip install -e .
python -m unittest discover -s tests -v
python -m be7000_wifi7_lab profiles/be7000-rc06-qwrt-r26.02.02.json
```

## Repository scope

- [`src/be7000_wifi7_lab`](src/be7000_wifi7_lab) — pure state-transition model.
- [`profiles`](profiles) — non-secret public constants and safety gates.
- [`tests`](tests) — block, rollback and mocked-success cases.
- [`openwrt-package`](openwrt-package) — render-only OpenWrt package source.
- [`docs/STOCK_SEQUENCE.md`](docs/STOCK_SEQUENCE.md) — evidence summary.
- [`docs/SAFETY.md`](docs/SAFETY.md) — rules for a future hardware stage.

## References

- [OpenWrt source and build system](https://openwrt.org/docs/guide-developer/source-code/start)
- [OpenWrt Xiaomi BE7000 support pull request](https://github.com/openwrt/openwrt/pull/20604)
- [Xiaomi Wi-Fi 7 FAQ](https://www.mi.com/global/support/article/KA-12725/)
- [BE7000 QWRT R26.02.02 community thread](https://4pda.to/forum/index.php?showtopic=1070166&view=findpost&p=138861971)
