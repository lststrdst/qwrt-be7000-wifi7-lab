#!/bin/sh

set -eu

AWG_GO=${AWG_GO:-/mnt/sda1/qwrt-services/amneziawg/bin/amneziawg-go}
AWG=${AWG:-/mnt/sda1/qwrt-services/amneziawg/bin/awg}
CONFIG=${CONFIG:-/etc/amneziawg/awg_remote.conf}
IFACE=${IFACE:-awg_remote}
ADDRESS=${ADDRESS:-10.77.0.1/24}

[ -x "$AWG_GO" ] || { echo "missing executable: $AWG_GO" >&2; exit 1; }
[ -x "$AWG" ] || { echo "missing executable: $AWG" >&2; exit 1; }
[ -r "$CONFIG" ] || { echo "missing private config: $CONFIG" >&2; exit 1; }

umask 077
if ! ip link show "$IFACE" >/dev/null 2>&1; then
	"$AWG_GO" -f "$IFACE" &
fi

tries=0
while ! ip link show "$IFACE" >/dev/null 2>&1; do
	tries=$((tries + 1))
	[ "$tries" -lt 20 ] || { echo 'userspace interface did not appear' >&2; exit 1; }
	sleep 1
done

"$AWG" setconf "$IFACE" "$CONFIG"
ip address replace "$ADDRESS" dev "$IFACE"
ip link set up dev "$IFACE"
echo "$IFACE is ready; firewall rules are intentionally not installed by this example"
