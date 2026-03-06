#!/usr/bin/env python3
import argparse
import socket
import struct


def send_req(ip, port, payload, timeout=1.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(payload, (ip, port))
        resp, _ = sock.recvfrom(1024)
        if len(resp) < 9:
            raise RuntimeError(f"Short response: {len(resp)} bytes")
        status, raddr, rdata = struct.unpack(">BII", resp[:9])
        return status, raddr, rdata
    finally:
        sock.close()


def udp_write(ip, port, addr, data, timeout=1.0):
    pkt = struct.pack(">BII", 0x01, addr & 0xFFFFFFFF, data & 0xFFFFFFFF)
    status, raddr, rdata = send_req(ip, port, pkt, timeout=timeout)
    print(
        f"WR addr=0x{addr:08X} data=0x{data:08X} -> "
        f"status=0x{status:02X} resp_addr=0x{raddr:08X} resp_data=0x{rdata:08X}"
    )
    return status, raddr, rdata


def udp_read(ip, port, addr, timeout=1.0):
    pkt = struct.pack(">BI", 0x00, addr & 0xFFFFFFFF)
    status, raddr, rdata = send_req(ip, port, pkt, timeout=timeout)
    print(
        f"RD addr=0x{addr:08X} -> "
        f"status=0x{status:02X} resp_addr=0x{raddr:08X} resp_data=0x{rdata:08X}"
    )
    return status, raddr, rdata


def main():
    parser = argparse.ArgumentParser(description="UDP AXI-Lite bridge register tool")
    parser.add_argument("--ip", default="192.168.1.128")
    parser.add_argument("--port", type=int, default=10000)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--addr", type=lambda x: int(x, 0), default=0x0C)
    parser.add_argument("--write", type=lambda x: int(x, 0), default=None)
    parser.add_argument("--read", action="store_true")
    parser.add_argument("--demo", action="store_true", help="write/read REG3 and read counter")
    args = parser.parse_args()

    if args.demo:
        udp_write(args.ip, args.port, 0x0C, 0x0000005A, timeout=args.timeout)
        udp_read(args.ip, args.port, 0x0C, timeout=args.timeout)
        udp_read(args.ip, args.port, 0x08, timeout=args.timeout)
        return

    if args.write is not None:
        udp_write(args.ip, args.port, args.addr, args.write, timeout=args.timeout)

    if args.read or args.write is None:
        udp_read(args.ip, args.port, args.addr, timeout=args.timeout)


if __name__ == "__main__":
    main()
