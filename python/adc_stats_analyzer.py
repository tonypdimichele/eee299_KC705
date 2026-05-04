#!/usr/bin/env python3
"""Real-time ADC statistics analyzer for beamforming validation.

FPGA computes:
    - Peak+/Peak- from cosine (I) channel
    - Frequency from cosine (I) zero crossings
    - Phase from sine (Q) channel
Analyzer receives and displays those stats.

Stat Packet Format (16 bytes per stat):
    [0]: sync byte (0xA7)
    [1]: peak_pos[11:4]
    [2]: peak_pos[3:0] || peak_neg[11:8]
    [3]: peak_neg[7:0]
    [4:7]: iq_delay_sum (unsigned 32-bit, clocks from I ZC to Q ZC, summed over N)
    [8]: freq_raw_clk_count[15:8]  (clk count over adaptive N crossings)
    [9]: freq_raw_clk_count[7:0]
    [10]: n_cycles[15:8]
    [11]: n_cycles[7:0]
    [12:15]: cordic_phase (signed 32-bit, single atan2 from correlation accumulation)

Usage:
    python3 python/adc_stats_analyzer.py --bind-port 40000 --fpga-ip 192.168.1.128 --duration-sec 1

Optional CSV output for recording while analyzing:
  --csv-output adc_stats.csv --duration-sec 1
"""

import argparse
import csv
import curses
import math
import pathlib
import socket
import statistics
import sys
import time
from collections import deque
from typing import Optional


