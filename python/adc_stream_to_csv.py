#!/usr/bin/env python3
"""Capture KC705 ADC1 UDP stream and write decoded samples to CSV.

Expected byte order from FPGA stream:
    adc1_msb_nibble, adc1_lsb (repeating)

Each ADC sample is reconstructed as:
    code = ((msb_nibble_byte & 0x0F) << 8) | lsb_byte

This matches the top-level HDL packing where each 12-bit averaged ADC1 sample is
split into two bytes with zero-padded upper nibble in the MSB byte.
"""

import argparse
import csv
import datetime as dt
import pathlib
import socket
import sys
import time


def decode_adc1_sample(b0: int, b1: int) -> int:
    """Decode one ADC1 sample from 2 stream bytes."""
    return ((b0 & 0x0F) << 8) | b1


def offset_binary_code_to_volts(code: int, vref: float) -> float:
    """Convert 12-bit offset-binary code to differential volts around midscale."""
    # AD9627 transfer: -VREF..+VREF maps to 0..4095 in offset-binary.
    return ((code - 2048) / 2048.0) * vref


def parse_hex_bytes(s: str) -> bytes:
    vals = [x for x in s.replace(",", " ").split() if x]
    if not vals:
        return b""
    return bytes(int(v, 16) for v in vals)


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture ADC UDP stream into CSV")
    parser.add_argument("--bind-ip", default="0.0.0.0", help="Local bind IP")
    parser.add_argument("--bind-port", type=int, default=40000, help="Local bind UDP port")
    parser.add_argument(
        "--fpga-ip",
        default="192.168.1.128",
        help="FPGA destination IP for startup training packet",
    )
    parser.add_argument(
        "--tx-port",
        type=int,
        default=20000,
        help="FPGA destination UDP port for startup training packet",
    )
    parser.add_argument(
        "--training-hex",
        default="00",
        help="Hex byte payload for startup training packet (e.g. '00' or 'aa bb cc')",
    )
    parser.add_argument(
        "--no-training",
        action="store_true",
        help="Disable automatic startup training packet",
    )
    parser.add_argument(
        "--expect-ip",
        default="",
        help="Optional expected FPGA source IP (empty disables check)",
    )
    parser.add_argument(
        "--expect-src-port",
        type=int,
        default=30000,
        help="Expected FPGA UDP source port (<=0 disables check)",
    )
    parser.add_argument("--recv-size", type=int, default=8192, help="Socket recv buffer size")
    parser.add_argument("--timeout", type=float, default=0.5, help="Socket timeout seconds")
    parser.add_argument(
        "--duration-sec",
        type=float,
        default=10.0,
        help="Capture duration in seconds (<=0 runs until Ctrl+C or --max-pairs)",
    )
    parser.add_argument(
        "--max-pairs",
        type=int,
        default=0,
        help="Stop after N decoded sample pairs (<=0 disables)",
    )
    parser.add_argument(
        "--vref",
        type=float,
        default=1.0,
        help="ADC VREF in volts for code-to-volts conversion",
    )
    parser.add_argument(
        "--output",
        default="adc_capture.csv",
        help="Output CSV path",
    )
    parser.add_argument(
        "--flush-every",
        type=int,
        default=2000,
        help="Flush CSV every N decoded pairs",
    )
    args = parser.parse_args()

    if args.recv_size <= 0:
        raise ValueError("--recv-size must be > 0")
    if args.timeout <= 0:
        raise ValueError("--timeout must be > 0")
    if args.tx_port <= 0 or args.tx_port > 65535:
        raise ValueError("--tx-port must be in 1..65535")

    training_payload = parse_hex_bytes(args.training_hex)
    if not args.no_training and len(training_payload) == 0:
        raise ValueError("--training-hex produced empty payload")

    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((args.bind_ip, args.bind_port))
    sock.settimeout(args.timeout)

    if not args.no_training:
        sock.sendto(training_payload, (args.fpga_ip, args.tx_port))
        print(
            f"Sent startup training packet: {len(training_payload)} byte(s) "
            f"to {args.fpga_ip}:{args.tx_port}"
        )

    print(f"Listening on {args.bind_ip}:{args.bind_port}")
    if args.expect_ip:
        print(f"Expecting source IP: {args.expect_ip}")
    if args.expect_src_port > 0:
        print(f"Expecting source UDP port: {args.expect_src_port}")
    print(f"Writing CSV to {out_path}")

    start = time.time()
    stop_at = start + args.duration_sec if args.duration_sec > 0 else None

    packets = 0
    bytes_rx = 0
    dropped_src = 0
    pairs = 0
    carry = bytearray()

    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "host_time_iso",
                "sample_index",
                "adc1_code",
                "adc1_volts_diff",
                "b0_adc1_msb",
                "b1_adc1_lsb",
            ]
        )

        try:
            while True:
                now = time.time()
                if stop_at is not None and now >= stop_at:
                    break
                if args.max_pairs > 0 and pairs >= args.max_pairs:
                    break

                try:
                    payload, (src_ip, src_port) = sock.recvfrom(args.recv_size)
                except socket.timeout:
                    continue

                if args.expect_ip and src_ip != args.expect_ip:
                    dropped_src += 1
                    continue
                if args.expect_src_port > 0 and src_port != args.expect_src_port:
                    dropped_src += 1
                    continue

                packets += 1
                bytes_rx += len(payload)

                carry.extend(payload)
                n_groups = len(carry) // 2
                if n_groups == 0:
                    continue

                ts = dt.datetime.now().isoformat(timespec="milliseconds")
                for i in range(n_groups):
                    b0 = carry[2 * i + 0]
                    b1 = carry[2 * i + 1]
                    adc1_code = decode_adc1_sample(b0, b1)
                    adc1_v = offset_binary_code_to_volts(adc1_code, args.vref)

                    writer.writerow(
                        [
                            ts,
                            pairs,
                            adc1_code,
                            f"{adc1_v:.9f}",
                            f"0x{b0:02X}",
                            f"0x{b1:02X}",
                        ]
                    )
                    pairs += 1

                    if args.max_pairs > 0 and pairs >= args.max_pairs:
                        break

                del carry[: n_groups * 2]

                if args.flush_every > 0 and (pairs % args.flush_every) == 0:
                    f.flush()

        except KeyboardInterrupt:
            print("Stopped by user")

        f.flush()

    elapsed = time.time() - start
    print(
        "Capture complete: "
        f"pairs={pairs} packets={packets} bytes={bytes_rx} "
        f"ignored_src={dropped_src} trailing_bytes={len(carry)} "
        f"elapsed={elapsed:.2f}s"
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
