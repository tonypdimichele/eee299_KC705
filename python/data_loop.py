#!/usr/bin/env python3
"""UDP loopback tester for KC705 streaming path.

Reads comma-separated hex bytes from an input text file, sends them to KC705 UDP
port 20000 in fixed-size chunks, receives looped-back packets (from source port
30000), writes received bytes to an output text file, and verifies round-trip
data integrity.
"""

import argparse
import pathlib
import re
import socket
import sys
from typing import Iterable, List


HEX_BYTE_RE = re.compile(r"\b[0-9a-fA-F]{2}\b")


def load_hex_file(path: pathlib.Path) -> bytes:
	"""Parse a file containing comma/whitespace-separated hex bytes."""
	text = path.read_text(encoding="utf-8")
	vals = HEX_BYTE_RE.findall(text)
	if not vals:
		raise ValueError(f"No hex byte tokens found in {path}")
	return bytes(int(v, 16) for v in vals)


def chunk_data(data: bytes, chunk_size: int) -> Iterable[bytes]:
	for i in range(0, len(data), chunk_size):
		yield data[i : i + chunk_size]


def write_hex_file(path: pathlib.Path, data: bytes, bytes_per_line: int = 10) -> None:
	rows: List[str] = []
	for i in range(0, len(data), bytes_per_line):
		row = ",".join(f"{b:02x}" for b in data[i : i + bytes_per_line])
		rows.append(row)
	path.write_text("\n".join(rows) + ("\n" if rows else ""), encoding="utf-8")


def run_loopback(
	fpga_ip: str,
	tx_port: int,
	expected_src_port: int,
	bind_ip: str,
	bind_port: int,
	timeout: float,
	chunks: Iterable[bytes],
) -> bytes:
	"""Stop-and-wait transfer: send one packet, wait for its echoed packet."""
	rx_accum = bytearray()
	sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	sock.settimeout(timeout)
	sock.bind((bind_ip, bind_port))

	try:
		for idx, payload in enumerate(chunks):
			sock.sendto(payload, (fpga_ip, tx_port))

			resp, addr = sock.recvfrom(max(2048, len(payload) + 64))
			src_ip, src_port = addr

			if src_ip != fpga_ip:
				raise RuntimeError(
					f"Packet {idx}: unexpected source IP {src_ip}, expected {fpga_ip}"
				)
			if src_port != expected_src_port:
				raise RuntimeError(
					f"Packet {idx}: unexpected source port {src_port}, "
					f"expected {expected_src_port}"
				)

			if resp != payload:
				raise RuntimeError(
					f"Packet {idx}: payload mismatch "
					f"(sent {len(payload)} bytes, got {len(resp)} bytes)"
				)

			rx_accum.extend(resp)

	finally:
		sock.close()

	return bytes(rx_accum)


def first_mismatch(a: bytes, b: bytes):
	n = min(len(a), len(b))
	for i in range(n):
		if a[i] != b[i]:
			return i, a[i], b[i]
	if len(a) != len(b):
		return n, None if n >= len(a) else a[n], None if n >= len(b) else b[n]
	return None


def main() -> int:
	parser = argparse.ArgumentParser(description="KC705 UDP streaming loopback test")
	parser.add_argument("--ip", default="192.168.1.128", help="KC705 IP")
	parser.add_argument("--tx-port", type=int, default=20000, help="KC705 ingress UDP port")
	parser.add_argument(
		"--expect-src-port",
		type=int,
		default=30000,
		help="Expected UDP source port on looped-back packets",
	)
	parser.add_argument("--bind-ip", default="0.0.0.0", help="Local bind IP")
	parser.add_argument("--bind-port", type=int, default=40000, help="Local UDP bind port")
	parser.add_argument("--timeout", type=float, default=1.0, help="Socket timeout (s)")
	parser.add_argument("--chunk-size", type=int, default=4, help="Bytes per UDP packet")
	parser.add_argument(
		"--input",
		default="send_data.txt",
		help="Input comma-separated hex-byte file",
	)
	parser.add_argument(
		"--output",
		default="recv_data.txt",
		help="Output comma-separated hex-byte file",
	)
	args = parser.parse_args()

	if args.chunk_size <= 0:
		raise ValueError("--chunk-size must be > 0")

	in_path = pathlib.Path(args.input)
	out_path = pathlib.Path(args.output)

	tx_data = load_hex_file(in_path)
	chunks = list(chunk_data(tx_data, args.chunk_size))

	print(
		f"Sending {len(tx_data)} bytes in {len(chunks)} packets "
		f"to {args.ip}:{args.tx_port} (bind {args.bind_ip}:{args.bind_port})"
	)

	rx_data = run_loopback(
		fpga_ip=args.ip,
		tx_port=args.tx_port,
		expected_src_port=args.expect_src_port,
		bind_ip=args.bind_ip,
		bind_port=args.bind_port,
		timeout=args.timeout,
		chunks=chunks,
	)

	write_hex_file(out_path, rx_data, bytes_per_line=10)
	print(f"Wrote received data to {out_path}")

	if rx_data == tx_data:
		print(f"PASS: {len(tx_data)} bytes matched exactly")
		return 0

	mm = first_mismatch(tx_data, rx_data)
	if mm is None:
		print("FAIL: data mismatch with unknown reason")
	else:
		idx, txv, rxv = mm
		print(
			"FAIL: data mismatch at index "
			f"{idx} (tx={txv if txv is None else hex(txv)}, "
			f"rx={rxv if rxv is None else hex(rxv)})"
		)
		print(f"Lengths: tx={len(tx_data)} rx={len(rx_data)}")

	return 1


if __name__ == "__main__":
	sys.exit(main())
from regs import send_req, udp_read, udp_write


def main():

