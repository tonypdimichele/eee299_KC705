#!/usr/bin/env python3
"""Generate PDF: Costas Correlation Phase Estimator with Hilbert FIR."""

from fpdf import FPDF
import subprocess, pathlib, sys


class DocPDF(FPDF):
    MARGIN = 18
    COL_W = 174  # 210 - 2*18

    def header(self):
        self.set_font("Helvetica", "I", 8)
        self.cell(0, 5, "EEE299 -- Costas Correlation Phase Estimator", align="R", new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.cell(0, 5, f"Page {self.page_no()}/{{nb}}", align="C")

    def section(self, num, title):
        self.set_font("Helvetica", "B", 14)
        self.cell(0, 10, f"{num}. {title}", new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def subsection(self, num, title):
        self.set_font("Helvetica", "B", 11)
        self.cell(0, 8, f"{num} {title}", new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def body(self, text):
        self.set_font("Helvetica", "", 10)
        self.multi_cell(self.COL_W, 5, text)
        self.ln(2)

    def bold(self, text):
        self.set_font("Helvetica", "B", 10)
        self.multi_cell(self.COL_W, 5, text)
        self.ln(1)

    def code(self, text):
        self.set_font("Courier", "", 8)
        for line in text.split("\n"):
            self.cell(0, 4, f"  {line}", new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def bullet(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_x(self.l_margin + 4)
        self.multi_cell(self.COL_W - 4, 5, f"- {text}")
        self.ln(1)

    def equation(self, tex):
        self.set_font("Courier", "B", 10)
        self.cell(0, 6, f"    {tex}", new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def table_row(self, cells, bold=False, fill=False):
        style = "B" if bold else ""
        self.set_font("Helvetica", style, 9)
        col_w = self.COL_W / len(cells)
        for c in cells:
            self.cell(col_w, 6, str(c), border=1, align="C",
                      fill=fill, new_x="RIGHT", new_y="TOP")
        self.ln()

    def ref_entry(self, tag, text):
        self.set_font("Helvetica", "B", 9)
        self.cell(12, 5, tag)
        self.set_font("Helvetica", "", 9)
        self.multi_cell(self.COL_W - 12, 5, text)
        self.ln(1)


def build():
    pdf = DocPDF("P", "mm", "A4")
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.set_left_margin(DocPDF.MARGIN)
    pdf.set_right_margin(DocPDF.MARGIN)

    # ======== TITLE PAGE ========
    pdf.add_page()
    pdf.ln(50)
    pdf.set_font("Helvetica", "B", 24)
    pdf.cell(0, 14, "Costas Correlation Phase Estimator", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 14)
    pdf.cell(0, 10, "Hilbert FIR + Host-Side atan2 Implementation", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(8)
    pdf.set_font("Helvetica", "", 12)
    pdf.cell(0, 8, "EEE299  --  KC705 FPGA Platform", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 8, "Tony DiMichele", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(20)
    pdf.set_font("Helvetica", "I", 10)
    pdf.cell(0, 6, "Xilinx Kintex-7 KC705, AD9627 dual-channel 12-bit ADC @ 125 MSPS,", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, "custom Hilbert FIR phase-shift network, Python host-side atan2.", align="C",
             new_x="LMARGIN", new_y="NEXT")

    # ======== 1. INTRODUCTION ========
    pdf.add_page()
    pdf.section("1", "Introduction")
    pdf.body(
        "This document describes the FPGA-based Costas correlation phase estimator implemented "
        "in phase_costas.sv. The module measures the relative phase between two same-frequency "
        "sinusoidal signals received on the I (cosine) and Q (sine) channels of an AD9627 "
        "dual-channel ADC. The measurement is frequency-independent across the passband "
        "(approximately 1.3 MHz to 40 MHz at 125 MSPS sampling)."
    )
    pdf.body(
        "The system uses a hardware/software co-design approach:"
    )
    pdf.bullet("FPGA: Computes the correlation pair (X, Y) using a 15-tap Hilbert FIR and "
               "pipelined accumulators. Normalizes the 40-bit accumulators to 12-bit signed "
               "values and transmits them to the host via UDP.")
    pdf.bullet("Host (Python): Receives the normalized X/Y pair and computes "
               "phase = atan2(Y, X) using IEEE 754 double-precision math. This eliminates "
               "FPGA CORDIC IP complexity and provides full-precision four-quadrant phase.")
    pdf.body(
        "This approach was chosen after validating that FPGA-side CORDIC introduced "
        "pipeline-latching artifacts. Moving atan2 to Python gives exact results with "
        "zero FPGA resource cost for the trigonometric computation."
    )

    pdf.subsection("1.1", "System Context")
    pdf.body(
        "The phase_costas module is instantiated by adc_stats.sv, which orchestrates the "
        "adaptive-N zero-crossing frequency measurement, peak tracking, and I-to-Q delay "
        "measurement. The adc_stats module drives the window_start and window_done pulses "
        "into phase_costas based on I-channel zero-crossing events, ensuring the correlation "
        "window spans an integer number of signal cycles."
    )
    pdf.body("The adc_stats output is a 16-byte AXIS byte stream packed as:")
    pdf.code(
        "Byte    Field\n"
        "------  -----\n"
        " [0]    0xA7 sync byte\n"
        " [1]    peak_pos[11:4]\n"
        " [2]    {peak_pos[3:0], peak_neg[11:8]}\n"
        " [3]    peak_neg[7:0]\n"
        "[4:7]   iq_delay_sum (unsigned 32-bit big-endian)\n"
        "[8:9]   measured_clk_count (unsigned 16-bit big-endian)\n"
        "[10:11] measured_cycles_count (unsigned 16-bit big-endian)\n"
        "[12:13] corr_y (signed 16-bit big-endian, correlation Y)\n"
        "[14:15] corr_x (signed 16-bit big-endian, correlation X)"
    )
    pdf.body(
        "This packet crosses the adc1_clk -> clk_int clock domain via an async FIFO in "
        "KC705_EEE299_top.v, then is encapsulated into UDP frames by the ethernet subsystem "
        "for delivery to the host."
    )

    # ======== 2. COSTAS CORRELATION METHOD ========
    pdf.add_page()
    pdf.section("2", "Costas Correlation Phase Estimation")

    pdf.subsection("2.1", "Mathematical Basis")
    pdf.body(
        "Consider two sinusoids at the same frequency but with a relative phase offset phi:"
    )
    pdf.equation("I(t) = A * cos(wt)")
    pdf.equation("Q(t) = B * cos(wt + phi)")
    pdf.body(
        "The phase phi can be recovered by correlating Q against both I and a 90-degree shifted "
        "copy of I (denoted I_90). Over one or more complete cycles:"
    )
    pdf.equation("X = SUM[ I[n]*Q[n] + I90[n]*Q90[n] ]  =  (AB/2) * cos(phi)")
    pdf.equation("Y = SUM[ I90[n]*Q[n] - I[n]*Q90[n] ]  =  (AB/2) * sin(phi)")
    pdf.body(
        "The phase is then:"
    )
    pdf.equation("phi = atan2(Y, X)")
    pdf.body(
        "This is the standard Costas-loop discriminator formulation. The key advantage is "
        "that the amplitude terms A and B cancel in the ratio Y/X, making the measurement "
        "amplitude-independent. The atan2 function resolves all four quadrants."
    )

    pdf.subsection("2.2", "Windowed Accumulation")
    pdf.body(
        "The accumulators X and Y run over a measurement window of N positive-going zero "
        "crossings of the I channel, where zero-crossing detection uses a hysteresis threshold "
        "of +/-4 LSB (ZC_HYST = 4 in adc_stats.sv). The adaptive-N system in adc_stats.sv "
        "adjusts N to keep the total clock count in a target range (FREQ_CLK_TARGET_LO=8000 "
        "to FREQ_CLK_TARGET_HI=50000 clocks), bounded by FREQ_N_MIN=32 and FREQ_N_MAX=16384."
    )
    pdf.body(
        "At the window boundary, adc_stats pulses costas_window_done, which causes "
        "phase_costas to snapshot the accumulators and pass them to the normalization pipeline. "
        "Accumulation for the next window begins immediately. If the accumulator exceeds "
        "FREQ_ACCUM_ABORT (500,000 clocks), adc_stats pulses costas_window_start instead, "
        "which aborts the window without generating output."
    )

    pdf.subsection("2.3", "IDDR Channel Alignment")
    pdf.body(
        "The AD9627 ADC outputs I and Q channels in DDR format. The FPGA IDDR primitive in "
        "SAME_EDGE mode causes channel B (Q) to arrive 1 sample late relative to channel A (I). "
        "This is compensated by delaying sample_i by 1 clock in adc_stats.sv before feeding "
        "it to the phase estimator:"
    )
    pdf.code(
        "reg signed [11:0] sample_i_d1;\n"
        "always @(posedge clk) sample_i_d1 <= sample_i;\n"
        "\n"
        "phase_costas u_phase_costas (\n"
        "    .sample_i(sample_i_d1),  // delayed to align with late Q\n"
        "    .sample_q(sample_q),\n"
        "    ..."
    )
    pdf.body(
        "Without this compensation, all phase readings have a constant offset of "
        "360 * f_signal / f_sample degrees (e.g., +31.7 degrees at 11 MHz / 125 MSPS)."
    )

    # ======== 3. HILBERT FIR FILTER ========
    pdf.add_page()
    pdf.section("3", "Hilbert FIR Transform (90-Degree Phase Shift)")

    pdf.subsection("3.1", "Why a Hilbert Filter?")
    pdf.body(
        "The correlation method requires I_90[n], a copy of I[n] shifted by exactly 90 degrees. "
        "A BRAM delay line of quarter_period samples introduces frequency-dependent error because "
        "the quarter period is rounded to an integer. A Hilbert transform FIR filter provides "
        "a true 90-degree phase shift at ALL frequencies within its passband, with a fixed "
        "and known group delay, eliminating frequency dependence."
    )

    pdf.subsection("3.2", "Filter Design: 15-Tap Type III FIR")
    pdf.body(
        "The ideal discrete-time Hilbert transform has the impulse response "
        "h[n] = 2/(pi*n) for n odd, 0 for n even. We use a 15-tap windowed truncation "
        "(Type III FIR: odd length, antisymmetric). Non-zero coefficients scaled by 2048:"
    )
    pdf.code(
        "Tap    k (offset)   h_float       h_int (x2048)   RTL param\n"
        "---    ----------   -------       -------------   ---------\n"
        " 0       -7         -0.0909        -186           H1 = 186\n"
        " 2       -5         -0.1273        -261           H3 = 261\n"
        " 4       -3         -0.2122        -435           H5 = 435\n"
        " 6       -1         -0.6366       -1304           H7 = 1304\n"
        " 7        0          0.0000           0           (center)\n"
        " 8       +1         +0.6366       +1304           H7\n"
        "10       +3         +0.2122        +435           H5\n"
        "12       +5         +0.1273        +261           H3\n"
        "14       +7         +0.0909        +186           H1"
    )
    pdf.body(
        "All even-offset taps are exactly zero. Antisymmetry means only 4 unique "
        "multiplications are needed, using pre-addition of symmetric tap pairs."
    )

    pdf.subsection("3.3", "Group Delay and Signal Alignment")
    pdf.body(
        "A linear-phase FIR of length N has constant group delay (N-1)/2 samples. For 15 taps "
        "this is 7 samples (GRP_DELAY=7). Both the direct I path and Q signal are delayed by "
        "7 samples via shift registers so that I_delayed, Hilbert(I), Q_delayed, and "
        "Hilbert(Q) are all time-aligned."
    )

    pdf.subsection("3.4", "DSP48 Efficient Implementation")
    pdf.body(
        "The Xilinx DSP48E1 pre-adder is exploited for the antisymmetric differences:"
    )
    pdf.code(
        "diff1 = sr[14] - sr[0]   -> * H1 (186)\n"
        "diff3 = sr[12] - sr[2]   -> * H3 (261)\n"
        "diff5 = sr[10] - sr[4]   -> * H5 (435)\n"
        "diff7 = sr[8]  - sr[6]   -> * H7 (1304)"
    )
    pdf.body(
        "This uses 4 DSP48 slices per channel (8 total for I and Q Hilbert). Products are "
        "summed into a 27-bit accumulator, right-shifted by 11 (divide by 2048), and "
        "saturated to 12-bit signed."
    )

    pdf.subsection("3.5", "Frequency Response")
    pdf.body(
        "A 15-tap Hilbert FIR has passband ~0.04*fs to ~0.46*fs. At 125 MSPS: ~5 MHz to "
        "~57 MHz. Below 5 MHz the magnitude rolls off but does NOT affect phase measurement "
        "since both X and Y arms are attenuated equally. Measurements remain stable down to "
        "~1.3 MHz due to long averaging windows at low frequencies."
    )

    # ======== 4. NORMALIZATION AND OUTPUT ========
    pdf.add_page()
    pdf.section("4", "Normalization and X/Y Output")

    pdf.subsection("4.1", "Why Normalize?")
    pdf.body(
        "The correlation accumulators are 40 bits wide (ACC_W=40) to prevent overflow during "
        "long measurement windows (up to 50,000 clocks). However, only the ratio Y/X matters "
        "for phase. The normalization pipeline scales both X and Y to fit in 12-bit signed "
        "range while preserving their ratio, enabling efficient 24-bit UDP transport."
    )

    pdf.subsection("4.2", "Two-Stage Pipeline")
    pdf.body("Split into two registered stages to meet 125 MHz timing:")
    pdf.bullet("Stage 5a: Compute |snap_x| and |snap_y| via conditional negation. "
               "Select max(|X|, |Y|) = norm_max_abs.")
    pdf.bullet("Stage 5b: Priority-encode the leading one of norm_max_abs via a 40-bit "
               "cascaded ternary chain (bits [39] down to [11]) to produce a 6-bit "
               "right-shift amount. This maps the largest accumulator into [0, 2047].")
    pdf.body(
        "Finally (Stage 6): Apply the arithmetic right-shift to both X and Y, saturate "
        "each to [-2048, +2047], and register the outputs as xy_x_out and xy_y_out."
    )

    pdf.subsection("4.3", "Host-Side atan2")
    pdf.body(
        "The host Python analyzer receives the 12-bit signed X and Y values "
        "(sign-extended to 16-bit in the UDP packet) and computes:"
    )
    pdf.code(
        "import math\n"
        "phase_deg = math.degrees(math.atan2(corr_y, corr_x))"
    )
    pdf.body(
        "This gives full IEEE 754 double-precision atan2 with all four quadrants resolved. "
        "No CORDIC IP is needed on the FPGA, saving logic resources and eliminating pipeline "
        "latching artifacts that were observed with the Xilinx CORDIC IP."
    )

    pdf.subsection("4.4", "Advantages Over FPGA CORDIC")
    pdf.bullet("Zero FPGA resource usage for trigonometry (no CORDIC IP instantiation).")
    pdf.bullet("Full double-precision result (vs 16-bit fixed-point CORDIC output).")
    pdf.bullet("No pipeline latency or handshake complexity between CORDIC and output latch.")
    pdf.bullet("Simpler RTL: fewer state machines, no cordic_pending flag logic.")
    pdf.bullet("Debugging: raw X/Y visible in packets, allowing immediate verification of "
               "correlation quality without ILA.")

    # ======== 5. PIPELINE STRUCTURE ========
    pdf.add_page()
    pdf.section("5", "Pipeline Structure and Timing")
    pdf.body("The full pipeline from ADC input to X/Y output:")
    pdf.code(
        "Clock  Stage  Operation\n"
        "-----  -----  ---------\n"
        "  0      0    DC-block + shift register load\n"
        "  1      1a   Hilbert pre-add (antisymmetric differences)\n"
        "  2      1b   Hilbert multiply (DSP48)\n"
        "  3      2    Hilbert sum + saturate + register I90/Q90/I_del/Q_del\n"
        "  4      3    Correlation multiply: I*Q, I90*Q, I90*Q90, I*Q90\n"
        "  5      4    Accumulate X += I*Q + I90*Q90, Y += I90*Q - I*Q90\n"
        "  ...         (runs for N zero-crossing cycles)\n"
        "  N+5    4    Snapshot: snap_x, snap_y <- final accumulators\n"
        "  N+6    5a   Absolute value + max selection\n"
        "  N+7    5b   Leading-one detect (priority encode)\n"
        "  N+8    6    Shift + saturate + output xy_x_out, xy_y_out, xy_valid"
    )
    pdf.body(
        "The window_done and window_start pulses are pipelined through a 5-bit shift register "
        "to arrive at the accumulator input exactly when the corresponding products are ready. "
        "This ensures the final clock's products are included in the snapshot sum."
    )

    pdf.subsection("5.1", "Latency Budget")
    pdf.body(
        "From window_done pulse to xy_valid output: 5 (pipeline) + 3 (normalization) = "
        "8 clock cycles = 64 ns at 125 MHz. This is negligible compared to the measurement "
        "window duration (typically 8,000-50,000 clocks = 64-400 us)."
    )

    # ======== 6. DC BLOCKING ========
    pdf.add_page()
    pdf.section("6", "DC Blocking Filter")
    pdf.body(
        "A first-order IIR DC blocker removes any DC offset from both I and Q channels "
        "before the Hilbert FIR and correlation. This prevents DC offsets from biasing "
        "the accumulator towards zero angle."
    )
    pdf.body("Transfer function (z-domain):")
    pdf.equation("H(z) = 1 - z^(-1) * (1 - 2^(-K))")
    pdf.body(
        "With DC_BLOCK_SHIFT=8 (K=8), the -3 dB corner is approximately "
        "fs / (2*pi*2^K) = 125e6 / (2*pi*256) = 77.7 kHz. This is well below the "
        "minimum signal frequency (~1.3 MHz) so signal attenuation is negligible."
    )

    # ======== 7. RESOURCE USAGE ========
    pdf.section("7", "FPGA Resource Usage")
    pdf.body("Estimated resource usage for phase_costas (Kintex-7):")
    pdf.table_row(["Resource", "Count", "Notes"], bold=True, fill=True)
    pdf.table_row(["DSP48E1", "12", "8 Hilbert (4 per I/Q) + 4 correlation"])
    pdf.table_row(["Flip-Flops", "~600", "Shift regs, pipeline, accumulators"])
    pdf.table_row(["LUT", "~400", "Normalization, saturation, muxing"])
    pdf.table_row(["BRAM", "0", "No block RAM needed"])
    pdf.body(
        "Removing the CORDIC IP saves approximately 1 DSP48, ~200 FFs, and ~150 LUTs "
        "that were previously used for the iterative rotation pipeline."
    )

    # ======== 8. MEASURED RESULTS ========
    pdf.add_page()
    pdf.section("8", "Measured Results")
    pdf.body(
        "Measured phase accuracy with 11 MHz, 3 Vpp sinusoidal input, channel alignment "
        "compensated (1-sample I delay for IDDR SAME_EDGE Q lag):"
    )
    pdf.table_row(["ARB Phase", "Y (dec)", "X (dec)", "atan2 (deg)", "Error"], bold=True, fill=True)
    pdf.table_row(["40°", "+1337", "+1579", "40.3°", "+0.3°"])
    pdf.table_row(["50°", "+1588", "+1322", "50.2°", "+0.2°"])
    pdf.table_row(["60°", "+1792", "+1026", "60.2°", "+0.2°"])
    pdf.table_row(["70°", "+1940", "+699", "70.2°", "+0.2°"])
    pdf.table_row(["80°", "+2029", "+351", "80.2°", "+0.2°"])
    pdf.table_row(["90°", "+1029", "-3", "90.2°", "+0.2°"])
    pdf.table_row(["100°", "+2022", "-364", "100.2°", "+0.2°"])
    pdf.table_row(["110°", "+1925", "-709", "110.3°", "+0.3°"])
    pdf.body(
        "Maximum error: 0.3 degrees across 70 degrees of phase sweep. "
        "The systematic ~0.2 degree bias is within the Hilbert FIR quantization error "
        "at 11 MHz (gain ~= 1.07 vs ideal 1.0)."
    )

    # ======== 9. Vpp FREQUENCY CALIBRATION ========
    pdf.add_page()
    pdf.section("9", "Vpp Frequency Calibration")
    pdf.body(
        "The measured peak-to-peak voltage exhibits a frequency-dependent attenuation "
        "through the ADC signal chain (FMC connector, PCB traces, AD9627 sample-and-hold). "
        "This is characterized by comparing FPGA-reported Vpp against a calibrated oscilloscope "
        "at fixed 3 Vpp output from the UTG962 signal generator."
    )
    pdf.table_row(["Freq (MHz)", "Scope Vpp", "FPGA Vpp", "Ratio"], bold=True, fill=True)
    pdf.table_row(["1.5", "3.10", "2.97", "1.044"])
    pdf.table_row(["5", "3.10", "2.94", "1.054"])
    pdf.table_row(["10", "3.10", "2.90", "1.069"])
    pdf.table_row(["15", "3.10", "2.84", "1.092"])
    pdf.table_row(["18", "3.10", "2.79", "1.111"])
    pdf.table_row(["25", "3.04", "2.56", "1.188"])
    pdf.table_row(["32", "2.90", "2.51", "1.155"])
    pdf.table_row(["40", "2.72", "2.29", "1.188"])
    pdf.body(
        "A linear least-squares fit to the correction factor (scope/FPGA) vs frequency gives:"
    )
    pdf.equation("cal(f) = 1.0377 + 0.00409 * f_MHz")
    pdf.body(
        "This is applied in the Python host analyzer to all Vpp and V^2rms readings. "
        "With calibration enabled, maximum residual error is 4.0% (at 25 MHz where the "
        "signal generator itself begins to roll off), and most points are within 1%."
    )
    pdf.body(
        "The calibration can be disabled with --no-vpp-cal or overridden with "
        "--vpp-cal-a and --vpp-cal-b command-line flags."
    )

    # ======== 10. PYTHON HOST INTERFACE ========
    pdf.add_page()
    pdf.section("10", "Python Host Interface")
    pdf.body(
        "The host-side decoder (adc_stats_analyzer.py) processes the 16-byte stat packets:"
    )
    pdf.code(
        "@staticmethod\n"
        "def _decode_corr_xy(stat_bytes: bytearray) -> tuple:\n"
        "    raw_y = (stat_bytes[11] << 8) | stat_bytes[12]\n"
        "    if raw_y >= 0x8000:\n"
        "        raw_y -= 0x10000\n"
        "    raw_x = (stat_bytes[13] << 8) | stat_bytes[14]\n"
        "    if raw_x >= 0x8000:\n"
        "        raw_x -= 0x10000\n"
        "    return raw_y, raw_x"
    )
    pdf.body("Phase computation:")
    pdf.code(
        "corr_y, corr_x = self._decode_corr_xy(stat_bytes)\n"
        "if corr_y != 0 or corr_x != 0:\n"
        "    phase_deg = math.degrees(math.atan2(corr_y, corr_x))"
    )
    pdf.body(
        "Additional filtering includes EMA smoothing, jump rejection, and optional "
        "pi-ambiguity resolution for wrapping near +/-180 degrees."
    )

    # ======== 11. REFERENCES ========
    pdf.add_page()
    pdf.section("11", "References")
    pdf.ref_entry("[1]", "J.P. Costas, 'Synchronous Communications', Proc. IRE, 1956.")
    pdf.ref_entry("[2]", "F.M. Gardner, 'Phaselock Techniques', 3rd ed., Wiley, 2005.")
    pdf.ref_entry("[3]", "A.V. Oppenheim & R.W. Schafer, 'Discrete-Time Signal Processing', "
                  "3rd ed., Pearson, 2009. Ch. 12: Hilbert Transform.")
    pdf.ref_entry("[4]", "S.L. Marple, 'Computing the Discrete-Time Analytic Signal via FFT', "
                  "IEEE Trans. Signal Processing, 1999.")
    pdf.ref_entry("[5]", "Xilinx UG479: 7 Series DSP48E1 Slice User Guide.")

    # ======== OUTPUT ========
    out_dir = pathlib.Path(__file__).resolve().parent
    out_path = out_dir / "costas_phase_estimator.pdf"
    pdf.output(str(out_path))
    print(f"Generated: {out_path}")


if __name__ == "__main__":
    build()
