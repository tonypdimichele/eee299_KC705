#!/usr/bin/env python3
import argparse
import socket
import struct


REG_COUNTER = 0x08
REG_LED = 0x0C
REG_DAC_CTRL = 0x10
REG_DAC_SPI_READ = 0x18
REG_STREAM_CTRL = 0x00


def decode_dac_spi_read_reg(value):
    return {
        "addr": value & 0xFF,
        "data": (value >> 8) & 0xFF,
        "req_toggle": (value >> 16) & 0x1,
        "busy": (value >> 17) & 0x1,
        "done_toggle": (value >> 18) & 0x1,
    }


def trigger_dac_spi_read(ip, port, reg_addr, timeout=1.0, polls=50):
    _, _, current = udp_read(ip, port, REG_DAC_SPI_READ, timeout=timeout)
    current_fields = decode_dac_spi_read_reg(current)
    next_toggle = current_fields["req_toggle"] ^ 0x1
    cmd = (next_toggle << 16) | (reg_addr & 0xFF)
    udp_write(ip, port, REG_DAC_SPI_READ, cmd, timeout=timeout)

    for _ in range(polls):
        status, raddr, rdata = udp_read(ip, port, REG_DAC_SPI_READ, timeout=timeout)
        fields = decode_dac_spi_read_reg(rdata)
        if fields["done_toggle"] == next_toggle and not fields["busy"]:
            print(
                f"DAC SPI RD reg=0x{reg_addr:02X} -> data=0x{fields['data']:02X} "
                f"(status=0x{status:02X} resp_addr=0x{raddr:08X})"
            )
            return status, raddr, rdata

    raise RuntimeError("Timed out waiting for DAC SPI read completion")


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
    parser.add_argument("--addr", type=lambda x: int(x, 0), default=REG_LED)
    parser.add_argument("--write", type=lambda x: int(x, 0), default=None)
    parser.add_argument("--read", action="store_true")
    parser.add_argument("--demo", action="store_true", help="write/read REG3 and read counter")
    parser.add_argument("--stream-off", action="store_true", help="Disable FPGA ADC UDP stream (REG0[0]=0)")
    parser.add_argument("--stream-on", action="store_true", help="Enable FPGA ADC UDP stream (REG0[0]=1)")
    parser.add_argument("--dac-read-addr", type=lambda x: int(x, 0), default=None,
                        help="Issue a single-byte DAC1 SPI register read via AXI register 0x18")
    args = parser.parse_args()

    if args.demo:
        udp_write(args.ip, args.port, REG_LED, 0x0000005A, timeout=args.timeout)
        udp_read(args.ip, args.port, REG_LED, timeout=args.timeout)
        udp_read(args.ip, args.port, REG_COUNTER, timeout=args.timeout)
        return

    if args.dac_read_addr is not None:
        trigger_dac_spi_read(args.ip, args.port, args.dac_read_addr, timeout=args.timeout)
        return

    if args.stream_off:
        udp_write(args.ip, args.port, REG_STREAM_CTRL, 0x00000000, timeout=args.timeout)
        udp_read(args.ip, args.port, REG_STREAM_CTRL, timeout=args.timeout)
        return

    if args.stream_on:
        udp_write(args.ip, args.port, REG_STREAM_CTRL, 0x00000001, timeout=args.timeout)
        udp_read(args.ip, args.port, REG_STREAM_CTRL, timeout=args.timeout)
        return

    if args.write is not None:
        udp_write(args.ip, args.port, args.addr, args.write, timeout=args.timeout)

    if args.read or args.write is None:
        udp_read(args.ip, args.port, args.addr, timeout=args.timeout)


if __name__ == "__main__":
    main()
