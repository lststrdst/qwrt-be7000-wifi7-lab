#!/bin/sh

set -u

BASE=${IOT_MONITOR_BASE:-/mnt/sda1/qwrt-services/iot-monitor}
LOG_DIR="$BASE/logs"
TARGETS_FILE=${IOT_MONITOR_TARGETS:-$BASE/targets.conf}
PID_FILE="$BASE/iot-monitor.pid"
EVENT_PID_FILE="$BASE/logread.pid"
INTERVAL=${IOT_MONITOR_INTERVAL:-15}
MAX_BYTES=${IOT_MONITOR_MAX_BYTES:-8388608}

mkdir -p "$LOG_DIR"
umask 077

if [ ! -s "$TARGETS_FILE" ]; then
    echo "Missing targets file: $TARGETS_FILE" >&2
    exit 1
fi

if [ -s "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        echo "iot-monitor is already running: pid $old_pid"
        exit 0
    fi
fi

echo $$ > "$PID_FILE"

rotate_file() {
    file=$1
    [ -f "$file" ] || return 0
    size=$(wc -c < "$file" 2>/dev/null || echo 0)
    [ "$size" -lt "$MAX_BYTES" ] && return 0
    rm -f "$file.3"
    [ ! -f "$file.2" ] || mv "$file.2" "$file.3"
    [ ! -f "$file.1" ] || mv "$file.1" "$file.2"
    mv "$file" "$file.1"
}

cleanup() {
    event_pid=$(cat "$EVENT_PID_FILE" 2>/dev/null || true)
    [ -z "$event_pid" ] || kill "$event_pid" 2>/dev/null || true
    rm -f "$PID_FILE" "$EVENT_PID_FILE"
}
trap cleanup EXIT INT TERM

logread -f 2>/dev/null |
    grep -Ei 'hostapd|dnsmasq|netifd|wlan|wifi|ath[0-9]|deauth|disassoc|dhcp|cnss|udhcpc|wan' \
    >> "$LOG_DIR/events.log" &
echo $! > "$EVENT_PID_FILE"

counter=0
while :; do
    rotate_file "$LOG_DIR/health.log"
    rotate_file "$LOG_DIR/events.log"

    {
        echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') ==="
        echo "uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)"

        while IFS='|' read -r label mac fallback_ip; do
            case "$label" in
                ''|'#'*) continue ;;
            esac

            lease_ip=$(awk -v wanted="$mac" '
                tolower($2) == tolower(wanted) { print $3; exit }
            ' /tmp/dhcp.leases 2>/dev/null || true)
            target_ip=${lease_ip:-$fallback_ip}
            station=''
            station_if='absent'

            for iface in ath0 ath1 ath2; do
                row=$(wlanconfig "$iface" list sta 2>/dev/null |
                    grep -i "^$mac" | head -n 1 || true)
                if [ -n "$row" ]; then
                    station_if=$iface
                    station=$row
                    break
                fi
            done

            echo "target=$label"
            echo "station_interface=$station_if"
            [ -z "$station" ] || echo "station=$station"
            echo "lease_ip=${target_ip:-unknown}"

            if [ -z "$target_ip" ]; then
                echo 'target_ping=unknown'
            elif ping -c 1 -W 1 "$target_ip" >/tmp/iot-monitor-target-ping 2>&1; then
                echo 'target_ping=ok'
                tail -n 2 /tmp/iot-monitor-target-ping 2>/dev/null || true
            else
                echo 'target_ping=fail'
                tail -n 2 /tmp/iot-monitor-target-ping 2>/dev/null || true
            fi
        done < "$TARGETS_FILE"

        if ping -c 1 -W 1 1.1.1.1 >/tmp/iot-monitor-wan-ping 2>&1; then
            echo 'wan_ping=ok'
        else
            echo 'wan_ping=fail'
        fi
        tail -n 2 /tmp/iot-monitor-wan-ping 2>/dev/null || true

        if [ $((counter % 4)) -eq 0 ]; then
            if nslookup example.com 127.0.0.1 >/tmp/iot-monitor-dns 2>&1; then
                echo 'dns=ok'
            else
                echo 'dns=fail'
            fi
            tail -n 6 /tmp/iot-monitor-dns 2>/dev/null || true
        fi
        echo
    } >> "$LOG_DIR/health.log"

    counter=$((counter + 1))
    sleep "$INTERVAL"
done
