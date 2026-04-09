#!/usr/bin/env python3
"""Real-time ADC statistics analyzer for beamforming validation.

FPGA computes:
    - Peak+/Peak- from cosine (I) channel
    - Frequency from cosine (I) zero crossings
    - Phase from sine (Q) channel
Analyzer receives and displays those stats.

Stat Packet Format (8 bytes per stat):
    [0]: sync byte (0xA7)
    [1]: peak_pos[11:4]
    [2]: peak_pos[3:0] || peak_neg[11:8]
    [3]: peak_neg[7:0]
    [4]: phase[15:8]
    [5]: phase[7:0]
    [6]: period[15:8]   (samples between + zero crossings)
    [7]: period[7:0]

Usage:
    python3 python/adc_stats_analyzer.py --bind-port 40000 --tone-freq-mhz 5.01 --fpga-ip 192.168.1.128 --cal-vpp 1.04 --cal-peak-code 2267 --cal-trough-code 1840 --duration-sec 1

Optional CSV output for recording while analyzing:
  --csv-output adc_stats.csv --duration-sec 1
"""

import argparse
import csv
import curses
import numpy as np
import pathlib
import socket
import sys
import time
from collections import deque
from typing import Optional


class ADCStatsAnalyzer:
    """Real-time analyzer for FPGA-computed ADC statistics."""

    SYNC_BYTE = 0xA7
    FRAME_LEN = 8
    PAYLOAD_LEN = 7
    MAX_SYNC_LOOKAHEAD_FRAMES = 4

    def __init__(
        self,
        bind_ip: str,
        bind_port: int,
        tone_freq_mhz: float,
        phase_reference_deg: float = 0.0,
        fpga_ip: str = "192.168.1.128",
        prime_port: int = 20000,
        no_prime: bool = False,
        cal_vpp: Optional[float] = None,
        cal_peak_code: Optional[float] = None,
        cal_trough_code: Optional[float] = None,
        sample_rate_msps: float = 125.0,
        ui_refresh_sec: float = 1.5,
        debug_stats: bool = False,
        csv_output: Optional[pathlib.Path] = None,
        recv_size: int = 8192,
        timeout: float = 1.0,
    ):
        self.bind_ip = bind_ip
        self.bind_port = bind_port
        self.tone_freq_mhz = tone_freq_mhz
        self.phase_reference_deg = phase_reference_deg
        self.fpga_ip = fpga_ip
        self.prime_port = prime_port
        self.no_prime = no_prime
        self.recv_size = recv_size
        self.timeout = timeout

        # Voltage calibration
        self.cal_vpp = cal_vpp
        self.cal_peak_code = cal_peak_code
        self.cal_trough_code = cal_trough_code
        self.sample_rate_msps = float(sample_rate_msps)
        self.ui_refresh_sec = max(0.1, float(ui_refresh_sec))
        self.debug_stats = debug_stats
        self.volts_center_code = 2048.0
        self.volts_per_code = 1.0 / 2048.0  # Default VREF = 1.0 V
        self._configure_voltage_scaling()

        # CSV output
        self.csv_output = csv_output
        if csv_output:
            csv_output.parent.mkdir(parents=True, exist_ok=True)
            self.csv_file = open(csv_output, "w", newline="", encoding="utf-8")
            self.csv_writer = csv.writer(self.csv_file)
            self.csv_writer.writerow(
                ["host_time_iso", "stat_index", "peak_pos_code", "peak_neg_code", "phase_deg", "freq_mhz"]
            )
        else:
            self.csv_file = None
            self.csv_writer = None

        # UDP socket
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        self.sock.bind((bind_ip, bind_port))
        self.sock.settimeout(timeout)

        if not self.no_prime:
            self._prime_fpga_egress()

        # Rolling window of stats
        self.window_size = 100
        self.peak_pos_codes = deque(maxlen=self.window_size)
        self.peak_neg_codes = deque(maxlen=self.window_size)
        self.phases_deg = deque(maxlen=self.window_size)
        self.freqs_mhz = deque(maxlen=self.window_size)

        # Tracking
        self.last_update_time = time.time()
        self.total_stats_read = 0
        self.packets_received = 0
        self.bytes_received = 0
        self.stat_buffer = bytearray()
        self.frames_rejected = 0

        print(f"Analyzer config:")
        print(f"  Listen: {bind_ip}:{bind_port}")
        print(f"  Tone freq: {tone_freq_mhz} MHz")
        print(f"  ADC sample rate: {self.sample_rate_msps:.3f} MSPS")
        print("  Frequency: period-based (samples between zero crossings)")
        print("  Channel mapping: peak/freq=cos(I), phase=sin(Q)")
        print(f"  Phase reference: {phase_reference_deg}°")
        print(
            f"  Prime: {'disabled' if self.no_prime else f'enabled -> {self.fpga_ip}:{self.prime_port}'}"
        )
        if self.cal_vpp is not None:
            print(
                f"  Voltage calibration: "
                f"{self.cal_vpp:.6f} Vpp from codes {self.cal_peak_code:.3f}/{self.cal_trough_code:.3f}"
            )
            print(
                f"  Cal center code: {self.volts_center_code:.3f} | "
                f"scale: {self.volts_per_code:.9f} V/code"
            )
        if csv_output:
            print(f"  CSV output: {csv_output}")
        print(f"  UI refresh: {self.ui_refresh_sec:.1f} s")
        print(f"  Debug stats: {'on' if self.debug_stats else 'off'}")
        print(f"  Display: terminal UI (curses)")

    def _prime_fpga_egress(self) -> None:
        """Send one UDP datagram to FPGA ingress port so egress destination is latched."""
        try:
            # Subsystem latches source IP/port from UDP/20000 ingress to route UDP/30000 egress.
            self.sock.sendto(b"PRIME", (self.fpga_ip, self.prime_port))
            print(f"Primed FPGA egress destination via {self.fpga_ip}:{self.prime_port}")
        except Exception as exc:
            print(f"WARNING: prime packet send failed: {exc}")

    def _configure_voltage_scaling(self) -> None:
        """Configure volts-per-code conversion from measured calibration."""
        if self.cal_vpp is None:
            return

        if self.cal_peak_code is None or self.cal_trough_code is None:
            raise ValueError("Voltage calibration requires both cal_peak_code and cal_trough_code")

        code_span = float(self.cal_peak_code) - float(self.cal_trough_code)
        if abs(code_span) < 1e-12:
            raise ValueError("Voltage calibration code span must be non-zero")

        self.volts_center_code = (float(self.cal_peak_code) + float(self.cal_trough_code)) / 2.0
        self.volts_per_code = float(self.cal_vpp) / code_span

    def code_to_volts(self, code: int) -> float:
        """Convert ADC code to volts using calibration or default VREF."""
        return (code - self.volts_center_code) * self.volts_per_code

    def read_udp_chunk(self) -> int:
        """Read UDP packet, decode stats, return count of new stats."""
        count = 0
        try:
            payload, (src_ip, src_port) = self.sock.recvfrom(self.recv_size)
        except socket.timeout:
            return 0

        self.packets_received += 1
        self.bytes_received += len(payload)

        # Accumulate bytes into buffer
        self.stat_buffer.extend(payload)

        # Parse framed packets: [sync][7-byte payload].
        # Validate lock by requiring another sync at a frame boundary.
        # The next sync may be +8, +16, ... if frames are dropped upstream.
        while True:
            if len(self.stat_buffer) < self.FRAME_LEN:
                break

            sync_idx = self.stat_buffer.find(bytes([self.SYNC_BYTE]))
            if sync_idx < 0:
                # Keep enough tail for possible split sync/frame boundaries.
                self.stat_buffer = self.stat_buffer[-((2 * self.FRAME_LEN) - 1):]
                break

            if sync_idx > 0:
                self.stat_buffer = self.stat_buffer[sync_idx:]

            if len(self.stat_buffer) < self.FRAME_LEN:
                break

            # Validate alignment by checking for a sync at any frame boundary
            # within a short lookahead window.
            if len(self.stat_buffer) >= (2 * self.FRAME_LEN):
                max_lookahead = min(
                    self.MAX_SYNC_LOOKAHEAD_FRAMES,
                    (len(self.stat_buffer) // self.FRAME_LEN) - 1,
                )
                has_frame_boundary_sync = False
                for mult in range(1, max_lookahead + 1):
                    if self.stat_buffer[mult * self.FRAME_LEN] == self.SYNC_BYTE:
                        has_frame_boundary_sync = True
                        break

                if not has_frame_boundary_sync:
                    self.frames_rejected += 1
                    # Drop one byte and keep searching for a valid lock point.
                    self.stat_buffer = self.stat_buffer[1:]
                    continue

            stat_bytes = self.stat_buffer[1:self.FRAME_LEN]
            self.stat_buffer = self.stat_buffer[self.FRAME_LEN:]

            peak_pos_code = self._decode_peak_pos(stat_bytes) #* (2/4096)) - 1) * 5
            peak_neg_code = self._decode_peak_neg(stat_bytes) #* (2/4096)) - 1) * 5
            phase_raw = self._decode_phase(stat_bytes)
            freq_raw = self._decode_freq(stat_bytes)

            # Transport should carry offset-binary peaks with pos >= neg; auto-correct if inverted.
            if peak_pos_code < peak_neg_code:
                peak_pos_code, peak_neg_code = peak_neg_code, peak_pos_code

            # Optional debug output for raw packet decoding.
            if self.debug_stats and (self.total_stats_read < 10 or (self.total_stats_read % 100) == 0):
                print(
                    f"DEBUG stat {self.total_stats_read}: frame={self.SYNC_BYTE:02x} "
                    f"{' '.join(f'{b:02x}' for b in stat_bytes)} "
                    f"peak_pos={peak_pos_code} peak_neg={peak_neg_code} phase_raw={phase_raw} freq_raw={freq_raw} "
                    f"rejected={self.frames_rejected}"
                )

            # Convert to degrees and MHz
            phase_deg = (phase_raw / 65536.0) * 360.0 - self.phase_reference_deg
            # freq_raw is now period in samples between positive-going zero crossings
            if freq_raw > 0 and freq_raw < 0xFFFF:
                freq_mhz = self.sample_rate_msps / freq_raw
            else:
                freq_mhz = 0.0

            self.peak_pos_codes.append(peak_pos_code)
            self.peak_neg_codes.append(peak_neg_code)
            self.phases_deg.append(phase_deg)
            self.freqs_mhz.append(freq_mhz)

            # Optional CSV output
            if self.csv_writer:
                ts = time.time()
                self.csv_writer.writerow(
                    [
                        time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(ts)),
                        self.total_stats_read,
                        peak_pos_code,
                        peak_neg_code,
                        f"{phase_deg:.2f}",
                        f"{freq_mhz:.3f}",
                    ]
                )

            self.total_stats_read += 1
            count += 1

        return count

    # @staticmethod
    # def _decode_peak_pos(stat_bytes: bytearray) -> int:
    #     """Decode peak_pos from bytes [0:2]."""
    #     b0 = stat_bytes[0]
    #     b1 = stat_bytes[1]
    #     return ((b0 << 4) | ((b1 >> 4) & 0x0F))  # 12-bit code
    
    @staticmethod
    def _decode_peak_pos(stat_bytes: bytearray) -> int:
        """Decode peak_pos from bytes [0:1].
        byte[0] = peak_pos[11:4], byte[1] upper nibble = peak_pos[3:0].
        """
        b0 = stat_bytes[0]
        b1 = stat_bytes[1]
        return (b0 << 4) | ((b1 >> 4) & 0x0F)

    @staticmethod
    def _decode_peak_neg(stat_bytes: bytearray) -> int:
        """Decode peak_neg from bytes [1:3]."""
        b1 = stat_bytes[1]
        b2 = stat_bytes[2]
        return (((b1 & 0x0F) << 8) | b2)  # 12-bit code

    @staticmethod
    def _decode_phase(stat_bytes: bytearray) -> int:
        """Decode phase from bytes [3:5]."""
        return (stat_bytes[3] << 8) | stat_bytes[4]  # 16-bit

    @staticmethod
    def _decode_freq(stat_bytes: bytearray) -> int:
        """Decode frequency from bytes [5:7]."""
        return (stat_bytes[5] << 8) | stat_bytes[6]  # 16-bit

    def compute_metrics(self) -> dict:
        """Compute summary metrics from current window."""
        if len(self.peak_pos_codes) < 5:
            return {"error": "Insufficient stats"}

        peak_pos_arr = np.array(list(self.peak_pos_codes))
        peak_neg_arr = np.array(list(self.peak_neg_codes))
        phase_arr = np.array(list(self.phases_deg))
        freq_arr = np.array(list(self.freqs_mhz))

        # Summary metrics
        peak_pos_avg = np.mean(peak_pos_arr)
        peak_neg_avg = np.mean(peak_neg_arr)
        peak_pp_avg = peak_pos_avg - peak_neg_avg

        phase_avg = np.mean(phase_arr)
        phase_std = np.std(phase_arr)

        freq_avg = np.mean(freq_arr)
        freq_std = np.std(freq_arr)
        freq_error_khz = (freq_avg - self.tone_freq_mhz) * 1000.0

        # Convert codes to volts
        peak_pos_volts = self.code_to_volts(int(peak_pos_avg))
        peak_neg_volts = self.code_to_volts(int(peak_neg_avg))
        peak_pp_volts = peak_pos_volts - peak_neg_volts

        return {
            "peak_pos_code": peak_pos_avg,
            "peak_neg_code": peak_neg_avg,
            "peak_pp_code": peak_pp_avg,
            "peak_pos_volts": peak_pos_volts,
            "peak_neg_volts": peak_neg_volts,
            "peak_pp_volts": peak_pp_volts,
            "phase_deg": phase_avg,
            "phase_std_deg": phase_std,
            "freq_mhz": freq_avg,
            "freq_std_mhz": freq_std,
            "freq_error_khz": freq_error_khz,
        }

    def print_metrics(self, metrics: dict) -> None:
        """Print metrics to console."""
        if "error" in metrics:
            print(f"  [Warming up...] {metrics['error']}", end="\r")
            return

        print(
            f"\n{'='*70}"
            f"\nADC Stats Analyzer | Stats: {self.total_stats_read:,} | "
            f"Packets: {self.packets_received} | Bytes: {self.bytes_received:,}"
            f"\n{'='*70}"
        )
        print(
            f"FPGA-Computed Statistics:\n"
            f"  Peak (+) cos(I):  Code {metrics['peak_pos_code']:.1f} = {metrics['peak_pos_volts']:.6f} V\n"
            f"  Peak (-) cos(I):  Code {metrics['peak_neg_code']:.1f} = {metrics['peak_neg_volts']:.6f} V\n"
            f"  Peak-to-Peak I:   Code {metrics['peak_pp_code']:.1f} = {metrics['peak_pp_volts']:.6f} V\n"
        )
        print(
            f"Phase & Frequency:\n"
            f"  Phase (sin Q):    {metrics['phase_deg']:.2f}° (std: {metrics['phase_std_deg']:.2f}°)\n"
            f"  Frequency:        {metrics['freq_mhz']:.3f} MHz (error: {metrics['freq_error_khz']:.1f} kHz)\n"
            f"  Freq std:         {metrics['freq_std_mhz']:.3f} MHz"
        )

    def print_metrics_curses(self, stdscr, metrics: dict) -> None:
        """Update screen with curses (like 'top' command)."""
        stdscr.clear()

        try:
            row = 0

            if "error" in metrics:
                stdscr.addstr(row, 0, f"[Warming up...] {metrics['error']}")
                row += 1
            else:
                line = f"{'='*70}"
                stdscr.addstr(row, 0, line[:70] if len(line) > 70 else line)
                row += 1

                line = f"ADC Stats | Stats: {self.total_stats_read:,} | Packets: {self.packets_received} | Bytes: {self.bytes_received:,}"
                stdscr.addstr(row, 0, line[:70] if len(line) > 70 else line)
                row += 1

                line = f"{'='*70}"
                stdscr.addstr(row, 0, line[:70] if len(line) > 70 else line)
                row += 1

                stdscr.addstr(row, 0, "FPGA-Computed Statistics (Cosine I):")
                row += 1
                stdscr.addstr(
                    row,
                    0,
                    f"  Peak (+) I:     Code {metrics['peak_pos_code']:.1f} = {metrics['peak_pos_volts']:.6f} V",
                )
                row += 1
                stdscr.addstr(
                    row,
                    0,
                    f"  Peak (-) I:     Code {metrics['peak_neg_code']:.1f} = {metrics['peak_neg_volts']:.6f} V",
                )
                row += 1
                stdscr.addstr(
                    row,
                    0,
                    f"  Peak-to-Peak I: Code {metrics['peak_pp_code']:.1f} = {metrics['peak_pp_volts']:.6f} V",
                )
                row += 2

                stdscr.addstr(row, 0, "Phase & Frequency:")
                row += 1
                stdscr.addstr(row, 0, f"  Phase (sin Q):  {metrics['phase_deg']:.2f}° (std: {metrics['phase_std_deg']:.2f}°)")
                row += 1
                stdscr.addstr(row, 0, f"  Frequency:      {metrics['freq_mhz']:.3f} MHz (err: {metrics['freq_error_khz']:.1f} kHz)")
                row += 1
                stdscr.addstr(row, 0, f"  Freq std:       {metrics['freq_std_mhz']:.3f} MHz")
                row += 2

                stdscr.addstr(row, 0, "Press Ctrl+C to stop")

            stdscr.refresh()
        except curses.error:
            pass

    def run_text_mode(self, duration_sec: Optional[float] = None) -> None:
        """Run analyzer in text-only mode with curses-based terminal UI."""
        print("Starting analyzer (Ctrl+C to stop)...")
        time.sleep(0.5)

        try:
            stdscr = curses.initscr()
            curses.cbreak()
            stdscr.nodelay(True)
            curses.noecho()

            start = time.time()
            last_update = start

            while True:
                new_count = self.read_udp_chunk()
                if new_count > 0 and self.csv_file:
                    self.csv_file.flush()

                now = time.time()
                if (now - last_update) >= self.ui_refresh_sec:
                    metrics = self.compute_metrics()
                    self.print_metrics_curses(stdscr, metrics)
                    last_update = now

                if duration_sec and (now - start) >= duration_sec:
                    break

                time.sleep(0.001)

        except KeyboardInterrupt:
            pass
        finally:
            try:
                curses.nocbreak()
                curses.echo()
                curses.endwin()
            except:
                pass
            if self.csv_file:
                self.csv_file.close()
            print("\nStopped by user")

    def run(self, duration_sec: Optional[float] = None) -> None:
        """Main run loop."""
        self.run_text_mode(duration_sec)


