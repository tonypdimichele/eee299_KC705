#!/usr/bin/env python3
"""Generate PDF document: Block vs Sliding RMS -- Theory, Implementation, and Experiment."""

from fpdf import FPDF
import os
import sys

class RMSDoc(FPDF):
    def header(self):
        self.set_font("Helvetica", "B", 10)
        self.cell(0, 6, "Block vs Sliding RMS on FPGA -- Theory & Implementation", align="C")
        self.ln(8)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.cell(0, 10, f"Page {self.page_no()}/{{nb}}", align="C")

    def section_title(self, title):
        self.set_font("Helvetica", "B", 13)
        self.set_fill_color(230, 230, 230)
        self.cell(0, 9, f"  {title}", fill=True, new_x="LMARGIN", new_y="NEXT")
        self.ln(3)

    def sub_title(self, title):
        self.set_font("Helvetica", "B", 11)
        self.cell(0, 7, title, new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def body_text(self, text):
        self.set_font("Helvetica", "", 10)
        self.multi_cell(0, 5.5, text)
        self.ln(1)

    def code_block(self, code):
        self.set_font("Courier", "", 8.5)
        self.set_fill_color(245, 245, 245)
        for line in code.split("\n"):
            self.cell(0, 4.5, f"  {line}", fill=True, new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def equation(self, text):
        self.set_font("Courier", "B", 10)
        self.cell(0, 6, f"    {text}", new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def bullet(self, text):
        self.set_font("Helvetica", "", 10)
        x = self.get_x()
        self.cell(6, 5.5, "-")
        self.multi_cell(0, 5.5, text)


def build_pdf(output_path):
    pdf = RMSDoc(orientation="P", unit="mm", format="A4")
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()

    # --------------------------------------------------------------
    # Title
    # --------------------------------------------------------------
    pdf.set_font("Helvetica", "B", 18)
    pdf.cell(0, 12, "Fixed-Point RMS Estimation on FPGA:", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "B", 14)
    pdf.cell(0, 10, "Block vs Sliding Window Approaches", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "I", 10)
    pdf.cell(0, 7, "EEE299 -- KC705 Platform", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(8)

    # --------------------------------------------------------------
    # 1. Introduction
    # --------------------------------------------------------------
    pdf.section_title("1. Introduction")
    pdf.body_text(
        "Root-mean-square (RMS) voltage is the standard measure of AC signal power. "
        "In digital systems the RMS value must be estimated from discrete, quantized "
        "samples using fixed-point arithmetic. Two common estimation architectures are:"
    )
    pdf.bullet("Block RMS -- collect N samples, compute the mean of their squares, report once per block.")
    pdf.ln(1)
    pdf.bullet("Sliding RMS -- maintain a running sum that updates every sample by adding the newest "
               "sample squared and subtracting the oldest, producing a continuous output stream.")
    pdf.ln(3)
    pdf.body_text(
        "While both converge to the same ideal value for stationary signals, their behavior "
        "diverges under real-world constraints: finite word-length arithmetic, quantization noise, "
        "accumulator saturation, and recursive numerical drift. This document describes the theory "
        "behind each method, how they are implemented in the project's Python analyzer, and the "
        "experimental procedure used to compare them."
    )

    # --------------------------------------------------------------
    # 2. Theory -- Block RMS
    # --------------------------------------------------------------
    pdf.section_title("2. Block RMS -- Theory")

    pdf.sub_title("2.1 Mathematical Definition")
    pdf.body_text("For a block of N samples x[0], x[1], ..., x[N-1]:")
    pdf.equation("V_rms_block = sqrt( (1/N) * SUM(n=0..N-1) x[n]^2 )")
    pdf.body_text(
        "In practice we often keep the squared form (V^2_rms) to avoid the square-root, "
        "which is expensive in hardware:"
    )
    pdf.equation("V^2_rms_block = (1/N) * SUM(n=0..N-1) x[n]^2")

    pdf.sub_title("2.2 FPGA Pipeline View")
    pdf.equation("x[n]  -->  x[n]^2  -->  accumulator  -->  divide by N  -->  V^2_rms")
    pdf.body_text(
        "At the end of N samples the accumulator holds the full sum. Division by N (a "
        "right-shift when N is a power of two) produces the final result. The accumulator "
        "is then reset to zero for the next block."
    )

    pdf.sub_title("2.3 Properties")
    pdf.bullet("Numerically stable: accumulator is reset every block, so rounding errors do not propagate.")
    pdf.ln(1)
    pdf.bullet("No long-term drift: each block is independent.")
    pdf.ln(1)
    pdf.bullet("High latency: must wait N samples before producing an output.")
    pdf.ln(1)
    pdf.bullet("Discontinuous output: one value per block, with no updates in between.")
    pdf.ln(3)

    pdf.sub_title("2.4 Relationship to Peak-to-Peak Voltage")
    pdf.body_text(
        "For a pure sinusoid with peak-to-peak voltage V_pp, the amplitude is A = V_pp / 2 "
        "and the RMS value is:"
    )
    pdf.equation("V_rms = A / sqrt(2) = V_pp / (2 * sqrt(2))")
    pdf.body_text("Therefore:")
    pdf.equation("V^2_rms = V_pp^2 / 8")
    pdf.body_text(
        "This identity allows us to derive V^2_rms from the FPGA's existing peak-positive "
        "and peak-negative measurements without needing sample-level data on the host."
    )

    # --------------------------------------------------------------
    # 3. Theory -- Sliding RMS
    # --------------------------------------------------------------
    pdf.section_title("3. Sliding RMS -- Theory")

    pdf.sub_title("3.1 Mathematical Definition")
    pdf.body_text(
        "Instead of resetting the accumulator every N samples, the sliding approach "
        "reuses the previous sum by subtracting the contribution of the oldest sample "
        "and adding the newest:"
    )
    pdf.equation("S[n] = S[n-1] + x[n]^2 - x[n-N]^2")
    pdf.equation("V^2_rms_sliding[n] = S[n] / N")
    pdf.body_text(
        "This produces a new RMS estimate at every sample clock, not just once per block."
    )

    pdf.sub_title("3.2 FPGA Implementation Considerations")
    pdf.body_text(
        "The sliding approach requires a circular buffer (typically BRAM) to store the last "
        "N squared samples so x[n-N]^2 is available for subtraction. The running sum is "
        "maintained in a single accumulator register."
    )
    pdf.equation("x[n]^2 --> [+] --> accumulator --> / N --> V^2_rms[n]")
    pdf.equation("              ^                             ")
    pdf.equation("              |--- subtract x[n-N]^2 <-- circular buffer")

    pdf.sub_title("3.3 Properties")
    pdf.bullet("Continuous output: produces a new V^2_rms value every sample clock.")
    pdf.ln(1)
    pdf.bullet("Low latency: output updates immediately when a new sample arrives.")
    pdf.ln(1)
    pdf.bullet("Efficient: only one addition and one subtraction per sample (no full re-sum).")
    pdf.ln(1)
    pdf.bullet("Sensitive to fixed-point precision: the subtract operation can accumulate "
               "rounding error over time because the accumulator is never reset.")
    pdf.ln(1)
    pdf.bullet("Drift risk: small rounding errors in the add/subtract cycle compound over "
               "millions of samples, causing the output to slowly deviate from the true value.")
    pdf.ln(1)
    pdf.bullet("Accumulator saturation: the running sum must be wide enough to hold "
               "N * max(x^2) without overflow.")
    pdf.ln(3)

    pdf.sub_title("3.4 Comparison Summary")
    # Table
    pdf.set_font("Helvetica", "B", 10)
    col_w = [50, 45, 45]
    headers = ["Property", "Block RMS", "Sliding RMS"]
    for i, h in enumerate(headers):
        pdf.cell(col_w[i], 7, h, border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 9.5)
    rows = [
        ("Latency", "High (N samples)", "Low (1 sample)"),
        ("Output cadence", "1 per block", "1 per sample"),
        ("Resource use", "Moderate", "Low + BRAM"),
        ("Numerical drift", "None", "Possible"),
        ("Fixed-pt sensitivity", "Lower", "Higher"),
        ("Accumulator reset", "Every block", "Never"),
    ]
    for r in rows:
        for i, val in enumerate(r):
            pdf.cell(col_w[i], 6, val, border=1)
        pdf.ln()
    pdf.ln(4)

    # --------------------------------------------------------------
    # 4. Implementation in Python
    # --------------------------------------------------------------
    pdf.section_title("4. Implementation in adc_stats_analyzer.py")

    pdf.sub_title("4.1 Overview")
    pdf.body_text(
        "The analyzer receives per-stat packets from the FPGA via UDP. Each stat packet "
        "contains peak-positive and peak-negative ADC codes (12-bit), from which V_pp is "
        "computed in volts. V^2_rms is derived as V_pp^2 / 8 for each stat. Both block "
        "and sliding estimators process these per-stat V^2_rms values."
    )

    pdf.sub_title("4.2 Block RMS Implementation")
    pdf.body_text(
        "Each incoming stat's V^2_rms is appended to a list (batch_v2rms_samples). "
        "When the batch reaches 20 stats, the block V^2_rms is computed as the arithmetic "
        "mean of the batch, and the batch variance is computed using Python's statistics.variance(). "
        "The list is then cleared for the next block."
    )
    pdf.code_block(
        "# Per stat:\n"
        "stat_vpp = code_to_volts(peak_pos) - code_to_volts(peak_neg)\n"
        "stat_v2rms = (stat_vpp * stat_vpp) / 8.0\n"
        "batch_v2rms_samples.append(stat_v2rms)\n"
        "\n"
        "# At batch boundary (every 20 stats):\n"
        "block_v2rms = statistics.fmean(batch_v2rms_samples)\n"
        "block_var   = statistics.variance(batch_v2rms_samples)\n"
        "batch_v2rms_samples.clear()  # reset for next block"
    )

    pdf.sub_title("4.3 Sliding RMS Implementation")
    pdf.body_text(
        "A deque of fixed maximum length (the sliding window size, default 50) acts as the "
        "circular buffer. A running sum (sliding_running_sum) is maintained across batch "
        "boundaries -- it is never reset. When a new stat arrives:"
    )
    pdf.code_block(
        "# If buffer is full, subtract the oldest value:\n"
        "if len(sliding_buf) == window_size:\n"
        "    sliding_running_sum -= sliding_buf[0]\n"
        "\n"
        "# Add the new value:\n"
        "sliding_buf.append(stat_v2rms)\n"
        "sliding_running_sum += stat_v2rms\n"
        "\n"
        "# Record this step's sliding output:\n"
        "sliding_output = sliding_running_sum / len(sliding_buf)"
    )
    pdf.body_text(
        "Each step produces a new sliding V^2_rms output. These per-step outputs are "
        "collected in batch_sliding_outputs. At batch finalization, the CSV records:"
    )
    pdf.bullet("sliding_rms2_measured: the latest sliding output (last value in the batch).")
    pdf.ln(1)
    pdf.bullet("sliding_variance: the variance of all per-step sliding outputs within that batch, "
               "which quantifies the 'wobble' or jitter of the continuous estimator.")
    pdf.ln(3)
    pdf.body_text(
        "Critically, the sliding buffer and running sum persist across batch boundaries. "
        "This means the sliding window genuinely spans across blocks, unlike the block "
        "estimator which resets completely. This is where numerical drift manifests: "
        "after thousands of add/subtract cycles, the running sum may diverge from the "
        "true sum of the buffer contents due to floating-point rounding."
    )

    pdf.sub_title("4.4 CSV Output Format")
    pdf.body_text("Each batch produces one row in the RMS comparison CSV with these columns:")
    pdf.set_font("Courier", "", 8.5)
    cols_desc = [
        ("host_time_iso", "ISO timestamp on the host when the batch was finalized"),
        ("report_index", "Sequential batch number (1, 2, 3, ...)"),
        ("frequency_mhz", "FPGA-measured signal frequency (averaged over the batch)"),
        ("measured_vpp", "FPGA-measured peak-to-peak voltage in volts"),
        ("block_rms2_measured", "Block V^2_rms: mean of per-stat V^2_rms in the batch"),
        ("block_variance", "Variance of per-stat V^2_rms values within the batch"),
        ("sliding_rms2_measured", "Latest sliding V^2_rms output at batch end"),
        ("sliding_variance", "Variance of per-step sliding outputs within the batch"),
    ]
    pdf.set_font("Helvetica", "B", 9)
    pdf.cell(55, 6, "Column", border=1, align="C")
    pdf.cell(0, 6, "Description", border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 8.5)
    for col, desc in cols_desc:
        pdf.cell(55, 5.5, col, border=1)
        pdf.cell(0, 5.5, desc, border=1)
        pdf.ln()
    pdf.ln(4)

    pdf.sub_title("4.5 Usage")
    pdf.code_block(
        "python3 python/adc_stats_analyzer.py \\\n"
        "    --bind-port 40000 --fpga-ip 192.168.1.128 \\\n"
        "    --rms-csv rms_comparison.csv \\\n"
        "    --sliding-window 50 \\\n"
        "    --duration-sec 1"
    )

    # --------------------------------------------------------------
    # 5. Relative Power Correctness
    # --------------------------------------------------------------
    pdf.section_title("5. Relative Power Correctness (Normalization Approach)")

    pdf.body_text(
        "Because the absolute signal amplitude changes with frequency due to DAC, ADC, "
        "and analog path effects, comparing raw V^2_rms values across frequencies is "
        "misleading. Instead, we evaluate relative power correctness."
    )
    pdf.body_text(
        "A baseline frequency f_0 is chosen where the DAC output amplitude is highest. "
        "At each test frequency f_i, the oscilloscope measures the true V_pp. The ideal "
        "V^2_rms ratio relative to baseline is:"
    )
    pdf.equation("ideal_ratio(f_i) = ( V_pp(f_i) / V_pp(f_0) )^2")
    pdf.body_text(
        "If signal B has half the amplitude of signal A, its V^2_rms must be exactly 1/4 "
        "of signal A's. A numerically correct estimator preserves this ratio regardless of "
        "frequency, window length, or estimator type."
    )
    pdf.body_text("The bias of each estimator at frequency f_i is then:")
    pdf.equation("bias(f_i) = measured_ratio(f_i) - ideal_ratio(f_i)")
    pdf.body_text(
        "Bias quantifies systematic deviation caused by quantization, accumulator width, "
        "or recursive drift. Variance quantifies measurement-to-measurement wobble."
    )

    # --------------------------------------------------------------
    # 6. Experimental Setup
    # --------------------------------------------------------------
    pdf.section_title("6. Experimental Setup")

    pdf.sub_title("6.1 Hardware")
    pdf.bullet("FPGA board: Xilinx KC705 (Kintex-7 XC7K325T)")
    pdf.ln(1)
    pdf.bullet("ADC: 12-bit, 125 MSPS (on FMC daughter card)")
    pdf.ln(1)
    pdf.bullet("DAC: AD9781 (on FMC daughter card)")
    pdf.ln(1)
    pdf.bullet("Clock: 125 MHz (from on-board MMCM)")
    pdf.ln(1)
    pdf.bullet("Host: Raspberry Pi / PC connected via Gigabit Ethernet")
    pdf.ln(1)
    pdf.bullet("Oscilloscope: used for baseline V_pp reference measurements")
    pdf.ln(3)

    pdf.sub_title("6.2 Signal Path")
    pdf.body_text(
        "The FPGA DDS generates a tone at the programmed frequency (2-40 MHz). "
        "The tone is output through the DAC, looped back externally into the ADC input. "
        "The FPGA computes per-stat peak-positive, peak-negative, frequency, and phase, "
        "then streams these stats over UDP to the host. The host Python script computes "
        "block and sliding V^2_rms from the received stats."
    )
    pdf.code_block(
        "[DDS (2-40 MHz)] --> [DAC] --> [external loopback] --> [ADC]\n"
        "                                                        |\n"
        "                                                   [FPGA stats]\n"
        "                                                        |\n"
        "                                                   [UDP stream]\n"
        "                                                        |\n"
        "                                              [Python analyzer]\n"
        "                                            block RMS / sliding RMS"
    )

    pdf.sub_title("6.3 Procedure")
    pdf.body_text(
        "1. Choose a baseline frequency where the DAC output amplitude is highest.\n"
        "2. Measure V_pp on the oscilloscope at the baseline frequency.\n"
        "3. For each test frequency (approximately 10 frequencies across 2-40 MHz):\n"
        "   a. Program the DDS to the test frequency via register write.\n"
        "   b. Measure V_pp on the oscilloscope.\n"
        "   c. Run the analyzer for a fixed duration (e.g. 5 seconds) with --rms-csv.\n"
        "   d. Record the block and sliding V^2_rms values and their variances.\n"
        "4. Compute ideal ratios from oscilloscope V_pp measurements.\n"
        "5. Compute bias = measured_ratio - ideal_ratio for each estimator.\n"
        "6. Tabulate and compare."
    )

    pdf.sub_title("6.4 Measurement Table")
    pdf.body_text(
        "The following table will be populated during the experiment. Shaded cells indicate "
        "values to be filled in from measurements."
    )
    # Table header
    pdf.set_font("Helvetica", "B", 8)
    cw = [18, 18, 18, 24, 24, 20, 24, 24, 20]
    hdrs = [
        "Freq\n(MHz)", "Scope\nVpp (V)", "Ideal\nRatio",
        "Block\nV^2rms", "Block\nRatio", "Block\nBias %",
        "Sliding\nV^2rms", "Sliding\nRatio", "Sliding\nBias %",
    ]
    for i, h in enumerate(hdrs):
        pdf.cell(cw[i], 10, h, border=1, align="C")
    pdf.ln()

    # Placeholder frequency rows
    freqs = ["2", "5", "8", "10", "15", "20", "25", "30", "35", "40"]
    pdf.set_font("Helvetica", "", 8)
    for f in freqs:
        pdf.cell(cw[0], 6, f, border=1, align="C")
        for j in range(1, len(cw)):
            pdf.set_fill_color(255, 255, 200)
            pdf.cell(cw[j], 6, "--", border=1, align="C", fill=True)
        pdf.ln()
    pdf.ln(4)

    pdf.sub_title("6.5 Expected Outcomes")
    pdf.bullet("Block RMS: low bias across all frequencies; variance bounded by quantization noise floor.")
    pdf.ln(1)
    pdf.bullet("Sliding RMS: comparable or slightly higher bias due to add/subtract rounding accumulation; "
               "lower latency (value updates every stat instead of every 20).")
    pdf.ln(1)
    pdf.bullet("At higher frequencies where V_pp is small, both estimators may show increased bias "
               "because quantization error is larger relative to the signal.")
    pdf.ln(1)
    pdf.bullet("Sliding variance is expected to be higher than block variance because the sliding "
               "window overlaps across blocks and carries state from previous measurements.")
    pdf.ln(3)

    # --------------------------------------------------------------
    # 7. Oscilloscope Measurement Uncertainty
    # --------------------------------------------------------------
    pdf.section_title("7. Oscilloscope Measurement Uncertainty")

    pdf.sub_title("7.1 Instrument: Tektronix TDS 3034B")
    pdf.body_text(
        "The baseline Vpp measurements used to compute ideal power ratios are "
        "taken with a Tektronix TDS 3034B oscilloscope. Key specifications:"
    )
    pdf.bullet("Vertical resolution: 8 bits (256 levels over full scale).")
    pdf.ln(1)
    pdf.bullet("Vertical divisions: 8 (not 10).")
    pdf.ln(1)
    pdf.bullet("Averaging mode: up to 512 frames.")
    pdf.ln(1)
    pdf.bullet("Bandwidth: 300 MHz (-3 dB).")
    pdf.ln(3)

    pdf.sub_title("7.2 Quantization Step Size")
    pdf.body_text(
        "At a given vertical sensitivity S (volts/division), the full-scale "
        "range is 8 * S and the quantization step (1 LSB) is:"
    )
    pdf.equation("Q_scope = (8 * S) / 256 = S / 32")
    pdf.body_text("For the experiment's typical settings:")
    pdf.set_font("Helvetica", "B", 9)
    cw7 = [35, 35, 35, 35]
    for i, h in enumerate(["V/div (S)", "Full Scale", "Q_scope", "Signal Vpp"]):
        pdf.cell(cw7[i], 7, h, border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 9)
    scope_rows = [
        ("100 mV", "800 mV", "3.1 mV", "~500 mV"),
        ("200 mV", "1.6 V", "6.3 mV", "~1 V"),
        ("500 mV", "4.0 V", "15.6 mV", "~2 V"),
    ]
    for r in scope_rows:
        for i, v in enumerate(r):
            pdf.cell(cw7[i], 6, v, border=1, align="C")
        pdf.ln()
    pdf.ln(3)
    pdf.body_text(
        "At 100 mV/div with a 500 mV Vpp signal, the signal spans roughly "
        "160 of 256 available levels (5 of 8 divisions). This is near-optimal "
        "utilization of the scope's vertical resolution."
    )

    pdf.sub_title("7.3 Effect of Averaging on Effective Resolution")
    pdf.body_text(
        "The TDS 3034B supports averaging up to 512 frames. Frame averaging "
        "reduces the effective quantization noise by the square root of the "
        "number of averaged frames:"
    )
    pdf.equation("Q_eff = Q_scope / sqrt(N_avg)")
    pdf.body_text("For 100 mV/div (Q_scope = 3.1 mV):")
    pdf.set_font("Helvetica", "B", 9)
    cw7b = [40, 40, 40, 40]
    for i, h in enumerate(["N_avg", "Q_eff (mV)", "Vpp Uncert.", "Ratio Uncert."]):
        pdf.cell(cw7b[i], 7, h, border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 9)
    avg_rows = [
        ("1 (none)", "3.10", "+/-0.62%", "+/-1.24%"),
        ("16", "0.78", "+/-0.16%", "+/-0.31%"),
        ("64", "0.39", "+/-0.08%", "+/-0.16%"),
        ("256", "0.19", "+/-0.04%", "+/-0.08%"),
        ("512", "0.14", "+/-0.03%", "+/-0.05%"),
    ]
    for r in avg_rows:
        for i, v in enumerate(r):
            pdf.cell(cw7b[i], 6, v, border=1, align="C")
        pdf.ln()
    pdf.ln(2)
    pdf.body_text(
        "'Vpp Uncert.' is Q_eff / Vpp (for a 500 mV signal). 'Ratio Uncert.' "
        "is the propagated uncertainty in the squared ratio (ideal_ratio = "
        "(Vpp_i/Vpp_0)^2); since squaring doubles the relative error, the ratio "
        "uncertainty is approximately 2x the Vpp uncertainty."
    )

    pdf.sub_title("7.4 Comparison to FPGA ADC Quantization")
    pdf.body_text(
        "The FPGA's 12-bit ADC has a quantization step of approximately 1.2 mV "
        "(5 V / 4096). Without scope averaging, the scope's 3.1 mV LSB is "
        "about 2.5x coarser than the ADC. With 512-frame averaging, the scope's "
        "effective resolution (0.14 mV) is about 8.5x finer than the ADC -- so "
        "the scope no longer limits measurement quality."
    )
    pdf.body_text(
        "Conclusion: with 512-frame averaging at 100 mV/div, the oscilloscope's "
        "effective Vpp uncertainty is +/-0.03%, and the ideal ratio uncertainty "
        "is +/-0.05%. Any FPGA RMS estimator bias larger than approximately "
        "0.1% is detectable above the scope's noise floor."
    )

    pdf.sub_title("7.5 Recommended Measurement Procedure")
    pdf.body_text(
        "1. Set the oscilloscope to 100 mV/div (or the narrowest range that "
        "fits the signal without clipping).\n"
        "2. Enable 512-frame averaging mode.\n"
        "3. Wait for averaging to fully complete (indicated on screen).\n"
        "4. Use the oscilloscope's built-in Measure > Peak-Peak function.\n"
        "5. Record 5 independent Vpp readings at each frequency.\n"
        "6. Compute the mean and standard deviation of the 5 readings.\n"
        "7. Use the mean as the ideal Vpp; report stdev as measurement uncertainty.\n"
        "8. In the final results table, flag any frequency where the measured FPGA "
        "bias is smaller than the scope's ratio uncertainty (+/-0.05%)."
    )
    pdf.ln(2)

    pdf.sub_title("7.6 Uncertainty Budget Summary")
    pdf.set_font("Helvetica", "B", 9)
    cw7c = [60, 50, 60]
    for i, h in enumerate(["Error Source", "Magnitude", "Mitigation"]):
        pdf.cell(cw7c[i], 7, h, border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 8.5)
    unc_rows = [
        ("Scope quantization (raw)", "3.1 mV (0.62%)", "512-frame averaging"),
        ("Scope quantization (avg 512)", "0.14 mV (0.03%)", "Dominant after avg"),
        ("FPGA ADC quantization", "1.2 mV (0.24%)", "12-bit, irreducible"),
        ("Analog path variation", "Frequency-dependent", "Normalized by Vpp ratio"),
        ("Probe loading / mismatch", "<1%", "Use matched 50-ohm term."),
    ]
    for r in unc_rows:
        for i, v in enumerate(r):
            pdf.cell(cw7c[i], 5.5, v, border=1)
        pdf.ln()
    pdf.ln(4)

    # --------------------------------------------------------------
    # 8. References
    # --------------------------------------------------------------
    pdf.section_title("8. References")
    pdf.set_font("Helvetica", "", 9)
    refs = [
        "[1] IEEE Std 1057 -- Standard for Digitizing Waveform Recorders.",
        "[2] Zhang et al., 'FPGA-Based Digital Lock-in Amplifier With High-Precision "
        "Automatic Frequency Tracking,' IEEE Access, 2020. DOI: 10.1109/ACCESS.2020.3006070",
        "[3] Hamouda et al., 'FPGA-Based Real-Time Data Acquisition and Transmission Using "
        "Ethernet UDP,' IEEE ISNIB, 2025. DOI: 10.1109/ISNIB64820.2025.10983340",
        "[4] Tektronix TDS 3034B Digital Phosphor Oscilloscope User Manual, "
        "Tektronix Inc., 071-0274-03.",
    ]
    for ref in refs:
        pdf.multi_cell(0, 5, ref)
        pdf.ln(1)

    # --------------------------------------------------------------
    # Write
    # --------------------------------------------------------------
    pdf.output(output_path)
    print(f"PDF written to: {output_path}")


if __name__ == "__main__":
    out = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "rms_block_vs_sliding.pdf",
    )
    if len(sys.argv) > 1:
        out = sys.argv[1]
    build_pdf(out)
