# NETSCOPE IoT monitor

[English](README.en.md)

Лёгкий read-only компонент NETSCOPE для QWRT/OpenWrt. Он помогает отличить
потерю ассоциации Wi-Fi от сбоя DHCP, DNS, WAN или облачного сервиса устройства.

Монитор записывает:

- интерфейс `ath0`/`ath1`/`ath2`, на котором видна каждая заданная станция;
- строку `wlanconfig` с RSSI, режимом и текущими скоростями;
- IP из актуальной DHCP lease и результат ping устройства;
- доступность WAN по IP и проверку локального DNS;
- отфильтрованные события hostapd, WLAN, CNSS, DHCP, dnsmasq и WAN.

Скрипт не меняет Wi-Fi, firewall, DNS или маршруты и по умолчанию не
добавляется в автозагрузку.

## Установка на USB

```sh
mkdir -p /mnt/sda1/NETSCOPE/iot-monitor/logs
cp netscope-iot-monitor.sh /mnt/sda1/NETSCOPE/iot-monitor/
cp targets.example /mnt/sda1/NETSCOPE/iot-monitor/targets.conf
chmod 700 /mnt/sda1/NETSCOPE/iot-monitor/netscope-iot-monitor.sh
chmod 600 /mnt/sda1/NETSCOPE/iot-monitor/targets.conf
```

Формат одной строки `targets.conf`:

```text
метка|MAC|резервный_IP
```

Резервный IP необязателен: сначала монитор ищет действующий адрес по MAC в
`/tmp/dhcp.leases`.

Запуск:

```sh
nohup /mnt/sda1/NETSCOPE/iot-monitor/netscope-iot-monitor.sh \
  >/mnt/sda1/NETSCOPE/iot-monitor/logs/runner.log 2>&1 </dev/null &
```

Остановка:

```sh
kill "$(cat /mnt/sda1/NETSCOPE/iot-monitor/iot-monitor.pid)"
```

Результаты находятся в `logs/health.log` и `logs/events.log`. При достижении
8 МиБ файл вращается; хранятся текущий журнал и три предыдущих поколения.

После сбоя сначала отметьте точное время и скопируйте журналы, не перезапуская
радио или устройство.
