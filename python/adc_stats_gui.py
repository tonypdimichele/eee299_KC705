#!/usr/bin/env python3
"""Live GUI for FPGA ADC stats: I and Q channel V^2rms on separate charts.

Reuses ADCStatsAnalyzer for UDP receive/decode/batching; this script only
replaces the curses terminal UI with Tkinter strip charts. Only one process can
receive the UDP stream, so run this *instead of* adc_stats_analyzer.py.

Usage:
    python3 python/adc_stats_gui.py --bind-port 40000 --fpga-ip 192.168.1.128
    python3 python/adc_stats_gui.py --csv-output adc_stats.csv
"""

import argparse
import pathlib
import queue
import sys
import threading
import time
import tkinter as tk
from collections import deque

from adc_stats_analyzer import ADCStatsAnalyzer

BG = "#1e1e1e"
GRID = "#3a3a3a"
TEXT = "#d4d4d4"
I_COLOR = "#7bd88f"
Q_COLOR = "#6cb6ff"


def _dim(color, frac=0.45):
    """Blend a #rrggbb color toward the background (for min/max envelope)."""
    c = [int(color[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(BG[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{int(bb + (cc - bb) * frac):02x}" for cc, bb in zip(c, b))


class BucketSeries:
    """Fixed-memory time series: every sample lands in a time bucket that keeps
    min / max / sum / count, so no excursion is lost however fast data arrives."""

    def __init__(self, history_sec, n_buckets=6000):
        self.dt = max(1e-3, history_sec / n_buckets)
        self.buckets = deque(maxlen=n_buckets + 10)  # [idx, min, max, sum, count]

    def add(self, t, y):
        idx = int(t / self.dt)
        if self.buckets and self.buckets[-1][0] == idx:
            b = self.buckets[-1]
            if y < b[1]:
                b[1] = y
            if y > b[2]:
                b[2] = y
            b[3] += y
            b[4] += 1
        else:
            self.buckets.append([idx, y, y, y, 1])

    def window(self, t_min):
        i_min = int(t_min / self.dt)
        for b in self.buckets:
            if b[0] >= i_min:
                yield (b[0] + 0.5) * self.dt, b[1], b[2], b[3], b[4]


class StripChart(tk.Canvas):
    """Minimal time-series plot on a Tk canvas (no external deps).

    Each pixel column draws the min..max envelope of all samples in it (dim)
    plus a line through the per-column mean (bright).
    """

    PAD_L, PAD_R, PAD_T, PAD_B = 70, 15, 25, 25

    def __init__(self, master, title, y_label, y_range=None, y_ticks=None, fmt="{:.3g}", **kw):
        super().__init__(master, bg=BG, highlightthickness=0, **kw)
        self.title = title
        self.y_label = y_label
        self.fixed_range = y_range
        self.y_ticks = y_ticks
        self.fmt = fmt
        self.series = []  # (label, color, BucketSeries)

    def add_series(self, label, color, data):
        self.series.append((label, color, data))

    def redraw(self, t_now, span_sec):
        self.delete("all")
        w, h = self.winfo_width(), self.winfo_height()
        x0, x1 = self.PAD_L, w - self.PAD_R
        y0, y1 = self.PAD_T, h - self.PAD_B
        if x1 <= x0 or y1 <= y0:
            return
        t_min = t_now - span_sec

        # Aggregate buckets into pixel columns: col -> [min, max, sum, count]
        per_series = []
        for _, color, data in self.series:
            cols = {}
            for t, mn, mx, sm, n in data.window(t_min):
                col = int(x0 + (t - t_min) / span_sec * (x1 - x0))
                c = cols.get(col)
                if c is None:
                    cols[col] = [mn, mx, sm, n]
                else:
                    c[0] = min(c[0], mn)
                    c[1] = max(c[1], mx)
                    c[2] += sm
                    c[3] += n
            per_series.append((color, sorted(cols.items())))

        if self.fixed_range:
            lo, hi = self.fixed_range
        else:
            mins = [c[0] for _, cols in per_series for _, c in cols]
            maxs = [c[1] for _, cols in per_series for _, c in cols]
            if mins:
                lo, hi = min(mins), max(maxs)
                pad = 0.1 * (hi - lo) if hi > lo else (abs(hi) * 0.1 or 1e-6)
                lo, hi = lo - pad, hi + pad
            else:
                lo, hi = 0.0, 1.0

        def sx(t):
            return x0 + (t - t_min) / span_sec * (x1 - x0)

        def sy(y):
            return y1 - (min(max(y, lo), hi) - lo) / (hi - lo) * (y1 - y0)

        ticks = self.y_ticks or [lo + i * (hi - lo) / 4 for i in range(5)]
        for v in ticks:
            yy = sy(v)
            self.create_line(x0, yy, x1, yy, fill=GRID)
            self.create_text(x0 - 6, yy, text=self.fmt.format(v), anchor="e", fill=TEXT, font=("Consolas", 9))
        for s in range(0, int(span_sec) + 1, max(1, int(span_sec) // 6)):
            xx = sx(t_now - s)
            self.create_line(xx, y0, xx, y1, fill=GRID)
            self.create_text(xx, y1 + 12, text=f"-{s}s", fill=TEXT, font=("Consolas", 9))
        self.create_rectangle(x0, y0, x1, y1, outline=GRID)

        self.create_text(x0, 12, text=f"{self.title}  [{self.y_label}]", anchor="w",
                         fill=TEXT, font=("Segoe UI", 10, "bold"))
        lx = x1
        for label, color, _ in reversed(self.series):
            item = self.create_text(lx, 12, text=f"\u25cf {label} (band = min/max)", anchor="e",
                                    fill=color, font=("Segoe UI", 9))
            lx = self.bbox(item)[0] - 12

        for color, cols in per_series:
            env = _dim(color)
            pts = []
            for col, (mn, mx, sm, n) in cols:
                y_mn, y_mx = sy(mn), sy(mx)
                if y_mn - y_mx >= 1:
                    self.create_line(col, y_mn, col, y_mx, fill=env)
                pts.extend((col, sy(sm / n)))
            if len(pts) >= 4:
                self.create_line(*pts, fill=color, width=1.5)
            elif len(pts) == 2:
                self.create_oval(pts[0] - 2, pts[1] - 2, pts[0] + 2, pts[1] + 2, fill=color, outline=color)


class StatsGUI:
    def __init__(self, analyzer: ADCStatsAnalyzer, history_sec: float, refresh_ms: int):
        self.analyzer = analyzer
        self.history_sec = history_sec
        self.refresh_ms = refresh_ms
        self.reports = queue.Queue()
        self.stop_evt = threading.Event()

        self.i_v2rms = BucketSeries(history_sec)
        self.q_v2rms = BucketSeries(history_sec)
        self.t_start = time.time()

        self.root = tk.Tk()
        self.root.title("ADC Stats - I/Q V²rms")
        self.root.configure(bg=BG)
        self.root.geometry("1000x720")
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        top = tk.Frame(self.root, bg=BG)
        top.pack(fill="x", padx=10, pady=(10, 0))
        self.lbl_i = self._readout(top, "I V²rms", I_COLOR)
        self.lbl_q = self._readout(top, "Q V²rms", Q_COLOR)
        self.lbl_freq = self._readout(top, "Frequency", TEXT)

        self.status = tk.Label(self.root, bg=BG, fg="#888888", anchor="w", font=("Consolas", 9))
        self.status.pack(side="bottom", fill="x", padx=10, pady=(0, 6))

        self.i_chart = StripChart(self.root, "I channel V²rms", "V²", fmt="{:.4g}")
        self.i_chart.add_series("I", I_COLOR, self.i_v2rms)
        self.i_chart.pack(fill="both", expand=True, padx=10, pady=(10, 5))

        self.q_chart = StripChart(self.root, "Q channel V²rms", "V²", fmt="{:.4g}")
        self.q_chart.add_series("Q", Q_COLOR, self.q_v2rms)
        self.q_chart.pack(fill="both", expand=True, padx=10, pady=(5, 5))

        self.worker = threading.Thread(target=self._rx_loop, daemon=True)

    @staticmethod
    def _readout(parent, title, color):
        box = tk.Frame(parent, bg="#252526", padx=12, pady=6)
        box.pack(side="left", fill="x", expand=True, padx=4)
        tk.Label(box, text=title, bg="#252526", fg="#9a9a9a", font=("Segoe UI", 9)).pack(anchor="w")
        lbl = tk.Label(box, text="--", bg="#252526", fg=color, font=("Consolas", 20, "bold"))
        lbl.pack(anchor="w")
        return lbl

    def _hook_batches(self):
        """Wrap the analyzer's batch finalizer so every per-stat value (not just
        the 20-stat average) is forwarded to the GUI, and no report is skipped."""
        a = self.analyzer
        orig = a._finalize_batch_metrics
        last_t = [time.time()]

        def v2rms_list(pos_codes, neg_codes):
            out = []
            for pp, pn, f in zip(pos_codes, neg_codes, a.batch_freqs_mhz):
                vpp = a.code_to_volts(pp) - a.code_to_volts(pn)
                if a.vpp_cal_enabled and f > 0:
                    vpp *= a.vpp_cal_a + a.vpp_cal_b * f
                out.append(vpp * vpp / 8.0)
            return out

        def finalize():
            now = time.time()
            i_v2 = v2rms_list(a.batch_peak_pos_codes, a.batch_peak_neg_codes)
            q_v2 = v2rms_list(a.batch_q_peak_pos_codes, a.batch_q_peak_neg_codes)
            n = len(i_v2)
            # Spread this batch's stats evenly between previous batch and now.
            t0 = max(last_t[0], now - 1.0)
            times = [t0 + (now - t0) * (i + 1) / n for i in range(n)] if n else []
            last_t[0] = now
            orig()
            self.reports.put((times, i_v2, q_v2, dict(a.latest_metrics)))

        a._finalize_batch_metrics = finalize

    def _rx_loop(self):
        """Background UDP receive; batches are posted by the finalize hook."""
        a = self.analyzer
        while not self.stop_evt.is_set():
            try:
                n = a.read_udp_chunk()
            except OSError:
                break
            if n and a.csv_file:
                a.csv_file.flush()
            if n and a.rms_csv_file:
                a.rms_csv_file.flush()

    def _tick(self):
        latest = None
        while True:
            try:
                times, i_v2, q_v2, m = self.reports.get_nowait()
            except queue.Empty:
                break
            for t, iv, qv in zip(times, i_v2, q_v2):
                self.i_v2rms.add(t, iv)
                self.q_v2rms.add(t, qv)
            latest = m

        if latest:
            self.lbl_i.config(text=f"{latest['v2rms_v2']:.4g} V²")
            self.lbl_q.config(text=f"{latest['q_v2rms_v2']:.4g} V²")
            self.lbl_freq.config(text=f"{latest['freq_mhz']:.4f} MHz")

        a = self.analyzer
        self.status.config(
            text=f"Stats: {a.total_stats_read:,}  Reports: {a.reports_generated}  "
                 f"Packets: {a.packets_received:,}  Invalid: {a.invalid_freq_stats}  "
                 f"Batch: {len(a.batch_peak_pos_codes)}/{a.batch_size}"
        )

        now = time.time()
        span = min(self.history_sec, max(5.0, now - self.t_start))
        self.i_chart.redraw(now, span)
        self.q_chart.redraw(now, span)

        if not self.stop_evt.is_set():
            self.root.after(self.refresh_ms, self._tick)

    def run(self):
        self._hook_batches()
        self.worker.start()
        self.root.after(self.refresh_ms, self._tick)
        try:
            self.root.mainloop()
        except KeyboardInterrupt:
            pass
        self.close()

    def close(self):
        if self.stop_evt.is_set():
            return
        self.stop_evt.set()
        self.worker.join(timeout=2 * self.analyzer.timeout + 0.5)
        self.analyzer.sock.close()
        for f in (self.analyzer.csv_file, self.analyzer.rms_csv_file):
            if f:
                f.close()
        self.root.destroy()


def main() -> int:
    p = argparse.ArgumentParser(description="Live I/Q V^2rms GUI for FPGA ADC stats")
    p.add_argument("--bind-ip", default="0.0.0.0")
    p.add_argument("--bind-port", type=int, default=40000)
    p.add_argument("--fpga-ip", default="192.168.1.128")
    p.add_argument("--prime-port", type=int, default=20000)
    p.add_argument("--no-prime", action="store_true")
    p.add_argument("--sample-rate-msps", type=float, default=125.0)
    p.add_argument("--phase-reference-deg", type=float, default=0.0)
    p.add_argument("--phase-ema-alpha", type=float, default=1.0)
    p.add_argument("--phase-max-step-deg", type=float, default=180.0)
    p.add_argument("--relock-rejects", type=int, default=20)
    p.add_argument("--resolve-pi", action="store_true")
    p.add_argument("--no-vpp-cal", action="store_true")
    p.add_argument("--vpp-cal-a", type=float, default=1.0377)
    p.add_argument("--vpp-cal-b", type=float, default=0.00409)
    p.add_argument("--tx-iq-phase-deg", type=float, default=90.0,
                   help="Transmitted Q-vs-I phase subtracted for the (Qrx-Qtx)-(Irx-Itx) CSV columns")
    p.add_argument("--csv-output", default="", help="Optional CSV recording (same format as analyzer)")
    p.add_argument("--history-sec", type=float, default=60.0, help="Visible time window in seconds")
    p.add_argument("--refresh-ms", type=int, default=200, help="GUI redraw interval in ms")
    args = p.parse_args()

    analyzer = ADCStatsAnalyzer(
        bind_ip=args.bind_ip,
        bind_port=args.bind_port,
        phase_reference_deg=args.phase_reference_deg,
        fpga_ip=args.fpga_ip,
        prime_port=args.prime_port,
        no_prime=args.no_prime,
        sample_rate_msps=args.sample_rate_msps,
        csv_output=pathlib.Path(args.csv_output) if args.csv_output.strip() else None,
        timeout=0.2,
        resolve_pi_ambiguity=args.resolve_pi,
        phase_ema_alpha=args.phase_ema_alpha,
        phase_max_step_deg=args.phase_max_step_deg,
        phase_relock_rejects=args.relock_rejects,
        vpp_cal_enabled=not args.no_vpp_cal,
        vpp_cal_a=args.vpp_cal_a,
        vpp_cal_b=args.vpp_cal_b,
        tx_iq_phase_deg=args.tx_iq_phase_deg,
    )

    StatsGUI(analyzer, args.history_sec, args.refresh_ms).run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
