#!/usr/bin/env python3
"""Always-on UDP IO utility for KC705 streaming.

This tool binds one UDP socket and keeps listening continuously while allowing
runtime send commands from stdin. Using one socket ensures replies sent by the
FPGA to the ingress source port come back to this same process.
"""

import argparse
import datetime
import pathlib
import queue
import re
import shlex
import socket
import sys
import threading
import time
from typing import Iterable, Optional


HEX_BYTE_RE = re.compile(r"\b[0-9a-fA-F]{2}\b")


def iter_chunks(data: bytes, chunk_size: int) -> Iterable[bytes]:
    for i in range(0, len(data), chunk_size):
        yield data[i : i + chunk_size]


def load_input(path: pathlib.Path, force_raw: bool) -> bytes:
    raw = path.read_bytes()
    if force_raw:
        return raw

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw

    vals = HEX_BYTE_RE.findall(text)
    if vals:
        return bytes(int(v, 16) for v in vals)

    return raw


def format_hex_rows(data: bytes, values_per_line: int = 10) -> str:
    lines = []
    for i in range(0, len(data), values_per_line):
        chunk = data[i : i + values_per_line]
        lines.append(",".join(f"{b:02x}" for b in chunk) + ",")
    return "\n".join(lines) + "\n"


def send_payload(
    sock: socket.socket,
    payload: bytes,
    fpga_ip: str,
    tx_port: int,
    chunk_size: int,
    tx_gap_us: int,
) -> tuple[int, int]:
    packets = 0
    sent_bytes = 0
    for chunk in iter_chunks(payload, chunk_size):
        sock.sendto(chunk, (fpga_ip, tx_port))
        packets += 1
        sent_bytes += len(chunk)
        if tx_gap_us > 0:
            time.sleep(tx_gap_us / 1_000_000.0)
    return packets, sent_bytes


def tx_worker(
    sock: socket.socket,
    fpga_ip: str,
    tx_port: int,
    chunk_size: int,
    tx_q: "queue.Queue[tuple[str, bytes]]",
    tx_done_q: "queue.Queue[tuple[str, int, int, str]]",
    stop_event: threading.Event,
    tx_gap_us: int,
) -> None:
    while not stop_event.is_set():
        try:
            label, data = tx_q.get(timeout=0.1)
        except queue.Empty:
            continue

        try:
            pkts, nbytes = send_payload(sock, data, fpga_ip, tx_port, chunk_size, tx_gap_us)
            tx_done_q.put((label, pkts, nbytes, ""))
        except OSError as exc:
            tx_done_q.put((label, 0, 0, str(exc)))


def stdin_reader(cmd_q: "queue.Queue[str]", stop_event: threading.Event) -> None:
    while not stop_event.is_set():
        try:
            line = input("io> ")
        except EOFError:
            cmd_q.put("quit")
            return
        except KeyboardInterrupt:
            cmd_q.put("quit")
            return
        cmd_q.put(line.strip())


def help_lines() -> list[str]:
    return [
        "Commands:",
        "  help",
        "  stats",
        "  send <file_path> [--raw]",
        "  sendhex <aa,bb,cc or aa bb cc>",
        "  quit",
    ]


def parse_sendhex(arg: str) -> bytes:
    vals = HEX_BYTE_RE.findall(arg)
    if not vals:
        raise ValueError("No hex-byte tokens found (expected like 'aa bb cc')")
    return bytes(int(v, 16) for v in vals)


