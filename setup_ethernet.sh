#!/usr/bin/env bash
set -e

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

IFACE="$1"

# Auto-detect: first physical, non-wireless interface
if [ -z "$IFACE" ]; then
    for dev in /sys/class/net/*; do
        name="$(basename "$dev")"
        [ "$name" = "lo" ] && continue
        [ -e "$dev/device" ] || continue
        [ -d "$dev/wireless" ] && continue
        IFACE="$name"
        break
    done
fi

if [ -z "$IFACE" ] || [ ! -e "/sys/class/net/$IFACE" ]; then
    echo "Could not find ethernet interface '${IFACE}'. Available interfaces:"
    ls /sys/class/net
    exit 1
fi

echo "Using interface: $IFACE"

ip link set dev "$IFACE" up
ip -4 addr flush dev "$IFACE"
ip addr add 192.168.1.10/24 dev "$IFACE"

ip addr show dev "$IFACE"
read -rp "Press Enter to continue..."
