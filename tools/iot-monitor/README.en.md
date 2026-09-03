# IoT connectivity monitor

[Русский](README.md)

This lightweight read-only monitor for QWRT/OpenWrt helps distinguish a Wi-Fi
association loss from DHCP, DNS, WAN or device-cloud failures.

It records the radio interface on which each configured station is visible,
the relevant `wlanconfig` row, its current DHCP address and ping result, WAN
reachability, local DNS health, and filtered networking events. It does not
change Wi-Fi, firewall, DNS or routing and is not installed as an autostart
service.

Copy `iot-monitor.sh` and `targets.example` to a private directory on USB,
rename the example to `targets.conf`, and replace its locally administered
placeholder MAC addresses. Each line uses:

```text
label|MAC|optional_fallback_IP
```

Start it with:

```sh
nohup /mnt/sda1/qwrt-services/iot-monitor/iot-monitor.sh \
  >/mnt/sda1/qwrt-services/iot-monitor/logs/runner.log 2>&1 </dev/null &
```

The rolling output is written to `logs/health.log` and `logs/events.log`.
Record the exact failure time and copy both logs before restarting the radio
or the affected device.