def run_io(
    bind_ip: str,
    bind_port: int,
    fpga_ip: str,
    tx_port: int,
    chunk_size: int,
    recv_size: int,
    output: Optional[pathlib.Path],
    startup_send: list[str],
    startup_raw: bool,
    heartbeat_sec: float,
    output_flush_sec: float,
    keepalive_sec: float,
    keepalive_payload: bytes,
    debug_log: pathlib.Path,
    tx_gap_us: int,
    rx_idle_log_sec: float,
) -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 * 1024 * 1024)
    sock.bind((bind_ip, bind_port))
    sock.settimeout(0.1)

    cmd_q: "queue.Queue[str]" = queue.Queue()
    tx_q: "queue.Queue[tuple[str, bytes]]" = queue.Queue()
    tx_done_q: "queue.Queue[tuple[str, int, int, str]]" = queue.Queue()
    stop_event = threading.Event()
    t = threading.Thread(target=stdin_reader, args=(cmd_q, stop_event), daemon=True)
    t.start()
    tx_t = threading.Thread(
        target=tx_worker,
        args=(sock, fpga_ip, tx_port, chunk_size, tx_q, tx_done_q, stop_event, tx_gap_us),
        daemon=True,
    )
    tx_t.start()

    recv_packets = 0
    recv_bytes = 0
    sent_packets = 0
    sent_bytes = 0

    out_file = None
    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        out_file = output.open("a", encoding="utf-8")

    debug_log.parent.mkdir(parents=True, exist_ok=True)
    debug_f = debug_log.open("a", encoding="utf-8", buffering=1)

    def log_event(msg: str) -> None:
        ts = datetime.datetime.now().isoformat(timespec="milliseconds")
        debug_f.write(f"{ts} {msg}\n")

    def emit(msg: str, to_console: bool = True) -> None:
        log_event(msg)
        if to_console:
            print(msg)

    try:
        emit(f"Listening on {bind_ip}:{bind_port}")
        emit(f"Default TX target: {fpga_ip}:{tx_port}")
        if output is not None:
            emit(f"Appending RX payloads to {output}")
        emit(f"Debug log file: {debug_log}")
        for line in help_lines():
            emit(line)

        for path in startup_send:
            cmd_q.put(f"send {shlex.quote(path)} {'--raw' if startup_raw else ''}".strip())

        last_stat = time.time()
        last_output_flush = time.time()
        last_keepalive = time.time()
        last_rx = time.time()
        last_rx_idle_log = 0.0
        while True:
            try:
                payload, _ = sock.recvfrom(recv_size)
                recv_packets += 1
                recv_bytes += len(payload)
                last_rx = time.time()
                if out_file is not None:
                    out_file.write(format_hex_rows(payload, values_per_line=10))
            except socket.timeout:
                pass

            while True:
                try:
                    label, pkts, nbytes, err = tx_done_q.get_nowait()
                except queue.Empty:
                    break
                if err:
                    emit(f"TX error for {label}: {err}")
                    continue
                sent_packets += pkts
                sent_bytes += nbytes
                emit(
                    f"TX sent {label} packets={pkts} bytes={nbytes}",
                    to_console=(label != "keepalive"),
                )

            while True:
                try:
                    cmd = cmd_q.get_nowait()
                except queue.Empty:
                    break

                if not cmd:
                    continue

                try:
                    parts = shlex.split(cmd)
                except ValueError as exc:
                    emit(f"Command parse error: {exc}")
                    continue

                if not parts:
                    continue

                op = parts[0].lower()
                if op in ("quit", "exit"):
                    emit("Stopping")
                    return 0
                if op == "help":
                    for line in help_lines():
                        emit(line)
                    continue
                if op == "stats":
                    emit(
                        f"STATS RX packets={recv_packets} bytes={recv_bytes} | "
                        f"TX packets={sent_packets} bytes={sent_bytes}"
                    )
                    continue
                if op == "send":
                    if len(parts) < 2:
                        emit("Usage: send <file_path> [--raw]")
                        continue
                    path = pathlib.Path(parts[1])
                    use_raw = "--raw" in parts[2:]
                    data = load_input(path, force_raw=use_raw)
                    tx_q.put((f"file={path}", data))
                    emit(f"TX queued file={path} bytes={len(data)}")
                    continue
                if op == "sendhex":
                    if len(parts) < 2:
                        emit("Usage: sendhex <aa bb cc>")
                        continue
                    hex_arg = cmd[len(parts[0]) :].strip()
                    data = parse_sendhex(hex_arg)
                    tx_q.put(("hex", data))
                    emit(f"TX queued hex bytes={len(data)}")
                    continue

                emit(f"Unknown command: {op}")

            now = time.time()
            if out_file is not None and output_flush_sec > 0 and now - last_output_flush >= output_flush_sec:
                out_file.flush()
                last_output_flush = now

            if keepalive_sec > 0 and now - last_keepalive >= keepalive_sec:
                if tx_q.empty():
                    tx_q.put(("keepalive", keepalive_payload))
                    emit(f"TX queued keepalive bytes={len(keepalive_payload)}", to_console=False)
                last_keepalive = now

            if rx_idle_log_sec > 0 and now - last_rx >= rx_idle_log_sec and now - last_rx_idle_log >= rx_idle_log_sec:
                emit(
                    f"RX idle for {now - last_rx:.2f}s (RX packets={recv_packets} bytes={recv_bytes})",
                    to_console=False,
                )
                last_rx_idle_log = now

            if heartbeat_sec > 0 and now - last_stat >= heartbeat_sec:
                emit(
                    f"Heartbeat RX packets={recv_packets} bytes={recv_bytes} | "
                    f"TX packets={sent_packets} bytes={sent_bytes}"
                )
                last_stat = now
    except KeyboardInterrupt:
        emit("Stopped by user")
        return 0
    finally:
        stop_event.set()
        if out_file is not None:
            out_file.close()
        debug_f.close()
        sock.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Always-on UDP IO utility")
    parser.add_argument("--bind-ip", default="0.0.0.0", help="Local bind IP")
    parser.add_argument("--bind-port", type=int, default=40000, help="Local bind port")
    parser.add_argument("--ip", default="192.168.1.128", help="FPGA destination IP")
    parser.add_argument("--tx-port", type=int, default=20000, help="FPGA destination UDP port")
    parser.add_argument("--chunk-size", type=int, default=900, help="Bytes per UDP packet")
    parser.add_argument("--recv-size", type=int, default=2048, help="recvfrom buffer size")
    parser.add_argument(
        "--output",
        default="received.txt",
        help="Append RX payloads as comma-separated hex (set empty string to disable)",
    )
    parser.add_argument(
        "--send-on-start",
        action="append",
        default=[],
        help="Optional file path to send immediately after startup (repeatable)",
    )
    parser.add_argument(
        "--send-on-start-raw",
        action="store_true",
        help="Use raw mode for --send-on-start file(s)",
    )
    parser.add_argument(
        "--heartbeat-sec",
        type=float,
        default=0.0,
        help="Print periodic heartbeat stats every N seconds (0 disables)",
    )
    parser.add_argument(
        "--output-flush-sec",
        type=float,
        default=1.0,
        help="Flush received output file every N seconds (0 disables periodic flush)",
    )
    parser.add_argument(
        "--keepalive-sec",
        type=float,
        default=0.0,
        help="Queue a tiny UDP keepalive every N seconds (0 disables)",
    )
    parser.add_argument(
        "--keepalive-hex",
        default="00",
        help="Hex byte(s) for keepalive payload, e.g. '00' or 'aa bb cc'",
    )
    parser.add_argument(
        "--debug-log",
        default="sender_debug.log",
        help="Append runtime debug/status events to this file",
    )
    parser.add_argument(
        "--tx-gap-us",
        type=int,
        default=100,
        help="Microseconds to wait between UDP packets to avoid overrunning FPGA RX",
    )
    parser.add_argument(
        "--rx-idle-log-sec",
        type=float,
        default=1.0,
        help="Log when no RX data has arrived for this many seconds (0 disables)",
    )
    args = parser.parse_args()

    if args.bind_port <= 0 or args.bind_port > 65535:
        raise ValueError("--bind-port must be in 1..65535")
    if args.tx_port <= 0 or args.tx_port > 65535:
        raise ValueError("--tx-port must be in 1..65535")
    if args.chunk_size <= 0:
        raise ValueError("--chunk-size must be > 0")
    if args.recv_size <= 0:
        raise ValueError("--recv-size must be > 0")
    if args.heartbeat_sec < 0:
        raise ValueError("--heartbeat-sec must be >= 0")
    if args.output_flush_sec < 0:
        raise ValueError("--output-flush-sec must be >= 0")
    if args.keepalive_sec < 0:
        raise ValueError("--keepalive-sec must be >= 0")
    if args.tx_gap_us < 0:
        raise ValueError("--tx-gap-us must be >= 0")
    if args.rx_idle_log_sec < 0:
        raise ValueError("--rx-idle-log-sec must be >= 0")

    keepalive_data = parse_sendhex(args.keepalive_hex)
    debug_log_path = pathlib.Path(args.debug_log)

    output_path = pathlib.Path(args.output) if args.output else None

    return run_io(
        bind_ip=args.bind_ip,
        bind_port=args.bind_port,
        fpga_ip=args.ip,
        tx_port=args.tx_port,
        chunk_size=args.chunk_size,
        recv_size=args.recv_size,
        output=output_path,
        startup_send=args.send_on_start,
        startup_raw=args.send_on_start_raw,
        heartbeat_sec=args.heartbeat_sec,
        output_flush_sec=args.output_flush_sec,
        keepalive_sec=args.keepalive_sec,
        keepalive_payload=keepalive_data,
        debug_log=debug_log_path,
        tx_gap_us=args.tx_gap_us,
        rx_idle_log_sec=args.rx_idle_log_sec,
    )


if __name__ == "__main__":
    sys.exit(main())
