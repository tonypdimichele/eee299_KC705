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
from typing import Iterable, List, Sequence


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
		row = ",".join(f"{b:02x}" for b in data[i : i + bytes_per_line]) + ","
		rows.append(row)
	path.write_text("\n".join(rows) + ("\n" if rows else ""), encoding="utf-8")


def run_loopback(
	fpga_ip: str,
	tx_port: int,
	expected_src_port: int,
	bind_ip: str,
	bind_port: int,
	timeout: float,
	chunks: Sequence[bytes],
	window: int,
	startup_retries: int,
) -> bytes:
	"""UDP loopback transfer with stop-and-wait or windowed mode."""
	rx_accum = bytearray()
	if not chunks:
		return b""

	sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	# Larger host-side buffers reduce packet drops under bursty traffic.
	sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
	sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 * 1024 * 1024)
	sock.settimeout(timeout)
	sock.bind((bind_ip, bind_port))
	max_payload = max(len(c) for c in chunks)
	recv_size = max(2048, max_payload + 64)

	try:
		total = len(chunks)

		# Compatibility mode: exact old behavior (send one, wait one).
		# This is the most robust mode if network/device timing is sensitive.
		if window == 1:
			for idx, payload in enumerate(chunks):
				sock.sendto(payload, (fpga_ip, tx_port))
				try:
					resp, addr = sock.recvfrom(recv_size)
				except TimeoutError as exc:
					raise TimeoutError(
						"Receive timeout waiting for loopback packet "
						f"(sent={idx + 1}, received={idx}, in_flight=1, "
						f"timeout={timeout}s)."
					) from exc

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

			return bytes(rx_accum)

		# Prime return path (e.g. ARP/cache warm-up) to avoid deadlock where
		# multiple initial sends are dropped and the sender blocks waiting forever.
		first_payload = chunks[0]
		primed = False
		for _ in range(startup_retries):
			sock.sendto(first_payload, (fpga_ip, tx_port))
			try:
				resp, addr = sock.recvfrom(recv_size)
			except TimeoutError:
				continue

			src_ip, src_port = addr
			if src_ip != fpga_ip or src_port != expected_src_port:
				continue
			if resp == first_payload:
				rx_accum.extend(resp)
				primed = True
				break

		if not primed:
			raise TimeoutError(
				"Failed to receive first loopback packet during startup priming "
				f"after {startup_retries} attempts. Check FPGA link/UDP path."
			)

		send_idx = 1
		recv_idx = 1
		pending: List[bytes] = []

		while recv_idx < total:
			while send_idx < total and len(pending) < window:
				payload = chunks[send_idx]
				sock.sendto(payload, (fpga_ip, tx_port))
				pending.append(payload)
				send_idx += 1

			try:
				resp, addr = sock.recvfrom(recv_size)
			except TimeoutError as exc:
				raise TimeoutError(
					"Receive timeout waiting for loopback packet "
					f"(sent={send_idx}, received={recv_idx}, in_flight={len(pending)}, "
					f"timeout={timeout}s). Try increasing --timeout or reducing --window."
				) from exc
			src_ip, src_port = addr

			if src_ip != fpga_ip:
				raise RuntimeError(
					f"Packet {recv_idx}: unexpected source IP {src_ip}, expected {fpga_ip}"
				)
			if src_port != expected_src_port:
				raise RuntimeError(
					f"Packet {recv_idx}: unexpected source port {src_port}, "
					f"expected {expected_src_port}"
				)

			if not pending:
				raise RuntimeError("Received a packet with no pending transmit queue")
			expected = pending.pop(0)

			if resp != expected:
				raise RuntimeError(
					f"Packet {recv_idx}: payload mismatch "
					f"(sent {len(expected)} bytes, got {len(resp)} bytes)"
				)

			rx_accum.extend(resp)
			recv_idx += 1

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
	parser.add_argument("--timeout", type=float, default=5.0, help="Socket timeout (s)")
	parser.add_argument("--chunk-size", type=int, default=900, help="Bytes per UDP packet")
	parser.add_argument(
		"--window",
		type=int,
		default=1,
		help="Max in-flight UDP packets before waiting for receives",
	)
	parser.add_argument(
		"--startup-retries",
		type=int,
		default=20,
		help="Retries for first loopback packet before windowed transfer",
	)
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
	if args.window <= 0:
		raise ValueError("--window must be > 0")
	if args.startup_retries <= 0:
		raise ValueError("--startup-retries must be > 0")

	in_path = pathlib.Path(args.input)
	out_path = pathlib.Path(args.output)

	tx_data = load_hex_file(in_path)
	chunks = list(chunk_data(tx_data, args.chunk_size))

	print(
		f"Sending {len(tx_data)} bytes in {len(chunks)} packets "
		f"to {args.ip}:{args.tx_port} (bind {args.bind_ip}:{args.bind_port}, "
		f"window={args.window})"
	)

	rx_data = run_loopback(
		fpga_ip=args.ip,
		tx_port=args.tx_port,
		expected_src_port=args.expect_src_port,
		bind_ip=args.bind_ip,
		bind_port=args.bind_port,
		timeout=args.timeout,
		chunks=chunks,
		window=args.window,
		startup_retries=args.startup_retries,
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

