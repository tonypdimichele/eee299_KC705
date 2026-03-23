#!/usr/bin/env python3
"""Continuously transmit a fixed DAC test pattern over UDP.

Default payload pattern is repeating 0x55, 0xAA bytes so the FPGA can drive
an easily recognizable alternating waveform on the DAC outputs.
"""

import argparse
import socket
import time


def build_payload(packet_size: int, pattern: bytes) -> bytes:
    repeats = (packet_size + len(pattern) - 1) // len(pattern)
    return (pattern * repeats)[:packet_size]


def parse_hex_pattern(pattern_hex: str) -> bytes:
    cleaned = pattern_hex.replace(" ", "").replace(",", "")
    if len(cleaned) == 0 or len(cleaned) % 2 != 0:
        raise ValueError("--pattern-hex must contain an even number of hex characters")
    return bytes.fromhex(cleaned)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Continuously send a repeating UDP pattern for DAC scope tests"
    )
    parser.add_argument("--ip", default="192.168.1.128", help="FPGA destination IP")
    parser.add_argument("--tx-port", type=int, default=20000, help="FPGA destination UDP port")
    parser.add_argument("--bind-ip", default="0.0.0.0", help="Local source IP")
    parser.add_argument("--bind-port", type=int, default=40000, help="Local source UDP port")
    parser.add_argument("--packet-size", type=int, default=900, help="UDP payload bytes per packet")
    parser.add_argument(
        "--pattern-hex",
        default="55AA",
        help="Repeating byte pattern in hex (example: 55AA or 55,AA)",
    )
    parser.add_argument(
        "--tx-gap-us",
        type=int,
        default=50,
        help="Delay between packets in microseconds (0 for no delay)",
    )
    parser.add_argument(
        "--stats-sec",
        type=float,
        default=1.0,
        help="Print throughput stats every N seconds",
    )
    args = parser.parse_args()

    if not (1 <= args.tx_port <= 65535):
        raise ValueError("--tx-port must be in 1..65535")
    if not (1 <= args.bind_port <= 65535):
        raise ValueError("--bind-port must be in 1..65535")
    if args.packet_size <= 0:
        raise ValueError("--packet-size must be > 0")
    if args.tx_gap_us < 0:
        raise ValueError("--tx-gap-us must be >= 0")
    if args.stats_sec <= 0:
        raise ValueError("--stats-sec must be > 0")

    pattern = parse_hex_pattern(args.pattern_hex)
    payload = build_payload(args.packet_size, pattern)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 * 1024 * 1024)
    sock.bind((args.bind_ip, args.bind_port))

    print(
        f"Sending repeating pattern {pattern.hex()} to {args.ip}:{args.tx_port} "
        f"from {args.bind_ip}:{args.bind_port}"
    )
    print(
        f"Packet size={len(payload)} bytes, tx_gap_us={args.tx_gap_us}, "
        f"stats every {args.stats_sec}s"
    )
    print("Press Ctrl+C to stop")

    packets = 0
    sent_bytes = 0
    t0 = time.time()
    last_stat = t0
    sleep_sec = args.tx_gap_us / 1_000_000.0

    try:
        while True:
            sock.sendto(payload, (args.ip, args.tx_port))
            packets += 1
            sent_bytes += len(payload)

            now = time.time()
            if now - last_stat >= args.stats_sec:
                elapsed = now - t0
                rate_bps = (sent_bytes * 8) / elapsed if elapsed > 0 else 0.0
                rate_Bps = sent_bytes / elapsed if elapsed > 0 else 0.0
                print(
                    f"TX packets={packets} bytes={sent_bytes} "
                    f"rate={rate_Bps/1e6:.3f} MB/s ({rate_bps/1e6:.3f} Mb/s)"
                )
                last_stat = now

            if sleep_sec > 0:
                time.sleep(sleep_sec)
    except KeyboardInterrupt:
        elapsed = time.time() - t0
        print("\nStopped")
        if elapsed > 0:
            print(
                f"Final: packets={packets} bytes={sent_bytes} "
                f"avg={(sent_bytes/elapsed)/1e6:.3f} MB/s"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
