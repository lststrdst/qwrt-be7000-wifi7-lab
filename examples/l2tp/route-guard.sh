#!/bin/sh

set -eu

OFFICE_PREFIXES=${OFFICE_PREFIXES:-'10.20.0.0/16 172.20.50.10/32'}
BLACKHOLE_METRIC=${BLACKHOLE_METRIC:-32760}

case "${1:-}" in
	install)
		for prefix in $OFFICE_PREFIXES; do
			ip route replace blackhole "$prefix" metric "$BLACKHOLE_METRIC"
		done
		;;
	up)
		iface=${2:?PPP interface is required}
		for prefix in $OFFICE_PREFIXES; do
			ip route replace "$prefix" dev "$iface" metric 10
		done
		;;
	down)
		iface=${2:?PPP interface is required}
		for prefix in $OFFICE_PREFIXES; do
			ip route del "$prefix" dev "$iface" metric 10 2>/dev/null || true
		done
		;;
	*)
		echo 'usage: route-guard.sh {install|up IFACE|down IFACE}' >&2
		exit 1
		;;
esac
