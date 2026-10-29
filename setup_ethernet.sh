#!/usr/bin/env bash
set -e

IFACE="${1:-eth0}"

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

ip link set dev "$IFACE" up
ip -4 addr flush dev "$IFACE"
ip addr add 192.168.1.10/24 dev "$IFACE"

ip addr show dev "$IFACE"
read -rp "Press Enter to continue..."