class ADCStatsAnalyzer:
    """Real-time analyzer for FPGA-computed ADC statistics."""

    SYNC_BYTE = 0xA7
    FRAME_LEN = 16
    PAYLOAD_LEN = 15
    MAX_SYNC_LOOKAHEAD_FRAMES = 4
    MIN_N_CYCLES = 4
    MAX_N_CYCLES = 30000

    def __init__(
        self,
        bind_ip: str,
        bind_port: int,
        phase_reference_deg: float = 0.0,
        fpga_ip: str = "192.168.1.128",
        prime_port: int = 20000,
        no_prime: bool = False,
        sample_rate_msps: float = 125.0,
        ui_refresh_sec: float = 1.5,
        debug_stats: bool = False,
        csv_output: Optional[pathlib.Path] = None,
        rms_csv_output: Optional[pathlib.Path] = None,
        sliding_window_size: int = 50,
        recv_size: int = 8192,
        timeout: float = 1.0,
        resolve_pi_ambiguity: bool = True,
        phase_ema_alpha: float = 0.25,
        phase_max_step_deg: float = 35.0,
        resolve_with_zc_phase: bool = True,
        phase_relock_rejects: int = 20,
    ):
        self.bind_ip = bind_ip
        self.bind_port = bind_port
        self.phase_reference_deg = phase_reference_deg
        self.fpga_ip = fpga_ip
        self.prime_port = prime_port
        self.no_prime = no_prime
        self.recv_size = recv_size
        self.timeout = timeout
        self.volts_center_code = 2048.0
        self.volts_per_code = 1.0 / 2048.0  # Default offset-binary scale

        self.sample_rate_msps = float(sample_rate_msps)
        self.ui_refresh_sec = max(0.1, float(ui_refresh_sec))
        self.debug_stats = debug_stats
        self.max_valid_freq_mhz = 0.5 * self.sample_rate_msps
        self.min_valid_period_clks = 2.0
        self.resolve_pi_ambiguity = bool(resolve_pi_ambiguity)
        self.phase_ema_alpha = max(0.0, min(1.0, float(phase_ema_alpha)))
        self.phase_max_step_deg = max(1.0, float(phase_max_step_deg))
        self.resolve_with_zc_phase = bool(resolve_with_zc_phase)
        self.phase_relock_rejects = max(1, int(phase_relock_rejects))

        # CSV output
        self.csv_output = csv_output
        if csv_output:
            csv_output.parent.mkdir(parents=True, exist_ok=True)
            self.csv_file = open(csv_output, "w", newline="", encoding="utf-8")
            self.csv_writer = csv.writer(self.csv_file)
            self.csv_writer.writerow(
                [
                    "host_time_iso",
                    "report_index",
                    "stats_processed",
                    "peak_pos_code",
                    "peak_neg_code",
                    "peak_pos_volts",
                    "peak_neg_volts",
                    "v2rms_v2",
                    "phase_zc_deg",
                    "phase_cordic_raw_deg",
                    "phase_cordic_stable_deg",
                    "n_cycles",
                    "freq_hz",
                    "freq_mhz",
                ]
            )
        else:
            self.csv_file = None
            self.csv_writer = None

        # RMS comparison CSV output (block vs sliding)
        self.rms_csv_output = rms_csv_output
        self.sliding_window_size = sliding_window_size
        if rms_csv_output:
            rms_csv_output.parent.mkdir(parents=True, exist_ok=True)
            self.rms_csv_file = open(rms_csv_output, "w", newline="", encoding="utf-8")
            self.rms_csv_writer = csv.writer(self.rms_csv_file)
            self.rms_csv_writer.writerow(
                [
                    "host_time_iso",
                    "stats_processed",
                    "report_index",
                    "block_updated",
                    "frequency_mhz",
                    "measured_vpp",
                    "stat_rms2_measured",
                    "block_rms2_measured",
                    "block_variance",
                    "sliding_rms2_measured",
                    "sliding_variance",
                ]
            )
        else:
            self.rms_csv_file = None
            self.rms_csv_writer = None

        # UDP socket
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        self.sock.bind((bind_ip, bind_port))
        self.sock.settimeout(timeout)

        if not self.no_prime:
            self._prime_fpga_egress()

        # Batch averaging: update reported metrics only once per full batch.
        self.batch_size = 20
        self.batch_peak_pos_codes = []
        self.batch_peak_neg_codes = []
        self.batch_phases_deg = []
        self.batch_cordic_phases_deg_raw = []
        self.batch_cordic_phases_deg = []
        self.batch_n_cycles = []
        self.batch_freqs_mhz = []
        self.latest_metrics = None
        self.reports_generated = 0

        # CORDIC phase stabilization state for real hardware streams.
        self._last_cordic_phase_stable_deg = None
        self._cordic_phase_ema_deg = None
        self._cordic_reject_streak = 0
        self.cordic_phase_rejects = 0

        # Sliding RMS state: running sum with circular buffer
        self.sliding_buf = deque(maxlen=self.sliding_window_size)
        self.sliding_running_sum = 0.0
        self.batch_v2rms_samples = []        # per-stat V²rms (for block average)
        self.batch_sliding_outputs = []      # per-stat sliding V²rms snapshots
        self.block_history = []              # history of completed block means (for variance)
        self.latest_block_v2rms = 0.0
        self.latest_block_var = 0.0

        # Tracking
        self.last_update_time = time.time()
        self.total_stats_read = 0
        self.packets_received = 0
        self.bytes_received = 0
        self.stat_buffer = bytearray()
        self.frames_rejected = 0
        self.invalid_freq_stats = 0
        self.stream_mismatch_warned = False

        print(f"Analyzer config:")
        print(f"  Listen: {bind_ip}:{bind_port}")
        print(f"  ADC sample rate: {self.sample_rate_msps:.3f} MSPS")
        print("  Frequency: raw clk count with transmitted N (from FPGA packet)")
        print(
            f"  Voltage scale: center={self.volts_center_code:.1f} code, "
            f"{self.volts_per_code:.9f} V/code"
        )
        print(f"  Report cadence: one averaged update per {self.batch_size} stats")
        print("  Channel mapping: peak/freq=cos(I), phase=sin(Q)")
        print(f"  Phase reference: {phase_reference_deg}°")
        print(
            f"  Prime: {'disabled' if self.no_prime else f'enabled -> {self.fpga_ip}:{self.prime_port}'}"
        )
        if csv_output:
            print(f"  CSV output: {csv_output}")
        print(f"  UI refresh: {self.ui_refresh_sec:.1f} s")
        print(f"  Debug stats: {'on' if self.debug_stats else 'off'}")
        print(f"  Pi ambiguity resolve: {'on' if self.resolve_pi_ambiguity else 'off'}")
        print(f"  CORDIC phase EMA alpha: {self.phase_ema_alpha:.2f}")
        print(f"  CORDIC max step: {self.phase_max_step_deg:.1f} deg/stat")
        print(f"  CORDIC branch ref: {'ZC phase' if self.resolve_with_zc_phase else 'last stable'}")
        print(f"  CORDIC relock after rejects: {self.phase_relock_rejects}")
        print(f"  Expected N range: [{self.MIN_N_CYCLES}, {self.MAX_N_CYCLES}]")
        print(f"  Max accepted frequency: {self.max_valid_freq_mhz:.3f} MHz")
        print(f"  Display: terminal UI (curses)")
        if rms_csv_output:
            print(f"  RMS comparison CSV: {rms_csv_output}")
            print(f"  Sliding window size: {sliding_window_size} stats")
            print("  RMS CSV cadence: per decoded stat (block_updated marks block refresh)")

    def _prime_fpga_egress(self) -> None:
        """Send one UDP datagram to FPGA ingress port so egress destination is latched."""
        try:
            # Subsystem latches source IP/port from UDP/20000 ingress to route UDP/30000 egress.
            self.sock.sendto(b"PRIME", (self.fpga_ip, self.prime_port))
            print(f"Primed FPGA egress destination via {self.fpga_ip}:{self.prime_port}")
        except Exception as exc:
            print(f"WARNING: prime packet send failed: {exc}")

    def code_to_volts(self, code: float) -> float:
        """Convert offset-binary ADC code to volts using default scaling."""
        return (code - self.volts_center_code) * self.volts_per_code * 5 #keep as ADC divides 1/5

    @staticmethod
    def _wrap_phase_deg(phase_deg: float) -> float:
        return (phase_deg + 180.0) % 360.0 - 180.0

    @staticmethod
    def _circular_distance_deg(a_deg: float, b_deg: float) -> float:
        return abs((a_deg - b_deg + 180.0) % 360.0 - 180.0)

    @classmethod
    def _circular_mean_deg(cls, phase_values_deg) -> float:
        if not phase_values_deg:
            return 0.0
        s = 0.0
        c = 0.0
        for p in phase_values_deg:
            r = math.radians(p)
            s += math.sin(r)
            c += math.cos(r)
        if abs(s) < 1e-12 and abs(c) < 1e-12:
            return cls._wrap_phase_deg(float(statistics.fmean(phase_values_deg)))
        return cls._wrap_phase_deg(math.degrees(math.atan2(s, c)))

    @classmethod
    def _resolve_pi_ambiguity_deg(cls, phase_deg: float, ref_deg: float) -> float:
        cand0 = cls._wrap_phase_deg(phase_deg)
        cand1 = cls._wrap_phase_deg(phase_deg + 180.0)
        if cls._circular_distance_deg(cand1, ref_deg) < cls._circular_distance_deg(cand0, ref_deg):
            return cand1
        return cand0

    def _finalize_batch_metrics(self) -> None:
        """Finalize one report from 20 decoded stats and reset batch accumulators."""
        peak_pos_avg = float(statistics.fmean(self.batch_peak_pos_codes))
        peak_neg_avg = float(statistics.fmean(self.batch_peak_neg_codes))
        peak_pp_avg = peak_pos_avg - peak_neg_avg
        phase_avg = self._circular_mean_deg(self.batch_phases_deg)
        cordic_phase_raw_avg = self._circular_mean_deg(self.batch_cordic_phases_deg_raw)
        cordic_phase_avg = self._circular_mean_deg(self.batch_cordic_phases_deg) + 19.0 # empirical correction for CORDIC atan2 scaling/offset
        n_cycles_avg = float(statistics.fmean(self.batch_n_cycles))
        freq_avg = float(statistics.fmean(self.batch_freqs_mhz))
        freq_hz = freq_avg * 1_000_000.0

        peak_pos_volts = self.code_to_volts(peak_pos_avg)
        peak_neg_volts = self.code_to_volts(peak_neg_avg)
        peak_pp_volts = peak_pos_volts - peak_neg_volts
        # For a sinusoid, Vrms = Vpp / (2*sqrt(2)); therefore Vrms^2 = Vpp^2 / 8.
        v2rms_v2 = (peak_pp_volts * peak_pp_volts) / 8.0

        self.latest_metrics = {
            "peak_pos_code": peak_pos_avg,
            "peak_neg_code": peak_neg_avg,
            "peak_pp_code": peak_pp_avg,
            "peak_pos_volts": peak_pos_volts,
            "peak_neg_volts": peak_neg_volts,
            "peak_pp_volts": peak_pp_volts,
            "v2rms_v2": v2rms_v2,
            "phase_deg": phase_avg,
            "cordic_phase_deg_raw": cordic_phase_raw_avg,
            "cordic_phase_deg": cordic_phase_avg,
            "n_cycles": n_cycles_avg,
            "freq_mhz": freq_avg,
            "freq_hz": freq_hz,
        }

        if self.csv_writer:
            ts = time.time()
            ts_us = int((ts % 1) * 1_000_000)
            ts_str = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(ts)) + f".{ts_us:06d}"
            self.csv_writer.writerow(
                [
                    ts_str,
                    self.reports_generated + 1,
                    self.total_stats_read,
                    f"{peak_pos_avg:.3f}",
                    f"{peak_neg_avg:.3f}",
                    f"{peak_pos_volts:.6f}",
                    f"{peak_neg_volts:.6f}",
                    f"{v2rms_v2:.9f}",
                    f"{phase_avg:.3f}",
                    f"{cordic_phase_raw_avg:.3f}",
                    f"{cordic_phase_avg:.3f}",
                    f"{n_cycles_avg:.3f}",
                    f"{freq_hz:.3f}",
                    f"{freq_avg:.6f}",
                ]
            )

        if self.batch_v2rms_samples:
            block_mean = float(statistics.fmean(self.batch_v2rms_samples))
            self.latest_block_v2rms = block_mean
            self.block_history.append(block_mean)
            # Variance is computed from the history of block means
            self.latest_block_var = (
                float(statistics.variance(self.block_history))
                if len(self.block_history) > 1 else 0.0
            )

        self.reports_generated += 1
        self.batch_peak_pos_codes.clear()
        self.batch_peak_neg_codes.clear()
        self.batch_phases_deg.clear()
        self.batch_cordic_phases_deg_raw.clear()
        self.batch_cordic_phases_deg.clear()
        self.batch_n_cycles.clear()
        self.batch_freqs_mhz.clear()
        self.batch_v2rms_samples.clear()
        self.batch_sliding_outputs.clear()

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

        # Parse framed packets: [sync][9-byte payload].
        # Validate lock by requiring another sync at a frame boundary.
        # The next sync may be +10, +20, ... if frames are dropped upstream.
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
            n_cycles = self._decode_n_cycles(stat_bytes)
            cordic_phase_raw = self._decode_cordic_phase(stat_bytes)

            # Transport should carry offset-binary peaks with pos >= neg; auto-correct if inverted.
            if peak_pos_code < peak_neg_code:
                peak_pos_code, peak_neg_code = peak_neg_code, peak_pos_code

            # Optional debug output for raw packet decoding.
            if self.debug_stats and (self.total_stats_read < 10 or (self.total_stats_read % 100) == 0):
                print(
                    f"DEBUG stat {self.total_stats_read}: frame={self.SYNC_BYTE:02x} "
                    f"{' '.join(f'{b:02x}' for b in stat_bytes)} "
                    f"peak_pos={peak_pos_code} peak_neg={peak_neg_code} phase_raw={phase_raw} "
                    f"freq_raw={freq_raw} n_cycles={n_cycles} cordic_raw={cordic_phase_raw} "
                    f"rejected={self.frames_rejected}"
                )

            # Guard against stream-format mismatch (e.g., 8-byte FPGA stream with 10-byte parser).
            # A common signature is n_cycles high byte equals SYNC (0xA7xx), which is not valid N.
            if n_cycles < self.MIN_N_CYCLES or n_cycles > self.MAX_N_CYCLES:
                self.invalid_freq_stats += 1
                if (not self.stream_mismatch_warned) and ((n_cycles >> 8) & 0xFF) == self.SYNC_BYTE:
                    print(
                        "WARNING: Detected invalid n_cycles with sync-byte signature (0xA7xx). "
                        "This usually means Python expects 10-byte stats but FPGA is still sending 8-byte stats."
                    )
                    self.stream_mismatch_warned = True
                continue

            # Compute frequency first (needed for phase normalization)
            if freq_raw > 0 and n_cycles > 0:
                freq_mhz = (self.sample_rate_msps * n_cycles) / float(freq_raw)
            else:
                freq_mhz = 0.0

            # Phase from I-to-Q zero-crossing delay (time-domain, no amplitude dependence)
            # phase_raw = sum of I-to-Q delays in clocks over N cycles
            # phase_deg = 360 * delay_sum / total_clks (N cancels)
            if freq_raw > 0:
                phase_deg = 360.0 * phase_raw / float(freq_raw) - self.phase_reference_deg
                # Normalize to [-180, 180]
                phase_deg = (phase_deg + 180.0) % 360.0 - 180.0
            else:
                phase_deg = 0.0

            # CORDIC atan2 phase: cordic_phase_raw is sum of signed 16-bit phases over N crossings.
            # RTL already aligns the sampling strobe to CORDIC latency, so no frequency-dependent
            # correction is needed here.
            if n_cycles > 0:
                cordic_phase_deg_raw = cordic_phase_raw * 180.0 / 32768.0
                cordic_phase_deg_raw -= self.phase_reference_deg
                cordic_phase_deg_raw = self._wrap_phase_deg(cordic_phase_deg_raw)

                cordic_phase_deg_resolved = cordic_phase_deg_raw
                if self.resolve_pi_ambiguity:
                    branch_ref = phase_deg if self.resolve_with_zc_phase else self._last_cordic_phase_stable_deg
                    if branch_ref is None:
                        branch_ref = phase_deg
                    cordic_phase_deg_resolved = self._resolve_pi_ambiguity_deg(
                        cordic_phase_deg_raw,
                        branch_ref,
                    )

                if self._cordic_phase_ema_deg is None:
                    self._cordic_phase_ema_deg = cordic_phase_deg_resolved
                    self._cordic_reject_streak = 0
                else:
                    # EMA on circular manifold with jump rejection to suppress
                    # packet-level glitches that appear as random sign flips.
                    delta = self._wrap_phase_deg(cordic_phase_deg_resolved - self._cordic_phase_ema_deg)
                    if abs(delta) > self.phase_max_step_deg:
                        self.cordic_phase_rejects += 1
                        self._cordic_reject_streak += 1
                        if self._cordic_reject_streak >= self.phase_relock_rejects:
                            # Reacquire lock if stream legitimately jumped phase.
                            self._cordic_phase_ema_deg = cordic_phase_deg_resolved
                            self._cordic_reject_streak = 0
                    else:
                        self._cordic_phase_ema_deg = self._wrap_phase_deg(
                            self._cordic_phase_ema_deg + self.phase_ema_alpha * delta
                        )
                        self._cordic_reject_streak = 0

                cordic_phase_deg = self._cordic_phase_ema_deg
                self._last_cordic_phase_stable_deg = cordic_phase_deg
            else:
                cordic_phase_deg_raw = 0.0
                cordic_phase_deg = 0.0

            # Physical consistency check:
            # period_clks = raw_clk_count / n_cycles should be >= ~2 near Nyquist.
            period_clks = (float(freq_raw) / float(n_cycles)) if n_cycles > 0 else 0.0

            if (
                ((n_cycles >> 8) & 0xFF) == self.SYNC_BYTE
                or n_cycles < self.MIN_N_CYCLES
                or n_cycles > self.MAX_N_CYCLES
                or freq_mhz <= 0.0
                or freq_mhz > self.max_valid_freq_mhz
                or period_clks < self.min_valid_period_clks
            ):
                self.invalid_freq_stats += 1
                if (not self.stream_mismatch_warned) and ((n_cycles >> 8) & 0xFF) == self.SYNC_BYTE:
                    print(
                        "WARNING: Detected invalid n_cycles with sync-byte signature (0xA7xx). "
                        "This usually means Python expects 10-byte stats but FPGA is still sending 8-byte stats."
                    )
                    self.stream_mismatch_warned = True
                if self.debug_stats and (
                    self.invalid_freq_stats <= 10 or (self.invalid_freq_stats % 100) == 0
                ):
                    print(
                        f"DEBUG invalid stat {self.total_stats_read}: "
                        f"freq_raw={freq_raw} n_cycles={n_cycles} "
                        f"period_clks={period_clks:.3f} freq_mhz={freq_mhz:.3f} "
                        f"invalid_total={self.invalid_freq_stats}"
                    )
                continue

            self.batch_peak_pos_codes.append(peak_pos_code)
            self.batch_peak_neg_codes.append(peak_neg_code)
            self.batch_phases_deg.append(phase_deg)
            self.batch_cordic_phases_deg_raw.append(cordic_phase_deg_raw)
            self.batch_cordic_phases_deg.append(cordic_phase_deg)
            self.batch_n_cycles.append(n_cycles)
            self.batch_freqs_mhz.append(freq_mhz)

            # Per-stat V²rms for block vs sliding comparison
            stat_vpp = 0.0
            stat_v2rms = 0.0
            sliding_v2rms = 0.0
            sliding_var = 0.0
            if self.rms_csv_writer:
                stat_vpp = self.code_to_volts(peak_pos_code) - self.code_to_volts(peak_neg_code)
                stat_v2rms = (stat_vpp * stat_vpp) / 8.0
                self.batch_v2rms_samples.append(stat_v2rms)
                # Sliding: subtract oldest if buffer full, then add new
                if len(self.sliding_buf) == self.sliding_window_size:
                    self.sliding_running_sum -= self.sliding_buf[0]
                self.sliding_buf.append(stat_v2rms)
                self.sliding_running_sum += stat_v2rms
                # Record this step's sliding output
                sliding_v2rms = self.sliding_running_sum / len(self.sliding_buf)
                self.batch_sliding_outputs.append(sliding_v2rms)
                sliding_var = (
                    statistics.variance(self.batch_sliding_outputs)
                    if len(self.batch_sliding_outputs) > 1 else 0.0
                )

            self.total_stats_read += 1

            block_updated = 0
            if len(self.batch_peak_pos_codes) >= self.batch_size:
                self._finalize_batch_metrics()
                block_updated = 1

            if self.rms_csv_writer:
                # Before first block measurement, show NaN for block metrics
                if self.reports_generated == 0:
                    block_rms_str = "NaN"
                    block_var_str = "NaN"
                else:
                    block_rms_str = f"{self.latest_block_v2rms:.9f}"
                    block_var_str = f"{self.latest_block_var:.12f}"
                
                ts = time.time()
                ts_us = int((ts % 1) * 1_000_000)
                ts_str = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(ts)) + f".{ts_us:06d}"
                self.rms_csv_writer.writerow(
                    [
                        ts_str,
                        self.total_stats_read,
                        self.reports_generated,
                        block_updated,
                        f"{freq_mhz:.6f}",
                        f"{stat_vpp:.6f}",
                        f"{stat_v2rms:.9f}",
                        block_rms_str,
                        block_var_str,
                        f"{sliding_v2rms:.9f}",
                        f"{sliding_var:.12f}",
                    ]
                )

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
        """Decode IQ delay sum from bytes [3:7] as unsigned 32-bit."""
        return (stat_bytes[3] << 24) | (stat_bytes[4] << 16) | (stat_bytes[5] << 8) | stat_bytes[6]

    @staticmethod
    def _decode_freq(stat_bytes: bytearray) -> int:
        """Decode frequency from bytes [7:9]."""
        return (stat_bytes[7] << 8) | stat_bytes[8]  # 16-bit

    @staticmethod
    def _decode_n_cycles(stat_bytes: bytearray) -> int:
        """Decode N (cycle count used) from bytes [9:11]."""
        return (stat_bytes[9] << 8) | stat_bytes[10]  # 16-bit

    @staticmethod
    def _decode_cordic_phase(stat_bytes: bytearray) -> int:
        """Decode CORDIC phase sum from bytes [11:15] as signed 32-bit."""
        raw = (stat_bytes[11] << 24) | (stat_bytes[12] << 16) | (stat_bytes[13] << 8) | stat_bytes[14]
        if raw >= 0x80000000:
            raw -= 0x100000000
        return raw

    def compute_metrics(self) -> dict:
        """Return most recent 20-sample batch report."""
        if self.latest_metrics is None:
            return {
                "error": (
                    f"Collecting initial batch: "
                    f"{len(self.batch_peak_pos_codes)}/{self.batch_size} stats"
                )
            }
        return self.latest_metrics

    def print_metrics(self, metrics: dict) -> None:
        """Print metrics to console."""
        if "error" in metrics:
            print(f"  [Warming up...] {metrics['error']}", end="\r")
            return

        print(
            f"\n{'='*70}"
            f"\nADC Stats Analyzer | Stats: {self.total_stats_read:,} | "
            f"Packets: {self.packets_received} | Bytes: {self.bytes_received:,} | "
            f"CORDIC rejects: {self.cordic_phase_rejects}"
            f"\n{'='*70}"
        )
        print(f"Batch averaging: {self.batch_size} stats/report | Reports: {self.reports_generated}")
        print(
            f"FPGA-Computed Statistics:\n"
            f"  Peak (+) cos(I):  {metrics['peak_pos_volts']:.4f} V "
            f"(code {metrics['peak_pos_code']:.1f})\n"
            f"  Peak (-) cos(I):  {metrics['peak_neg_volts']:.4f} V "
            f"(code {metrics['peak_neg_code']:.1f})\n"
            f"  Peak-to-Peak I:   {metrics['peak_pp_volts']:.4f} V "
            f"(code {metrics['peak_pp_code']:.1f})\n"
            f"  Power (V^2rms; R=1 Ω):     {metrics['v2rms_v2']:.6f} V^2\n"
        )
        print(
            f"Phase & Frequency:\n"
            f"  Phase ZC (sin Q):     {metrics['phase_deg']:.2f}\u00b0\n"
            f"  Phase CORDIC raw:     {metrics['cordic_phase_deg_raw']:.2f}\u00b0\n"
            f"  Phase CORDIC stable:  {metrics['cordic_phase_deg']:.2f}\u00b0\n"
            f"  N cycles:             {metrics['n_cycles']:.1f}\n"
            f"  Frequency:            {metrics['freq_mhz']:.4f} MHz"
        )

    def print_metrics_curses(self, stdscr, metrics: dict) -> None:
        """Update screen with curses (like 'top' command)."""
        try:
            row = 0

            if "error" in metrics:
                stdscr.addstr(row, 0, f"[Warming up...] {metrics['error']}")
                stdscr.clrtoeol()
                row += 1
            else:
                stdscr.addstr(row, 0, f"{'='*70}")
                stdscr.clrtoeol()
                row += 1

                stdscr.addstr(row, 0,
                    f"ADC Stats | Stats: {self.total_stats_read:,} | "
                    f"Packets: {self.packets_received} | Bytes: {self.bytes_received:,} | "
                    f"CORDIC rejects: {self.cordic_phase_rejects}")
                stdscr.clrtoeol()
                row += 1

                stdscr.addstr(row, 0,
                    f"Batch avg: {self.batch_size} stats/report | Reports: {self.reports_generated}")
                stdscr.clrtoeol()
                row += 1

                stdscr.addstr(row, 0, f"{'='*70}")
                stdscr.clrtoeol()
                row += 1

                stdscr.addstr(row, 0, "FPGA-Computed Statistics (Cosine I):")
                stdscr.clrtoeol()
                row += 1
                stdscr.addstr(row, 0,
                    f"  Peak (+) I:     {metrics['peak_pos_volts']:.4f} V "
                    f"(code {metrics['peak_pos_code']:.1f})")
                stdscr.clrtoeol()
                row += 1
                stdscr.addstr(row, 0,
                    f"  Peak (-) I:     {metrics['peak_neg_volts']:.4f} V "
                    f"(code {metrics['peak_neg_code']:.1f})")
                stdscr.clrtoeol()
                row += 1
                stdscr.addstr(row, 0,
                    f"  Peak-to-Peak I: {metrics['peak_pp_volts']:.4f} V "
                    f"(code {metrics['peak_pp_code']:.1f})")
                stdscr.clrtoeol()
                row += 2

                stdscr.addstr(row, 0,
                    f"  V^2rms (R=1):   {metrics['v2rms_v2']:.6f} V^2")
                stdscr.clrtoeol()
                row += 2

                stdscr.addstr(row, 0, "Phase & Frequency:")
                stdscr.clrtoeol()
                row += 1
                stdscr.addstr(row, 0, f"  Phase ZC (sin Q):     {metrics['phase_deg']:.2f}\u00b0")
                stdscr.clrtoeol()
                row += 1
                stdscr.addstr(row, 0, f"  Phase CORDIC raw:     {metrics['cordic_phase_deg_raw']:.2f}\u00b0")
                stdscr.clrtoeol()
                row += 1
                stdscr.addstr(row, 0, f"  Phase CORDIC stable:  {metrics['cordic_phase_deg']:.2f}\u00b0")
                stdscr.clrtoeol()
                row += 1
                stdscr.addstr(row, 0, f"  N cycles:             {metrics['n_cycles']:.1f}")
                stdscr.clrtoeol()
                row += 1
                stdscr.addstr(row, 0, f"  Frequency:            {metrics['freq_mhz']:.4f} MHz")
                stdscr.clrtoeol()
                row += 2

                stdscr.addstr(row, 0, "Press Ctrl+C to stop")
                stdscr.clrtoeol()
                row += 1

            stdscr.clrtobot()
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
                if new_count > 0 and self.rms_csv_file:
                    self.rms_csv_file.flush()

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
            if self.rms_csv_file:
                self.rms_csv_file.close()
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
    parser.add_argument(
        "--rms-csv",
        default="",
        help="CSV file for block vs sliding RMS comparison output",
    )
    parser.add_argument(
        "--sliding-window",
        type=int,
        default=50,
        help="Sliding RMS window size in stats (default: 50)",
    )
    parser.add_argument(
        "--phase-ema-alpha",
        type=float,
        default=0.25,
        help="CORDIC phase EMA alpha in [0,1] for live stabilization",
    )
    parser.add_argument(
        "--no-resolve-pi",
        action="store_true",
        help="Disable 180-degree branch ambiguity resolution for CORDIC phase",
    )
    parser.add_argument(
        "--phase-max-step-deg",
        type=float,
        default=35.0,
        help="Reject per-stat CORDIC phase jumps larger than this many degrees",
    )
    parser.add_argument(
        "--relock-rejects",
        type=int,
        default=20,
        help="Reacquire CORDIC lock after this many consecutive rejected jumps",
    )
    parser.add_argument(
        "--no-zc-branch-ref",
        action="store_true",
        help="Resolve CORDIC 180-degree branch using last stable phase instead of ZC phase",
    )
    args = parser.parse_args()

    csv_output_path = None
    if args.csv_output.strip():
        csv_output_path = pathlib.Path(args.csv_output)

    rms_csv_path = None
    if args.rms_csv.strip():
        rms_csv_path = pathlib.Path(args.rms_csv)

    analyzer = ADCStatsAnalyzer(
        bind_ip=args.bind_ip,
        bind_port=args.bind_port,
        phase_reference_deg=args.phase_reference_deg,
        fpga_ip=args.fpga_ip,
        prime_port=args.prime_port,
        no_prime=args.no_prime,
        sample_rate_msps=args.sample_rate_msps,
        ui_refresh_sec=args.ui_refresh_sec,
        debug_stats=args.debug_stats,
        csv_output=csv_output_path,
        rms_csv_output=rms_csv_path,
        sliding_window_size=args.sliding_window,
        recv_size=args.recv_size,
        timeout=args.timeout,
        resolve_pi_ambiguity=not args.no_resolve_pi,
        phase_ema_alpha=args.phase_ema_alpha,
        phase_max_step_deg=args.phase_max_step_deg,
        resolve_with_zc_phase=not args.no_zc_branch_ref,
        phase_relock_rejects=args.relock_rejects,
    )

    duration = args.duration_sec if args.duration_sec > 0 else None
    analyzer.run(duration)

    return 0


if __name__ == "__main__":
    sys.exit(main())