def main() -> int:
    parser = argparse.ArgumentParser(description="Real-time ADC statistics analyzer")
    parser.add_argument(
        "--bind-ip",
        default="0.0.0.0",
        help="Local bind IP (0.0.0.0 = all interfaces)",
    )
    parser.add_argument(
        "--bind-port",
        type=int,
        default=40000,
        help="Local UDP port to listen on",
    )
    parser.add_argument(
        "--tone-freq-mhz",
        type=float,
        required=True,
        help="Expected tone frequency in MHz (e.g., 5.01)",
    )
    parser.add_argument(
        "--sample-rate-msps",
        type=float,
        default=125.0,
        help="ADC sample rate in MSPS used for frequency decode",
    )
    parser.add_argument(
        "--fpga-ip",
        default="192.168.1.128",
        help="FPGA IP used for auto-prime packet (default: 192.168.1.128)",
    )
    parser.add_argument(
        "--prime-port",
        type=int,
        default=20000,
        help="FPGA ingress UDP port used for auto-prime (default: 20000)",
    )
    parser.add_argument(
        "--no-prime",
        action="store_true",
        help="Disable auto-prime packet at startup",
    )
    parser.add_argument(
        "--phase-reference-deg",
        type=float,
        default=0.0,
        help="Phase reference point in degrees for IQ phase display",
    )
    parser.add_argument(
        "--cal-vpp",
        type=float,
        default=None,
        help="Measured waveform peak-to-peak voltage for calibration",
    )
    parser.add_argument(
        "--cal-peak-code",
        type=float,
        default=None,
        help="Measured ADC code at positive peak for voltage calibration",
    )
    parser.add_argument(
        "--cal-trough-code",
        type=float,
        default=None,
        help="Measured ADC code at negative peak for voltage calibration",
    )
    parser.add_argument(
        "--ui-refresh-sec",
        type=float,
        default=1.5,
        help="Curses metrics refresh interval in seconds",
    )
    parser.add_argument(
        "--debug-stats",
        action="store_true",
        help="Enable raw decoded stat debug prints",
    )
    parser.add_argument(
        "--csv-output",
        default="",
        help="Optional CSV file for recording while analyzing",
    )
    parser.add_argument(
        "--recv-size",
        type=int,
        default=8192,
        help="UDP socket receive buffer size",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=1.0,
        help="UDP receive timeout in seconds",
    )
    parser.add_argument(
        "--duration-sec",
        type=float,
        default=0,
        help="Run duration in seconds (<=0 runs until Ctrl+C)",
    )
    args = parser.parse_args()

    csv_output_path = None
    if args.csv_output.strip():
        csv_output_path = pathlib.Path(args.csv_output)

    analyzer = ADCStatsAnalyzer(
        bind_ip=args.bind_ip,
        bind_port=args.bind_port,
        tone_freq_mhz=args.tone_freq_mhz,
        phase_reference_deg=args.phase_reference_deg,
        fpga_ip=args.fpga_ip,
        prime_port=args.prime_port,
        no_prime=args.no_prime,
        cal_vpp=args.cal_vpp,
        cal_peak_code=args.cal_peak_code,
        cal_trough_code=args.cal_trough_code,
        sample_rate_msps=args.sample_rate_msps,
        ui_refresh_sec=args.ui_refresh_sec,
        debug_stats=args.debug_stats,
        csv_output=csv_output_path,
        recv_size=args.recv_size,
        timeout=args.timeout,
    )

    duration = args.duration_sec if args.duration_sec > 0 else None
    analyzer.run(duration)

    return 0


if __name__ == "__main__":
    sys.exit(main())
