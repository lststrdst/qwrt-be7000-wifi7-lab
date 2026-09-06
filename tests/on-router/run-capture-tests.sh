#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: run-capture-tests.sh NETSCOPE_CAPTURE_MODEL NETSCOPE_CAPTURE_PROXY" >&2
  exit 2
fi

MODEL=$1
PROXY=$2
test -f "$MODEL"
test -f "$PROXY"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CASE=$(mktemp -d /tmp/netscope-capture-it.XXXXXX)

cleanup() {
  case "$CASE" in
    /tmp/netscope-capture-it.*) rm -rf "$CASE" ;;
    *) echo "refusing unsafe cleanup path" >&2; exit 1 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$CASE/unmounted"
NETSCOPE_CAPTURE_ROOT="$CASE/unmounted/NETSCOPE" \
NETSCOPE_CAPTURE_MOUNT="$CASE/unmounted" \
NETSCOPE_CAPTURE_RUN="$CASE/run" \
  lua "$HERE/test_capture.lua" "$MODEL" "$PROXY"
