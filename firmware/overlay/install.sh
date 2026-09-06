#!/bin/sh
# NETSCOPE overlay installer for the exact Xiaomi BE7000 QWRT R26.2.2 base.
# It never writes firmware partitions and never restarts network/firewall/VPN.
set -eu
umask 077

die() { echo "NETSCOPE installer: $*" >&2; exit 1; }
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
action=${1:-install}

clear_luci_cache() {
    rm -f /tmp/luci-indexcache
    for cache in /tmp/luci-modulecache/*6E657473636F7065*; do
        test -f "$cache" && test ! -L "$cache" && rm -f "$cache"
    done
    return 0
}

restore_backup() {
    backup=$1
    case "$backup" in /mnt/sda1/NETSCOPE/backups/overlay.*) ;; *) die 'unsafe backup path' ;; esac
    test -f "$backup/before.tar.gz" || die 'backup archive is missing'
    test -f "$backup/new.txt" || die 'backup inventory is missing'
    if test -x /etc/init.d/netscope-capture; then /etc/init.d/netscope-capture stop || true; fi
    tar -xzf "$backup/before.tar.gz" -C /
    while IFS= read -r target; do
        case "$target" in
            etc/init.d/netscope-*|etc/netscope/wifi7/*|usr/lib/lua/luci/controller/netscope*|usr/lib/lua/luci/model/netscope*|usr/lib/lua/luci/view/netscope*|usr/lib/lua/luci/view/themes/netscope/*|usr/libexec/netscope-*|www/luci-static/netscope/*|www/luci-static/resources/netscope/*)
                rm -f "/$target" ;;
            *) die "unsafe rollback target: $target" ;;
        esac
    done < "$backup/new.txt"
    if test -f "$backup/luci.conf"; then cp "$backup/luci.conf" /etc/config/luci; fi
    clear_luci_cache
    if test -x /etc/init.d/netscope-capture; then /etc/init.d/netscope-capture start || true; fi
    echo "NETSCOPE restored from $backup"
}

if test "$action" = rollback; then
    test "$#" -eq 2 || die 'usage: install.sh rollback /mnt/sda1/NETSCOPE/backups/overlay.NAME'
    restore_backup "$2"
    exit 0
fi
test "$action" = install || die 'usage: install.sh [install|rollback BACKUP]'
test "$#" -le 1 || die 'unexpected arguments'

test -d "$script_dir/payload" || die 'payload directory is missing'
test -f "$script_dir/manifest.tsv" || die 'manifest is missing'
test -f "$script_dir/SHA256SUMS" || die 'checksums are missing'
(cd "$script_dir" && sha256sum -c SHA256SUMS) || die 'release checksum verification failed'

command -v ubus >/dev/null 2>&1 || die 'ubus is unavailable'
command -v jsonfilter >/dev/null 2>&1 || die 'jsonfilter is unavailable'
board_file=$(mktemp /tmp/netscope-board.XXXXXX)
trap 'rm -f "$board_file"' EXIT HUP INT TERM
ubus call system board > "$board_file"
test "$(jsonfilter -i "$board_file" -e '@.board_name')" = xiaomi,be7000 || die 'this release supports only Xiaomi BE7000'
test "$(jsonfilter -i "$board_file" -e '@.release.target')" = ipq95xx/generic || die 'unexpected QWRT target'
case "$(jsonfilter -i "$board_file" -e '@.release.revision')" in *'R26.2.2'*) ;; *) die 'exact QWRT R26.2.2 base required' ;; esac

grep -q ' /mnt/sda1 ' /proc/mounts || die 'writable USB at /mnt/sda1 is required'
mkdir -p /mnt/sda1/NETSCOPE/backups /mnt/sda1/NETSCOPE/releases
test -w /mnt/sda1/NETSCOPE || die 'USB storage is not writable'

if test -x /usr/libexec/netscope-capture && /usr/libexec/netscope-capture status 2>/dev/null | grep -q '"active":true'; then
    die 'turn NETSCOPE Capture off before updating'
fi
if test -x /usr/libexec/netscope-vpn-profile; then
    for kind in wg awg vless mieru hy2; do
        if /usr/libexec/netscope-vpn-profile status "$kind" 2>/dev/null | grep -Eq '"(active|pending)":true'; then
            die "stop the NETSCOPE $kind profile before updating"
        fi
    done
fi

backup=$(mktemp -d /mnt/sda1/NETSCOPE/backups/overlay.XXXXXX)
existing=$backup/existing.txt
new=$backup/new.txt
: > "$existing"; : > "$new"

while IFS="$(printf '\t')" read -r target sha mode component; do
    test -n "$target" || continue
    case "$target" in
        etc/init.d/netscope-*|etc/netscope/wifi7/*|usr/lib/lua/luci/controller/netscope*|usr/lib/lua/luci/model/netscope*|usr/lib/lua/luci/view/netscope*|usr/lib/lua/luci/view/themes/netscope/*|usr/libexec/netscope-*|www/luci-static/netscope/*|www/luci-static/resources/netscope/*) ;;
        *) die "unsafe manifest target: $target" ;;
    esac
    test ! -L "/$target" || die "symlink target refused: $target"
    test ! -L "$(dirname "/$target")" || die "symlink parent refused: $target"
    if test -e "/$target"; then printf '%s\n' "$target" >> "$existing"; else printf '%s\n' "$target" >> "$new"; fi
done < "$script_dir/manifest.tsv"

test -f /etc/config/luci && cp /etc/config/luci "$backup/luci.conf"
tar -czf "$backup/before.tar.gz" -C / -T "$existing"
cp "$script_dir/manifest.tsv" "$script_dir/manifest.json" "$script_dir/SHA256SUMS" "$backup/"

rollback_on_error() {
    trap - EXIT HUP INT TERM
    restore_backup "$backup"
    die "installation failed; previous files restored from $backup"
}
trap rollback_on_error EXIT HUP INT TERM

if test -x /etc/init.d/netscope-capture; then /etc/init.d/netscope-capture stop; fi
while IFS="$(printf '\t')" read -r target sha mode component; do
    test -n "$target" || continue
    source=$script_dir/payload/$target
    test "$(sha256sum "$source" | cut -d ' ' -f 1)" = "$sha" || die "payload changed: $target"
    mkdir -p "$(dirname "/$target")"
    cp "$source" "/$target.new"
    chmod "$mode" "/$target.new"
    mv "/$target.new" "/$target"
done < "$script_dir/manifest.tsv"

# UI-only UCI change; the previous file is in the rollback archive.
uci set luci.main.mediaurlbase='/luci-static/netscope'
uci set luci.main.lang='ru'
uci commit luci
clear_luci_cache

/etc/init.d/netscope-capture enable
/etc/init.d/netscope-capture start
sleep 1
/usr/libexec/netscope-capture status | grep -q '"active":false' || die 'Capture did not recover to OFF'
cp "$script_dir/manifest.json" /mnt/sda1/NETSCOPE/releases/installed-overlay.json

trap - EXIT HUP INT TERM
rm -f "$board_file"
echo "NETSCOPE overlay installed with Capture OFF. Backup: $backup"
echo "Rollback: sh $script_dir/install.sh rollback $backup"
