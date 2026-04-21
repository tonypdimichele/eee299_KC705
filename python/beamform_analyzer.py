#!/usr/bin/env python3
"""Real-time ADC analyzer for beamforming validation.

Direct UDP stream listening—no CSV file, no disk I/O.

Displays:
  - FFT spectrum (tone location, SNR)
  - Rolling waveform (last 100 ms)
  - Phase tracking (array alignment reference)
  - RMS power and stability metrics
  - Frequency error

Usage:
    python3 python/beamform_analyzer.py --bind-port 40000 --tone-freq-mhz 10.0 --duration-sec 1
    python3 python/beamform_analyzer.py --bind-port 40000 --tone-freq-mhz 5.01 --cal-vpp 1.04 --cal-peak-code 2267 --cal-trough-code 1840 --duration-sec 1

Configure your FPGA to send ADC stream to this port; analyzer listens directly.
Optional CSV output for recording while analyzing:
    --csv-output adc_capture.csv --duration-sec 1

If your stream is interleaved quadrature (I,Q,I,Q...), enable:
    --iq-interleaved --duration-sec 1
"""

import argparse
import csv
import curses
import numpy as np
import os
import pathlib
import socket
import sys
import time
from collections import deque
from typing import Optional, Tuple

plt = None
FuncAnimation = None
MATPLOTLIB_AVAILABLE = False

try:
    import matplotlib
    # Try to set backend before importing pyplot
    if not os.environ.get("DISPLAY"):
        matplotlib.use("Agg")  # Non-interactive backend for headless systems
    import matplotlib.pyplot as plt
    from matplotlib.animation import FuncAnimation
    MATPLOTLIB_AVAILABLE = True
except (ImportError, Exception):
    MATPLOTLIB_AVAILABLE = False


class BeamformAnalyzer:
    """Real-time beamforming analyzer reading ADC UDP stream directly."""

    def __init__(
        self,
        bind_ip: str,
        bind_port: int,
        tone_freq_mhz: float,
        sample_rate_msps: float = 125.0,
        rtl_decim: int = 4,
        window_ms: float = 100.0,
        update_interval_ms: float = 1000.0,
        vref: float = 1.0,
        cal_vpp: Optional[float] = None,
        cal_peak_code: Optional[float] = None,
        cal_trough_code: Optional[float] = None,
        plot_freq_range_mhz: Optional[Tuple[float, float]] = None,
        enable_plot: bool = True,
        waveform_cycles: float = 6.0,
        iq_interleaved: bool = False,
        iq_swap: bool = False,
        byte_phase: str = "auto",
        plot_raw_codes: bool = True,
        interp_factor: int = 4,
        waveform_render: str = "recon",
        force_live_plot: bool = False,
        plot_file: Optional[pathlib.Path] = None,
        csv_output: Optional[pathlib.Path] = None,
        recv_size: int = 8192,
        timeout: float = 1.0,
    ):
        self.bind_ip = bind_ip
        self.bind_port = bind_port
        self.tone_freq_mhz = tone_freq_mhz
        self.sample_rate_msps = sample_rate_msps
        self.adc_sample_rate_hz = sample_rate_msps * 1e6
        self.rtl_decim = max(1, int(rtl_decim))
        self.window_ms = window_ms
        self.update_interval_ms = update_interval_ms
        self.vref = vref
        self.cal_vpp = cal_vpp
        self.cal_peak_code = cal_peak_code
        self.cal_trough_code = cal_trough_code
        self.enable_plot = enable_plot and MATPLOTLIB_AVAILABLE
        self.waveform_cycles = waveform_cycles
        self.iq_interleaved = iq_interleaved
        self.iq_swap = iq_swap
        self.byte_phase_mode = byte_phase
        self.plot_raw_codes = plot_raw_codes
        self.interp_factor = max(1, int(interp_factor))
        self.waveform_render = waveform_render
        self.force_live_plot = force_live_plot
        self.plot_file = plot_file
        self.plot_freq_range_mhz = plot_freq_range_mhz
        self.recv_size = recv_size
        self.timeout = timeout
        self.has_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))

        self.volts_center_code = 2048.0
        self.volts_per_code = self.vref / 2048.0
        self._configure_voltage_scaling()

        # Effective rates after RTL decimation and optional IQ interleave split.
        decoded_factor = 2.0 if self.iq_interleaved else 1.0
        self.stream_sample_rate_hz = (self.adc_sample_rate_hz / self.rtl_decim) * decoded_factor
        self.channel_sample_rate_hz = self.stream_sample_rate_hz / (2.0 if self.iq_interleaved else 1.0)

        # CSV output (optional)
        self.csv_output = csv_output
        if csv_output:
            csv_output.parent.mkdir(parents=True, exist_ok=True)
            self.csv_file = open(csv_output, "w", newline="", encoding="utf-8")
            self.csv_writer = csv.writer(self.csv_file)
            self.csv_writer.writerow(
                [
                    "host_time_iso",
                    "sample_index",
                    "adc1_code",
                    "adc1_volts_diff",
                    "b0_adc1_msb",
                    "b1_adc1_lsb",
                ]
            )
        else:
            self.csv_file = None
            self.csv_writer = None

        # UDP socket
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        self.sock.bind((bind_ip, bind_port))
        self.sock.settimeout(timeout)

        # Sliding window of samples
        self.window_samples = int((window_ms / 1000.0) * self.stream_sample_rate_hz)
        if self.iq_interleaved:
            self.i_samples = deque(maxlen=max(16, self.window_samples // 2))
            self.q_samples = deque(maxlen=max(16, self.window_samples // 2))
            self.i_codes = deque(maxlen=max(16, self.window_samples // 2))
            self.q_codes = deque(maxlen=max(16, self.window_samples // 2))
            self.i_time_us = deque(maxlen=max(16, self.window_samples // 2))
            self.q_time_us = deque(maxlen=max(16, self.window_samples // 2))
            self.next_is_i = not self.iq_swap
        else:
            self.samples = deque(maxlen=self.window_samples)
            self.codes = deque(maxlen=self.window_samples)
            self.time_us = deque(maxlen=self.window_samples)

        # Tracking
        self.last_update_time = time.time()
        self.reference_phase = None
        self.total_samples_read = 0
        self.packets_received = 0
        self.bytes_received = 0
        self.stream_byte_index = 0
        self.pending_msb = None
        self.phase_probe = bytearray()
        if byte_phase == "auto":
            self.byte_phase = None
        else:
            self.byte_phase = int(byte_phase)
        self.msb_seen = 0
        self.msb_bad = 0

        print(f"Analyzer config:")
        print(f"  Listen: {bind_ip}:{bind_port}")
        print(f"  Tone freq: {tone_freq_mhz} MHz")
        print(f"  ADC sample rate: {sample_rate_msps} MSPS")
        print(f"  RTL decimation: {self.rtl_decim}")
        print(f"  Stream sample rate: {self.stream_sample_rate_hz/1e6:.3f} MSPS")
        print(f"  Channel sample rate: {self.channel_sample_rate_hz/1e6:.3f} MSPS")
        print(f"  Window: {window_ms} ms = {self.window_samples} samples")
        print(f"  Waveform cycles shown: {waveform_cycles}")
        print(f"  IQ interleaved mode: {'on' if iq_interleaved else 'off'}")
        if self.iq_interleaved:
            print(f"  IQ order: {'Q,I (swapped)' if self.iq_swap else 'I,Q'}")
        print(f"  Byte phase mode: {byte_phase}")
        print(f"  Waveform source: {'raw ADC code' if plot_raw_codes else 'volts'}")
        print(f"  Waveform interpolation: x{self.interp_factor}")
        print(f"  Waveform render mode: {self.waveform_render}")
        print(f"  VREF: {vref} V")
        if self.cal_vpp is not None:
            print(
                "  Voltage calibration: "
                f"{self.cal_vpp:.6f} Vpp from codes {self.cal_peak_code:.3f}/{self.cal_trough_code:.3f}"
            )
            print(
                f"  Cal center code: {self.volts_center_code:.3f} | "
                f"scale: {self.volts_per_code:.9f} V/code"
            )
        if csv_output:
            print(f"  CSV output: {csv_output}")
        if plot_file:
            print(f"  Plot output (snapshot): {plot_file}")
        if self.enable_plot and not plot_file and not self.has_display and not self.force_live_plot:
            # No usable GUI display; force terminal mode so behavior is explicit.
            self.enable_plot = False

        if self.enable_plot and not plot_file:
            print(f"  Live matplotlib plot: enabled")
        elif not self.enable_plot:
            print(f"  Display: terminal UI (curses)")

    def read_udp_chunk(self) -> int:
        """Read UDP packet, decode ADC samples, return count of new samples."""
        count = 0
        try:
            payload, (src_ip, src_port) = self.sock.recvfrom(self.recv_size)
        except socket.timeout:
            return 0

        self.packets_received += 1
        self.bytes_received += len(payload)

        if self.byte_phase is None:
            need = max(0, 256 - len(self.phase_probe))
            if need > 0:
                self.phase_probe.extend(payload[:need])
            if len(self.phase_probe) >= 64:
                self.byte_phase = self._detect_byte_phase(self.phase_probe)
                print(f"Auto-detected sample byte phase: {self.byte_phase}")
                self.phase_probe.clear()

        # Decode as a continuous byte stream so packet boundaries do not affect framing.
        for b in payload:
            if self.byte_phase is None:
                self.stream_byte_index += 1
                continue

            is_msb = ((self.stream_byte_index - self.byte_phase) & 1) == 0

            if is_msb:
                self.pending_msb = b
                self.msb_seen += 1
                if (b & 0xF0) != 0:
                    self.msb_bad += 1
            else:
                if self.pending_msb is not None:
                    b0 = self.pending_msb
                    b1 = b
                    adc1_code = self.decode_adc1_sample(b0, b1)
                    volts = self.offset_binary_code_to_volts(adc1_code)

                    time_us = self.total_samples_read / self.stream_sample_rate_hz * 1e6
                    if self.iq_interleaved:
                        if self.next_is_i:
                            self.i_samples.append(volts)
                            self.i_codes.append(adc1_code)
                            self.i_time_us.append(time_us)
                        else:
                            self.q_samples.append(volts)
                            self.q_codes.append(adc1_code)
                            self.q_time_us.append(time_us)
                        self.next_is_i = not self.next_is_i
                    else:
                        self.samples.append(volts)
                        self.codes.append(adc1_code)
                        self.time_us.append(time_us)

                    # Optional CSV output
                    if self.csv_writer:
                        ts = time.time()
                        self.csv_writer.writerow(
                            [
                                time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(ts)),
                                self.total_samples_read,
                                adc1_code,
                                f"{volts:.9f}",
                                f"0x{b0:02X}",
                                f"0x{b1:02X}",
                            ]
                        )

                    self.total_samples_read += 1
                    count += 1

            self.stream_byte_index += 1

        # If we see persistent MSB format violations, flip phase once to recover.
        if self.byte_phase is not None and self.msb_seen >= 128:
            bad_ratio = self.msb_bad / float(self.msb_seen)
            if bad_ratio > 0.30:
                self.byte_phase ^= 1
                self.pending_msb = None
                print(f"High MSB format error ratio ({bad_ratio:.2f}); flipped byte phase to {self.byte_phase}")
            self.msb_seen = 0
            self.msb_bad = 0

        return count

    @staticmethod
    def _detect_byte_phase(probe: bytes) -> int:
        """Detect sample byte phase via MSB format: MSB bytes carry only low nibble data."""
        best_phase = 0
        best_score = -1.0
        for phase in (0, 1):
            seq = probe[phase::2]
            if len(seq) == 0:
                continue
            good = sum(1 for x in seq if (x & 0xF0) == 0)
            score = good / float(len(seq))
            if score > best_score:
                best_score = score
                best_phase = phase
        return best_phase

    @staticmethod
    def decode_adc1_sample(b0: int, b1: int) -> int:
        """Decode one ADC1 sample from 2 stream bytes."""
        return ((b0 & 0x0F) << 8) | b1

    def _configure_voltage_scaling(self) -> None:
        """Configure volts-per-code conversion from either VREF or measured calibration."""
        if self.cal_vpp is None:
            return

        if self.cal_peak_code is None or self.cal_trough_code is None:
            raise ValueError("Voltage calibration requires both cal_peak_code and cal_trough_code")

        code_span = float(self.cal_peak_code) - float(self.cal_trough_code)
        if abs(code_span) < 1e-12:
            raise ValueError("Voltage calibration code span must be non-zero")

        self.volts_center_code = (float(self.cal_peak_code) + float(self.cal_trough_code)) / 2.0
        self.volts_per_code = float(self.cal_vpp) / code_span

    def offset_binary_code_to_volts(self, code: int) -> float:
        """Convert ADC code to volts using ideal VREF or measured calibration."""
        return (code - self.volts_center_code) * self.volts_per_code

    def compute_metrics(self) -> dict:
        """Compute beamforming-relevant metrics from current window."""
        if self.iq_interleaved:
            n_iq = min(len(self.i_samples), len(self.q_samples))
            if n_iq < 10:
                return {"error": "Insufficient IQ samples"}
            i_arr = np.array(list(self.i_samples)[-n_iq:])
            q_arr = np.array(list(self.q_samples)[-n_iq:])
            i_code_arr = np.array(list(self.i_codes)[-n_iq:])
            q_code_arr = np.array(list(self.q_codes)[-n_iq:])
            samples_arr = i_arr
            codes_arr = i_code_arr
            q_peak_pos = np.max(q_arr)
            q_peak_neg = np.min(q_arr)
            q_peak_to_peak = q_peak_pos - q_peak_neg
        else:
            if len(self.samples) < 10:
                return {"error": "Insufficient samples"}
            samples_arr = np.array(list(self.samples))
            codes_arr = np.array(list(self.codes))
            q_peak_pos = None
            q_peak_neg = None
            q_peak_to_peak = None

        # Time-domain metrics
        rms_v = np.sqrt(np.mean(samples_arr**2))
        peak_pos = np.max(samples_arr)
        peak_neg = np.min(samples_arr)
        peak_to_peak = peak_pos - peak_neg
        peak_avg_ratio = peak_to_peak / (2 * rms_v) if rms_v > 0 else 0

        # Power metrics (normalized to 50 Ohm)
        rms_dbm = 10 * np.log10((rms_v**2 / 50.0) * 1000 + 1e-12)

        # FFT for tone tracking
        n_fft = len(samples_arr)
        samples_windowed = samples_arr.copy()
        self.apply_hann_window(samples_windowed)

        fft_out = np.fft.rfft(samples_windowed)
        freqs = np.fft.rfftfreq(n_fft, 1.0 / self.channel_sample_rate_hz) / 1e6  # MHz
        power_db = 20 * np.log10(np.abs(fft_out) + 1e-12)

        # Find tone bin (nearest to expected tone_freq_mhz)
        tone_idx = np.argmin(np.abs(freqs - self.tone_freq_mhz))
        tone_freq_found, tone_power_db = self._quadratic_peak_refine(freqs, power_db, tone_idx)

        # Estimate noise floor (median power excluding tone region ±1 MHz)
        tone_region = np.abs(freqs - self.tone_freq_mhz) < 1.0
        noise_power_db = np.median(power_db[~tone_region])
        snr_db = tone_power_db - noise_power_db

        # Phase tracking (complex FFT at tone frequency)
        tone_complex = fft_out[tone_idx]
        phase_rad = np.angle(tone_complex)
        if self.reference_phase is None:
            self.reference_phase = phase_rad
        phase_error_rad = phase_rad - self.reference_phase
        phase_error_deg = np.degrees(phase_error_rad)

        # Reconstruct continuous-tone extrema via least-squares sinusoid fit.
        recon = self._fit_sine_extrema(codes_arr.astype(float), tone_freq_found * 1e6)
        sampled_peak_code = float(np.max(codes_arr))
        sampled_trough_code = float(np.min(codes_arr))
        sampled_pp_code = sampled_peak_code - sampled_trough_code

        if recon is not None:
            recon_peak_code, recon_trough_code = recon
            recon_pp_code = recon_peak_code - recon_trough_code
        else:
            recon_peak_code = sampled_peak_code
            recon_trough_code = sampled_trough_code
            recon_pp_code = sampled_pp_code

        # Frequency error
        freq_error_khz = (tone_freq_found - self.tone_freq_mhz) * 1000

        return {
            "rms_v": rms_v,
            "peak_pos": peak_pos,
            "peak_neg": peak_neg,
            "peak_to_peak": peak_to_peak,
            "q_peak_pos": q_peak_pos,
            "q_peak_neg": q_peak_neg,
            "q_peak_to_peak": q_peak_to_peak,
            "peak_avg_ratio": peak_avg_ratio,
            "rms_dbm": rms_dbm,
            "tone_freq_mhz": tone_freq_found,
            "tone_power_db": tone_power_db,
            "snr_db": snr_db,
            "noise_floor_db": noise_power_db,
            "phase_deg": phase_error_deg,
            "freq_error_khz": freq_error_khz,
            "sampled_peak_code": sampled_peak_code,
            "sampled_trough_code": sampled_trough_code,
            "sampled_pp_code": sampled_pp_code,
            "recon_peak_code": recon_peak_code,
            "recon_trough_code": recon_trough_code,
            "recon_pp_code": recon_pp_code,
            "fft_freqs": freqs,
            "fft_power_db": power_db,
            "samples_arr": samples_arr,
        }

    def _quadratic_peak_refine(self, freqs_mhz: np.ndarray, power_db: np.ndarray, k: int) -> Tuple[float, float]:
        """Refine FFT peak frequency/power using quadratic interpolation around bin k."""
        if k <= 0 or k >= (len(power_db) - 1):
            return float(freqs_mhz[k]), float(power_db[k])

        y1 = float(power_db[k - 1])
        y2 = float(power_db[k])
        y3 = float(power_db[k + 1])
        denom = (y1 - 2.0 * y2 + y3)
        if abs(denom) < 1e-12:
            return float(freqs_mhz[k]), float(y2)

        delta = 0.5 * (y1 - y3) / denom
        delta = max(-0.5, min(0.5, delta))
        bin_hz_mhz = float(freqs_mhz[1] - freqs_mhz[0]) if len(freqs_mhz) > 1 else 0.0
        f_ref = float(freqs_mhz[k] + delta * bin_hz_mhz)
        p_ref = float(y2 - 0.25 * (y1 - y3) * delta)
        return f_ref, p_ref

    def _fit_sine_extrema(self, y: np.ndarray, freq_hz: float) -> Optional[Tuple[float, float]]:
        """Fit y ~= A*sin(wt)+B*cos(wt)+C and return reconstructed peak/trough (same units as y)."""
        if len(y) < 8 or freq_hz <= 0:
            return None

        t = np.arange(len(y), dtype=float) / self.channel_sample_rate_hz
        w = 2.0 * np.pi * freq_hz
        X = np.column_stack((np.sin(w * t), np.cos(w * t), np.ones_like(t)))
        try:
            coeff, _, _, _ = np.linalg.lstsq(X, y, rcond=None)
        except Exception:
            return None

        amp = float(np.hypot(coeff[0], coeff[1]))
        offs = float(coeff[2])
        return offs + amp, offs - amp

    @staticmethod
    def apply_hann_window(samples: np.ndarray) -> np.ndarray:
        """Apply Hann window in-place for better FFT sidelobe suppression."""
        window = np.hanning(len(samples))
        samples[:] *= window
        return samples

    def print_metrics(self, metrics: dict) -> None:
        """Print metrics to console in an easy-to-read format."""
        if "error" in metrics:
            print(f"  [Warming up...] {metrics['error']}", end="\r")
            return

        print(
            f"\n{'='*70}"
            f"\nBeamforming Analyzer | Samples: {self.total_samples_read:,} | "
            f"Packets: {self.packets_received} | Bytes: {self.bytes_received:,}"
            f"\n{'='*70}"
        )
        print(
            f"Signal Quality:\n"
            f"  RMS Power:        {metrics['rms_v']:.6f} Vrms ({metrics['rms_dbm']:.1f} dBm @ 50Ω)"
            f"\n  Peak (+):         {metrics['peak_pos']:.6f} V"
            f"\n  Peak (-):         {metrics['peak_neg']:.6f} V"
            f"\n  Peak-to-Peak:     {metrics['peak_to_peak']:.6f} V"
            f"\n  Sampled Code P/T: {metrics['sampled_peak_code']:.2f}/{metrics['sampled_trough_code']:.2f}"
            f"\n  Recon Code P/T:   {metrics['recon_peak_code']:.2f}/{metrics['recon_trough_code']:.2f}"
            f"\n  Crest Factor:     {metrics['peak_avg_ratio']:.2f}x"
        )
        print(
            f"Tone Detection:\n"
            f"  Expected:         {self.tone_freq_mhz:.3f} MHz"
            f"\n  Found:            {metrics['tone_freq_mhz']:.3f} MHz"
            f"\n  Frequency Error:  {metrics['freq_error_khz']:.1f} kHz"
            f"\n  Tone Power:       {metrics['tone_power_db']:.1f} dB"
        )
        print(
            f"Noise & SNR:\n"
            f"  Noise Floor:      {metrics['noise_floor_db']:.1f} dB"
            f"\n  SNR:              {metrics['snr_db']:.1f} dB"
        )
        print(
            f"Array Alignment (Phase):\n"
            f"  Phase Error:      {metrics['phase_deg']:.2f}°"
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
                
                line = f"Beamforming Analyzer | Samples: {self.total_samples_read:,} | Packets: {self.packets_received} | Bytes: {self.bytes_received:,}"
                stdscr.addstr(row, 0, line[:70] if len(line) > 70 else line)
                row += 1
                
                line = f"{'='*70}"
                stdscr.addstr(row, 0, line[:70] if len(line) > 70 else line)
                row += 1
                
                stdscr.addstr(row, 0, "Signal Quality:")
                row += 1
                stdscr.addstr(row, 0, f"  RMS Power:      {metrics['rms_v']:.6f} Vrms ({metrics['rms_dbm']:.1f} dBm @ 50Ω)")
                row += 1
                stdscr.addstr(row, 0, f"  Peak (+):       {metrics['peak_pos']:.6f} V")
                row += 1
                stdscr.addstr(row, 0, f"  Peak (-):       {metrics['peak_neg']:.6f} V")
                row += 1
                stdscr.addstr(row, 0, f"  Peak-to-Peak:   {metrics['peak_to_peak']:.6f} V")
                row += 1
                stdscr.addstr(
                    row,
                    0,
                    f"  Code P/T (S/R): {metrics['sampled_peak_code']:.1f}/{metrics['sampled_trough_code']:.1f}  "
                    f"{metrics['recon_peak_code']:.1f}/{metrics['recon_trough_code']:.1f}",
                )
                row += 1
                if self.iq_interleaved and metrics["q_peak_to_peak"] is not None:
                    stdscr.addstr(row, 0, f"  Q Peak-to-Peak: {metrics['q_peak_to_peak']:.6f} V")
                    row += 1
                stdscr.addstr(row, 0, f"  Crest Factor:   {metrics['peak_avg_ratio']:.2f}x")
                row += 2
                
                stdscr.addstr(row, 0, "Tone Detection:")
                row += 1
                stdscr.addstr(row, 0, f"  Expected:       {self.tone_freq_mhz:.3f} MHz")
                row += 1
                stdscr.addstr(row, 0, f"  Found:          {metrics['tone_freq_mhz']:.3f} MHz")
                row += 1
                stdscr.addstr(row, 0, f"  Frequency Err:  {metrics['freq_error_khz']:.1f} kHz")
                row += 1
                stdscr.addstr(row, 0, f"  Tone Power:     {metrics['tone_power_db']:.1f} dB")
                row += 2
                
                stdscr.addstr(row, 0, "Noise & SNR:")
                row += 1
                stdscr.addstr(row, 0, f"  Noise Floor:    {metrics['noise_floor_db']:.1f} dB")
                row += 1
                stdscr.addstr(row, 0, f"  SNR:            {metrics['snr_db']:.1f} dB")
                row += 2
                
                stdscr.addstr(row, 0, "Array Alignment (Phase):")
                row += 1
                stdscr.addstr(row, 0, f"  Phase Error:    {metrics['phase_deg']:.2f}°")
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
                if (now - last_update) >= (self.update_interval_ms / 1000.0):
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

    def setup_plot(self):
        """Setup matplotlib figure and axes for live plotting."""
        fig = plt.figure(figsize=(14, 9))
        gs = fig.add_gridspec(3, 2, hspace=0.35, wspace=0.3)

        self.fig = fig
        self.ax_waveform = fig.add_subplot(gs[0, :])
        self.ax_spectrum = fig.add_subplot(gs[1, :])
        self.ax_metrics = fig.add_subplot(gs[2, :])

        self.ax_metrics.axis("off")
        self.config_axes()

    def config_axes(self) -> None:
        """Configure axis labels and formatting."""
        self.ax_waveform.set_xlabel("Time (μs)")
        self.ax_waveform.set_ylabel("ADC Code" if self.plot_raw_codes else "Amplitude (V)")
        self.ax_waveform.set_title(
            f"Waveform Snapshot (last {self.waveform_cycles:.1f} cycles, interp x{self.interp_factor})"
        )
        self.ax_waveform.grid(True, alpha=0.3)

        self.ax_spectrum.set_xlabel("Frequency (MHz)")
        self.ax_spectrum.set_ylabel("Power (dB)")
        self.ax_spectrum.set_title("FFT Spectrum")
        self.ax_spectrum.grid(True, alpha=0.3)

    def update_plot(self) -> None:
        """Update plot with latest metrics."""
        now = time.time()
        if (now - self.last_update_time) < (self.update_interval_ms / 1000.0):
            return

        metrics = self.compute_metrics()
        if "error" in metrics:
            return

        self.last_update_time = now

        # Waveform plot
        self.ax_waveform.clear()
        if self.iq_interleaved:
            i_t = np.array(list(self.i_time_us))
            i_y = np.array(list(self.i_codes if self.plot_raw_codes else self.i_samples))
            q_t = np.array(list(self.q_time_us))
            q_y = np.array(list(self.q_codes if self.plot_raw_codes else self.q_samples))
            wave_t_i, wave_y_i = self._select_waveform_slice(i_t, i_y)
            wave_t_q, wave_y_q = self._select_waveform_slice(q_t, q_y)
            wave_t_i, wave_y_i = self._render_waveform(wave_t_i, wave_y_i, metrics["tone_freq_mhz"] * 1e6)
            wave_t_q, wave_y_q = self._render_waveform(wave_t_q, wave_y_q, metrics["tone_freq_mhz"] * 1e6)
            self.ax_waveform.plot(wave_t_i, wave_y_i, "b-", linewidth=0.9, alpha=0.9, label="I")
            self.ax_waveform.plot(wave_t_q, wave_y_q, "g-", linewidth=0.9, alpha=0.9, label="Q")
            self.ax_waveform.legend()
        else:
            time_arr = np.array(list(self.time_us))
            y_arr = np.array(list(self.codes if self.plot_raw_codes else self.samples))
            wave_t, wave_y = self._select_waveform_slice(time_arr, y_arr)
            wave_t, wave_y = self._render_waveform(wave_t, wave_y, metrics["tone_freq_mhz"] * 1e6)
            self.ax_waveform.plot(wave_t, wave_y, "b-", linewidth=0.8, alpha=0.9)
        self.ax_waveform.set_xlabel("Time (μs)")
        self.ax_waveform.set_ylabel("ADC Code" if self.plot_raw_codes else "Amplitude (V)")
        self.ax_waveform.set_title(
            f"Waveform Snapshot (last {self.waveform_cycles:.1f} cycles, interp x{self.interp_factor})"
        )
        self.ax_waveform.grid(True, alpha=0.3)

        # Spectrum plot
        self.ax_spectrum.clear()
        freqs = metrics["fft_freqs"]
        power_db = metrics["fft_power_db"]

        if self.plot_freq_range_mhz:
            f_min, f_max = self.plot_freq_range_mhz
            mask = (freqs >= f_min) & (freqs <= f_max)
            freqs_plot = freqs[mask]
            power_plot = power_db[mask]
        else:
            freqs_plot = freqs
            power_plot = power_db

        self.ax_spectrum.plot(freqs_plot, power_plot, "b-", linewidth=1)
        self.ax_spectrum.axvline(
            self.tone_freq_mhz, color="r", linestyle="--", alpha=0.7, label=f"Tone: {self.tone_freq_mhz:.2f} MHz"
        )
        self.ax_spectrum.set_xlabel("Frequency (MHz)")
        self.ax_spectrum.set_ylabel("Power (dB)")
        self.ax_spectrum.set_title("FFT Spectrum")
        self.ax_spectrum.grid(True, alpha=0.3)
        self.ax_spectrum.legend()

        # Metrics text
        self.ax_metrics.clear()
        self.ax_metrics.axis("off")
        metrics_text = (
            f"RMS: {metrics['rms_v']:.6f} Vrms ({metrics['rms_dbm']:.1f} dBm) | "
            f"Peak(+): {metrics['peak_pos']:.6f} V | "
            f"Peak(-): {metrics['peak_neg']:.6f} V | P-P: {metrics['peak_to_peak']:.6f} V\n"
            f"Tone: {metrics['tone_freq_mhz']:.3f} MHz (error: {metrics['freq_error_khz']:.1f} kHz) | "
            f"Power: {metrics['tone_power_db']:.1f} dB | "
            f"SNR: {metrics['snr_db']:.1f} dB\n"
            f"Code P/T sampled: {metrics['sampled_peak_code']:.1f}/{metrics['sampled_trough_code']:.1f} | "
            f"recon: {metrics['recon_peak_code']:.1f}/{metrics['recon_trough_code']:.1f}\n"
            f"Phase Error: {metrics['phase_deg']:.2f}° | "
            f"Samples: {self.total_samples_read:,} | "
            f"Window: {min(len(self.i_samples), len(self.q_samples)) if self.iq_interleaved else len(self.samples)} samples"
        )
        if self.iq_interleaved and metrics["q_peak_to_peak"] is not None:
            metrics_text += f"\nQ P-P: {metrics['q_peak_to_peak']:.6f} V"
        self.ax_metrics.text(
            0.5, 0.5, metrics_text, ha="center", va="center", fontsize=10, family="monospace"
        )

        self.fig.canvas.draw_idle()

    def run_plot_mode(self, duration_sec: Optional[float] = None) -> None:
        """Run analyzer with live matplotlib plot (requires DISPLAY or --plot-file)."""
        if not MATPLOTLIB_AVAILABLE:
            print("matplotlib not available, falling back to text mode")
            self.run_text_mode(duration_sec)
            return

        backend = ""
        try:
            backend = matplotlib.get_backend().lower()
        except Exception:
            backend = ""

        if (not self.has_display or "agg" in backend) and not self.plot_file and not self.force_live_plot:
            print("No interactive display/backend available for live plot; using terminal UI.")
            print("Use --plot-file <name>.png to save a snapshot on headless systems.")
            self.run_text_mode(duration_sec)
            return

        # If saving to file, collect data then save snapshot
        if self.plot_file:
            self.run_collect_and_save_plot(duration_sec)
            return

        self.setup_plot()
        print("Starting live plot (close window or Ctrl+C to stop)\n")

        start = time.time()

        def animate(frame):
            new_count = self.read_udp_chunk()
            if new_count > 0 and self.csv_file:
                self.csv_file.flush()
            self.update_plot()
            if duration_sec and (time.time() - start) >= duration_sec:
                plt.close(self.fig)

        ani = FuncAnimation(self.fig, animate, interval=100, cache_frame_data=False)

        try:
            plt.show()
        except KeyboardInterrupt:
            pass
        except Exception as e:
            print(f"Plot error: {e}")
            print("Falling back to text mode...")
            self.run_text_mode(duration_sec)
        finally:
            if self.csv_file:
                self.csv_file.close()

    def run_collect_and_save_plot(self, duration_sec: Optional[float] = None) -> None:
        """Collect data and save plot snapshot to file."""
        if not MATPLOTLIB_AVAILABLE:
            print("ERROR: matplotlib not available for plot generation")
            return
        
        print(f"Collecting data for {duration_sec or 'infinite'} seconds, will save to {self.plot_file}...")
        
        start = time.time()
        
        try:
            while True:
                new_count = self.read_udp_chunk()
                if new_count > 0 and self.csv_file:
                    self.csv_file.flush()

                now = time.time()
                if duration_sec and (now - start) >= duration_sec:
                    break

                time.sleep(0.001)

        except KeyboardInterrupt:
            print("Collection stopped by user")
        finally:
            if self.csv_file:
                self.csv_file.close()

        # Now save plot
        print(f"Saving plot to {self.plot_file}...")
        try:
            metrics = self.compute_metrics()
            if "error" not in metrics:
                self._save_plot_snapshot(metrics)
                print(f"Plot saved to {self.plot_file}")
            else:
                print(f"Cannot save plot: {metrics['error']}")
        except Exception as e:
            print(f"Error saving plot: {e}")

    def _save_plot_snapshot(self, metrics: dict) -> None:
        """Save current metrics as a plot snapshot."""
        if plt is None:
            raise RuntimeError("matplotlib not available for plot generation")
        
        fig = plt.figure(figsize=(14, 9))
        gs = fig.add_gridspec(3, 2, hspace=0.35, wspace=0.3)

        ax_waveform = fig.add_subplot(gs[0, :])
        ax_spectrum = fig.add_subplot(gs[1, :])
        ax_metrics = fig.add_subplot(gs[2, :])
        ax_metrics.axis("off")

        # Waveform
        if self.iq_interleaved:
            i_t = np.array(list(self.i_time_us))
            i_y = np.array(list(self.i_codes if self.plot_raw_codes else self.i_samples))
            q_t = np.array(list(self.q_time_us))
            q_y = np.array(list(self.q_codes if self.plot_raw_codes else self.q_samples))
            wave_t_i, wave_y_i = self._select_waveform_slice(i_t, i_y)
            wave_t_q, wave_y_q = self._select_waveform_slice(q_t, q_y)
            wave_t_i, wave_y_i = self._render_waveform(wave_t_i, wave_y_i, metrics["tone_freq_mhz"] * 1e6)
            wave_t_q, wave_y_q = self._render_waveform(wave_t_q, wave_y_q, metrics["tone_freq_mhz"] * 1e6)
            ax_waveform.plot(wave_t_i, wave_y_i, "b-", linewidth=0.9, alpha=0.9, label="I")
            ax_waveform.plot(wave_t_q, wave_y_q, "g-", linewidth=0.9, alpha=0.9, label="Q")
            ax_waveform.legend()
        else:
            time_arr = np.array(list(self.time_us))
            y_arr = np.array(list(self.codes if self.plot_raw_codes else self.samples))
            wave_t, wave_y = self._select_waveform_slice(time_arr, y_arr)
            wave_t, wave_y = self._render_waveform(wave_t, wave_y, metrics["tone_freq_mhz"] * 1e6)
            ax_waveform.plot(wave_t, wave_y, "b-", linewidth=0.8, alpha=0.9)
        ax_waveform.set_xlabel("Time (μs)")
        ax_waveform.set_ylabel("ADC Code" if self.plot_raw_codes else "Amplitude (V)")
        ax_waveform.set_title(
            f"Waveform Snapshot (last {self.waveform_cycles:.1f} cycles, interp x{self.interp_factor})"
        )
        ax_waveform.grid(True, alpha=0.3)

        # Spectrum
        freqs = metrics["fft_freqs"]
        power_db = metrics["fft_power_db"]

        if self.plot_freq_range_mhz:
            f_min, f_max = self.plot_freq_range_mhz
            mask = (freqs >= f_min) & (freqs <= f_max)
            freqs_plot = freqs[mask]
            power_plot = power_db[mask]
        else:
            freqs_plot = freqs
            power_plot = power_db

        ax_spectrum.plot(freqs_plot, power_plot, "b-", linewidth=1)
        ax_spectrum.axvline(
            self.tone_freq_mhz, color="r", linestyle="--", alpha=0.7, label=f"Tone: {self.tone_freq_mhz:.2f} MHz"
        )
        ax_spectrum.set_xlabel("Frequency (MHz)")
        ax_spectrum.set_ylabel("Power (dB)")
        ax_spectrum.set_title("FFT Spectrum")
        ax_spectrum.grid(True, alpha=0.3)
        ax_spectrum.legend()

        # Metrics text
        metrics_text = (
            f"RMS: {metrics['rms_v']:.6f} Vrms ({metrics['rms_dbm']:.1f} dBm) | "
            f"Peak(+): {metrics['peak_pos']:.6f} V | "
            f"Peak(-): {metrics['peak_neg']:.6f} V | "
            f"P-P: {metrics['peak_to_peak']:.6f} V\n"
            f"Tone: {metrics['tone_freq_mhz']:.3f} MHz (err: {metrics['freq_error_khz']:.1f} kHz) | "
            f"Power: {metrics['tone_power_db']:.1f} dB | "
            f"SNR: {metrics['snr_db']:.1f} dB | "
            f"Phase: {metrics['phase_deg']:.2f}°\n"
            f"Code P/T sampled: {metrics['sampled_peak_code']:.1f}/{metrics['sampled_trough_code']:.1f} | "
            f"recon: {metrics['recon_peak_code']:.1f}/{metrics['recon_trough_code']:.1f}\n"
            f"Samples: {self.total_samples_read:,} | Packets: {self.packets_received} | Bytes: {self.bytes_received:,}"
        )
        if self.iq_interleaved and metrics["q_peak_to_peak"] is not None:
            metrics_text += f"\nQ P-P: {metrics['q_peak_to_peak']:.6f} V"
        ax_metrics.text(
            0.5, 0.5, metrics_text, ha="center", va="center", fontsize=10, family="monospace"
        )

        fig.savefig(self.plot_file, dpi=100, bbox_inches="tight")
        plt.close(fig)

    def _select_waveform_slice(self, time_arr: np.ndarray, samples_arr: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Return only the last N tone cycles for display so waveform remains readable."""
        if len(samples_arr) == 0:
            return time_arr, samples_arr

        tone_hz = self.tone_freq_mhz * 1e6
        if tone_hz <= 0:
            return time_arr, samples_arr

        n_samples = int(max(8, round(self.waveform_cycles * self.channel_sample_rate_hz / tone_hz)))
        n_samples = min(n_samples, len(samples_arr))
        start = len(samples_arr) - n_samples

        t_sel = time_arr[start:].copy()
        y_sel = samples_arr[start:].copy()

        # Re-base time to start at zero for a compact cycle snapshot.
        if len(t_sel) > 0:
            t_sel -= t_sel[0]
        return t_sel, y_sel

    def _interpolate_waveform(self, t: np.ndarray, y: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Display-only interpolation to smooth plots; metrics/FFT remain on original samples."""
        if self.interp_factor <= 1 or len(t) < 2:
            return t, y

        n_out = (len(t) - 1) * self.interp_factor + 1
        t_new = np.linspace(t[0], t[-1], n_out)
        y_new = np.interp(t_new, t, y)
        return t_new, y_new

    def _render_waveform(self, t: np.ndarray, y: np.ndarray, freq_hz: float) -> Tuple[np.ndarray, np.ndarray]:
        """Render waveform according to selected mode: raw, interp, or recon."""
        if self.waveform_render == "raw":
            return t, y
        if self.waveform_render == "interp":
            return self._interpolate_waveform(t, y)
        return self._reconstruct_waveform(t, y, freq_hz)

    def _reconstruct_waveform(self, t_us: np.ndarray, y: np.ndarray, freq_hz: float) -> Tuple[np.ndarray, np.ndarray]:
        """Display-only sinusoid reconstruction from sparse/quantized points."""
        if len(t_us) < 8 or freq_hz <= 0:
            return self._interpolate_waveform(t_us, y)

        t = t_us * 1e-6
        w = 2.0 * np.pi * freq_hz
        X = np.column_stack((np.sin(w * t), np.cos(w * t), np.ones_like(t)))
        try:
            coeff, _, _, _ = np.linalg.lstsq(X, y.astype(float), rcond=None)
        except Exception:
            return self._interpolate_waveform(t_us, y)

        n_out = max((len(t_us) - 1) * self.interp_factor + 1, 200)
        t_new = np.linspace(t[0], t[-1], n_out)
        y_new = (
            coeff[0] * np.sin(w * t_new)
            + coeff[1] * np.cos(w * t_new)
            + coeff[2]
        )
        return t_new * 1e6, y_new

    def run(self, duration_sec: Optional[float] = None) -> None:
        """Main run loop."""
        if self.plot_file:
            # Collect data and save snapshot
            self.run_collect_and_save_plot(duration_sec)
        elif self.enable_plot:
            # Try live plot with matplotlib
            self.run_plot_mode(duration_sec)
        else:
            # Terminal UI with curses
            self.run_text_mode(duration_sec)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Real-time beamforming analyzer for ADC UDP stream"
    )
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
        help="Expected tone frequency in MHz (e.g., 10.0)",
    )
    parser.add_argument(
        "--sample-rate-msps",
        type=float,
        default=125.0,
        help="ADC clock/sample rate entering RTL in MSPS",
    )
    parser.add_argument(
        "--rtl-decim",
        type=int,
        default=4,
        help="RTL decimation factor before packetization (current KC705 RTL uses 4)",
    )
    parser.add_argument(
        "--window-ms",
        type=float,
        default=100.0,
        help="Analysis window in milliseconds (FFT length)",
    )
    parser.add_argument(
        "--update-interval-ms",
        type=float,
        default=1000.0,
        help="Metric update interval in milliseconds",
    )
    parser.add_argument(
        "--vref",
        type=float,
        default=1.0,
        help="ADC VREF in volts",
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
        "--plot-freq-range-mhz",
        type=str,
        default="",
        help="Frequency range for spectrum plot, e.g. '0 30' for 0-30 MHz (empty = full)",
    )
    parser.add_argument(
        "--wave-cycles",
        type=float,
        default=6.0,
        help="Number of tone cycles to show in waveform plot/snapshot",
    )
    parser.add_argument(
        "--iq-interleaved",
        action="store_true",
        help="Interpret samples as interleaved I,Q,I,Q and plot both channels",
    )
    parser.add_argument(
        "--iq-swap",
        action="store_true",
        help="Swap IQ assignment to Q,I if channels appear reversed",
    )
    parser.add_argument(
        "--plot-raw-codes",
        dest="plot_raw_codes",
        action="store_true",
        help="Plot raw received ADC codes in waveform panel (default)",
    )
    parser.add_argument(
        "--plot-volts",
        dest="plot_raw_codes",
        action="store_false",
        help="Plot converted volts in waveform panel",
    )
    parser.add_argument(
        "--interp-factor",
        type=int,
        default=4,
        help="Display-only waveform interpolation factor (1 disables)",
    )
    parser.add_argument(
        "--waveform-render",
        choices=["raw", "interp", "recon"],
        default="recon",
        help="Waveform rendering mode: raw points, linear interpolation, or sine reconstruction",
    )
    parser.add_argument(
        "--byte-phase",
        choices=["auto", "0", "1"],
        default="auto",
        help="Sample byte phase: auto detect or force 0/1",
    )
    parser.add_argument(
        "--force-live-plot",
        action="store_true",
        help="Attempt live plot even when DISPLAY detection fails (useful in some remote desktop sessions)",
    )
    parser.add_argument(
        "--no-plot",
        action="store_true",
        help="Disable scrolling terminal UI (use if curses unavailable)",
    )
    parser.add_argument(
        "--plot-file",
        default="",
        help="Save plot snapshot to file instead of live plot (e.g. plot.png)",
    )
    parser.add_argument(
        "--csv-output",
        default="",
        help="Optional CSV file for recording while analyzing (empty = no recording)",
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
    parser.set_defaults(plot_raw_codes=True)
    args = parser.parse_args()

    plot_range = None
    if args.plot_freq_range_mhz.strip():
        parts = args.plot_freq_range_mhz.split()
        if len(parts) == 2:
            try:
                plot_range = (float(parts[0]), float(parts[1]))
            except ValueError:
                print("Invalid --plot-freq-range-mhz format")
                return 1

    csv_output_path = None
    if args.csv_output.strip():
        csv_output_path = pathlib.Path(args.csv_output)

    plot_file_path = None
    if args.plot_file.strip():
        plot_file_path = pathlib.Path(args.plot_file)

    analyzer = BeamformAnalyzer(
        bind_ip=args.bind_ip,
        bind_port=args.bind_port,
        tone_freq_mhz=args.tone_freq_mhz,
        sample_rate_msps=args.sample_rate_msps,
        rtl_decim=args.rtl_decim,
        window_ms=args.window_ms,
        update_interval_ms=args.update_interval_ms,
        vref=args.vref,
        cal_vpp=args.cal_vpp,
        cal_peak_code=args.cal_peak_code,
        cal_trough_code=args.cal_trough_code,
        plot_freq_range_mhz=plot_range,
        enable_plot=not args.no_plot,
        waveform_cycles=args.wave_cycles,
        iq_interleaved=args.iq_interleaved,
        iq_swap=args.iq_swap,
        byte_phase=args.byte_phase,
        plot_raw_codes=args.plot_raw_codes,
        interp_factor=args.interp_factor,
        waveform_render=args.waveform_render,
        force_live_plot=args.force_live_plot,
        plot_file=plot_file_path,
        csv_output=csv_output_path,
        recv_size=args.recv_size,
        timeout=args.timeout,
    )

    duration = args.duration_sec if args.duration_sec > 0 else None
    analyzer.run(duration)

    return 0


if __name__ == "__main__":
    sys.exit(main())
