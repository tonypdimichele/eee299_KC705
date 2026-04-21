#!/usr/bin/env python3
"""Generate PDF: ADC Statistics -- Compilation, Transfer, and Analysis."""

from fpdf import FPDF


class DocPDF(FPDF):
    MARGIN = 18
    COL_W = 174  # 210 - 2*18

    def header(self):
        if self.page_no() > 1:
            self.set_font("Helvetica", "I", 8)
            self.cell(0, 5, "EEE299 KC705 -- ADC Statistics Subsystem", align="C")
            self.ln(8)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.cell(0, 10, f"Page {self.page_no()}/{{nb}}", align="C")

    # Helpers
    def section(self, num, title):
        self.set_font("Helvetica", "B", 14)
        self.set_text_color(0, 51, 102)
        self.cell(0, 10, f"{num}  {title}", new_x="LMARGIN", new_y="NEXT")
        self.set_text_color(0)
        self.ln(2)

    def subsection(self, num, title):
        self.set_font("Helvetica", "B", 11)
        self.set_text_color(0, 51, 102)
        self.cell(0, 8, f"{num}  {title}", new_x="LMARGIN", new_y="NEXT")
        self.set_text_color(0)
        self.ln(1)

    def body(self, text):
        self.set_font("Helvetica", "", 10)
        self.multi_cell(self.COL_W, 5, text)
        self.ln(2)

    def bold(self, text):
        self.set_font("Helvetica", "B", 10)
        self.multi_cell(self.COL_W, 5, text)
        self.ln(2)

    def code(self, text):
        self.set_font("Courier", "", 8.5)
        self.set_fill_color(240, 240, 240)
        for line in text.strip().split("\n"):
            self.cell(self.COL_W, 4.5, "  " + line, fill=True, new_x="LMARGIN", new_y="NEXT")
        self.ln(3)

    def bullet(self, text):
        self.set_font("Helvetica", "", 10)
        self.cell(6, 5, "-")
        self.multi_cell(self.COL_W - 6, 5, text)
        self.ln(1)

    def table_row(self, cells, bold=False, fill=False):
        style = "B" if bold else ""
        self.set_font("Helvetica", style, 9)
        if fill:
            self.set_fill_color(220, 230, 241)
        for w, txt in cells:
            self.cell(w, 6, txt, border=1, fill=fill, align="C")
        self.ln()

    def equation(self, tex):
        """Render an equation line centered in monospace (poor-man's math)."""
        self.set_font("Courier", "B", 10)
        self.cell(self.COL_W, 7, tex, align="C", new_x="LMARGIN", new_y="NEXT")
        self.ln(2)


def build():
    pdf = DocPDF("P", "mm", "A4")
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.set_left_margin(DocPDF.MARGIN)
    pdf.set_right_margin(DocPDF.MARGIN)

    # ======== TITLE PAGE ========
    pdf.add_page()
    pdf.ln(50)
    pdf.set_font("Helvetica", "B", 26)
    pdf.cell(0, 14, "ADC Statistics Subsystem", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 16)
    pdf.cell(0, 10, "Compilation, Ethernet Transfer, and Host Analysis", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(10)
    pdf.set_font("Helvetica", "", 12)
    pdf.cell(0, 8, "EEE299  --  KC705 FPGA Platform", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 8, "Tony DiMichele", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(20)
    pdf.set_font("Helvetica", "I", 10)
    pdf.cell(0, 6, "Design based on Xilinx KC705, AD9627 dual-channel ADC,", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, "Alex Forencich verilog-ethernet IP, and custom RTL.", align="C",
             new_x="LMARGIN", new_y="NEXT")

    # ======== 1. SYSTEM OVERVIEW ========
    pdf.add_page()
    pdf.section("1", "System Overview")
    pdf.body(
        "The ADC statistics subsystem provides real-time amplitude, frequency, "
        "and I/Q phase measurements from a dual-channel AD9627 12-bit ADC "
        "running at 125 MSPS. All signal processing is performed in FPGA fabric; "
        "a Raspberry Pi host receives compact 12-byte measurement packets over "
        "Gigabit Ethernet and computes final engineering units."
    )
    pdf.body(
        "The end-to-end data path is:"
    )
    pdf.bullet("AD9627 ADC samples I (cosine) and Q (sine) channels at 125 MSPS via LVDS DDR.")
    pdf.bullet("IDDR primitives on the Kintex-7 capture the 12-bit samples on the recovered ADC clock (adc1_clk).")
    pdf.bullet("adc_stats (SystemVerilog) computes peak, frequency, and phase measurements and emits 12-byte packets on an AXI-Stream interface.")
    pdf.bullet("An asynchronous FIFO (Xilinx XPM, 2048-deep, 8-bit) crosses from the ADC clock domain to the 125 MHz Ethernet clock domain.")
    pdf.bullet("A ping-pong buffer frames the byte stream into 512-byte UDP payload segments.")
    pdf.bullet("The Ethernet subsystem transmits UDP datagrams on port 30000 to the host, routed via the latched destination from a prime packet sent to port 20000.")
    pdf.bullet("The Python analyzer (adc_stats_analyzer.py) decodes, validates, and batch-averages measurements, presenting live metrics in a curses UI.")

    # ======== 2. FPGA MEASUREMENT MODULE ========
    pdf.add_page()
    pdf.section("2", "FPGA Measurement Module (adc_stats.sv)")
    pdf.body(
        "The adc_stats module operates entirely in the ADC clock domain "
        "(nominally 125 MHz). It receives raw 12-bit offset-binary I and Q "
        "samples every clock cycle and continuously computes three measurements, "
        "all aligned to positive-going I-channel zero crossings."
    )

    # -- 2.1 Input Conversion
    pdf.subsection("2.1", "Input Conversion: Offset-Binary to Signed")
    pdf.body(
        "The AD9627 outputs 12-bit offset-binary codes where 0x000 represents "
        "the most negative voltage and 0xFFF the most positive. The module "
        "converts to two's-complement signed representation by flipping the MSB:"
    )
    pdf.equation("sample_signed = { ~adc_data[11], adc_data[10:0] }")
    pdf.body(
        "This maps code 0x800 (mid-scale) to signed zero, 0xFFF to +2047, "
        "and 0x000 to -2048. All internal comparisons and peak tracking use "
        "this signed representation. When packing into the output packet, "
        "the inverse transform restores offset-binary for transmission."
    )

    # -- 2.2 Zero-Crossing Detection
    pdf.subsection("2.2", "Zero-Crossing Detection with Hysteresis")
    pdf.body(
        "All three measurements share a common zero-crossing detector on the "
        "I channel. A positive-going zero crossing is recognized when:"
    )
    pdf.bullet("The signal previously fell below -ZC_HYST (default -16 codes), arming the detector (zc_armed = 1).")
    pdf.bullet("The current sample crosses upward through +ZC_HYST (prev < +16, current >= +16).")
    pdf.body(
        "The hysteresis band of +/-16 codes (approximately +/-0.039 V with "
        "the default 5 Vpp / 4096 scale) prevents noise-induced false triggers. "
        "A minimum period guard (FREQ_MIN_PERIOD_CLKS = 2 clocks) rejects "
        "any crossing that occurs too soon after the previous one."
    )
    pdf.body(
        "Q-channel zero crossings use an independent detector with the same "
        "hysteresis thresholds, armed when Q falls below -ZC_HYST and triggered "
        "when Q crosses upward through +ZC_HYST."
    )

    # -- 2.3 Frequency Measurement
    pdf.add_page()
    pdf.subsection("2.3", "Frequency Measurement (Adaptive-N Zero-Crossing Counter)")
    pdf.body(
        "Frequency is measured by counting the number of sample clock cycles "
        "that elapse over N consecutive positive-going I-channel zero crossings. "
        "N is not fixed -- it adapts dynamically to keep the total accumulated "
        "clock count in a target range, ensuring good resolution across the "
        "full frequency span."
    )
    pdf.body("Algorithm per clock cycle:")
    pdf.bullet("A 16-bit period counter (zc_period_counter) increments every clock.")
    pdf.bullet("On each valid positive-going I zero crossing, the period count is added to a 32-bit accumulator (freq_clk_accum) and a cycle counter (freq_cycle_count) increments.")
    pdf.bullet("When freq_cycle_count reaches freq_n_target, the measurement is complete.")
    pdf.body("On measurement completion:")
    pdf.bullet("The 32-bit accumulator is checked against 0xFFFF. If it fits in 16 bits, it is latched into measured_clk_count (16-bit); otherwise the measurement is discarded and N is reduced.")
    pdf.bullet("The cycle count used is latched into measured_cycles_count (16-bit).")
    pdf.bullet("N adapts for the next window: if total clocks > FREQ_CLK_TARGET_HI (50000), N is halved; if < FREQ_CLK_TARGET_LO (8000), N is doubled. The range is clamped to [FREQ_N_MIN=32, FREQ_N_MAX=16384].")
    pdf.bullet("An abort mechanism fires if the accumulator exceeds FREQ_ACCUM_ABORT (500000 clocks), preventing deadlock on very low frequencies. N is quartered and the window restarts.")

    pdf.body("The host computes the final frequency as:")
    pdf.equation("f = f_s * N / total_clks")
    pdf.body(
        "where f_s = 125 MHz (sample rate), N = measured_cycles_count, and "
        "total_clks = measured_clk_count -- all transmitted in the packet."
    )

    # -- 2.3.1 Frequency Resolution
    pdf.subsection("2.3.1", "Frequency Resolution Analysis")
    pdf.body(
        "The frequency measurement resolution is limited by the integer clock "
        "count. If the true period is T_true clocks, the counter reads an "
        "integer value T_meas = round(T_true). Over N cycles the total count "
        "is C = sum of N integer periods. The quantization uncertainty in C "
        "is +/-1 clock, giving:"
    )
    pdf.equation("delta_f = f_s * N / C^2   (for +/-1 count in C)")
    pdf.body("Equivalently, the relative resolution is:")
    pdf.equation("delta_f / f = 1 / C")
    pdf.body(
        "The adaptive-N algorithm targets C in the range [8000, 50000], so "
        "the worst-case relative resolution is 1/8000 = 0.0125% and the "
        "best case is 1/50000 = 0.002%. At representative frequencies:"
    )
    w = [40, 35, 35, 35, 35]
    pdf.table_row(list(zip(w, ["Signal Freq", "Typical N", "Total Clks (C)", "delta_f (Hz)", "Relative"])), bold=True, fill=True)
    pdf.table_row(list(zip(w, ["1 MHz", "320", "~40000", "~3.1 Hz", "0.003%"])))
    pdf.table_row(list(zip(w, ["10 MHz", "4000", "~50000", "~25 Hz", "0.003%"])))
    pdf.table_row(list(zip(w, ["100 kHz", "32", "~40000", "~0.31 Hz", "0.0003%"])))
    pdf.table_row(list(zip(w, ["62.5 MHz", "4000", "~8000", "~977 Hz", "0.0016%"])))
    pdf.ln(2)
    pdf.body(
        "The maximum measurable frequency is the Nyquist rate, f_s/2 = 62.5 MHz. "
        "At that limit, each half-cycle is 1 clock, so the minimum period is 2 "
        "clocks/cycle (enforced by FREQ_MIN_PERIOD_CLKS)."
    )

    # -- 2.4 Peak Amplitude
    pdf.add_page()
    pdf.subsection("2.4", "Peak Amplitude Measurement")
    pdf.body(
        "The module tracks the running maximum and minimum of the signed I-channel "
        "samples over the same N-crossing measurement window used for frequency. "
        "On each clock cycle:"
    )
    pdf.code(
        "if (sample_i > run_pk_pos) run_pk_pos <= sample_i;\n"
        "if (sample_i < run_pk_neg) run_pk_neg <= sample_i;"
    )
    pdf.body(
        "When the N-crossing window completes, the running peak values are latched "
        "into latched_pk_pos and latched_pk_neg, and the running trackers are "
        "reset to -2048 (max) and +2047 (min) respectively. The latched values "
        "are converted back to offset-binary for packet transmission."
    )

    pdf.subsection("2.4.1", "Amplitude Resolution")
    pdf.body(
        "The AD9627 is a 12-bit ADC. With a 5 Vpp full-scale range:"
    )
    pdf.equation("V_LSB = 5 V / 4096 = 1.221 mV")
    pdf.body(
        "Peak values are reported as raw 12-bit offset-binary codes. The host "
        "converts to volts using:"
    )
    pdf.equation("V = ((code - 2048) * (5 / 4096)) * 5  =  ((code - 2048) * 1.221 mV) * 5")
    pdf.body(
        "The amplitude resolution is exactly 1 LSB = 1.221 mV. Peak-to-peak "
        "amplitude has a resolution of 2 LSBs in the worst case (when positive "
        "and negative peaks each have +/-0.5 LSB quantization error that adds "
        "constructively). The dynamic range is:"
    )
    pdf.equation("DR = 20*log10(4096) = 72.2 dB")
    pdf.body(
        "Since the peaks are tracked sample-by-sample, there is no bandwidth "
        "reduction -- the measurement captures the true peak of any waveform "
        "within the ADC's analog bandwidth, limited only by the 125 MSPS "
        "sampling rate."
    )
    pdf.bold("\nNOTE: The extra * 5 in the voltage equation accounts for the ADC input's gain of 1/5\n")

    # -- 2.5 Phase Measurement
    pdf.subsection("2.5", "Phase Measurement (I-to-Q Zero-Crossing Delay)")
    pdf.body(
        "Phase is measured as the time delay between each I-channel positive-going "
        "zero crossing and the next Q-channel positive-going zero crossing. This "
        "is a ideally a pure discrete time-domain measurement with no amplitude dependence,"
        " but due to the quantization at low amplitude and high frequency, the "
        "lower the amplitude the closer to the hystersis thresholds the signal is at its max voltage,"
        " decreasing the accuracy of the zero-crossing timing and therefore the phase measurement."
    )
    pdf.body("Operation:")
    pdf.bullet("At each I-channel zero crossing, a 16-bit counter (iq_delay_counter) is reset to zero and a capture flag (iq_delay_captured) is cleared.")
    pdf.bullet("The counter increments every clock cycle.")
    pdf.bullet("When the Q-channel detector fires (if not already captured for this I cycle), the counter value is added to a 32-bit accumulator (iq_delay_accum) and the capture flag is set.")
    pdf.bullet("At the N-crossing measurement boundary, iq_delay_accum is latched and reset.")
    pdf.body("The host computes phase from the packet fields:")
    pdf.equation("phase = 360 * iq_delay_sum / total_clks  [degrees]")
    pdf.body(
        "Since iq_delay_sum is the sum of N individual delays and total_clks is "
        "the total period over N cycles, the N cancels and the result is the "
        "average phase offset per cycle."
    )

    pdf.add_page()
    pdf.subsection("2.5.1", "Phase Resolution Analysis")
    pdf.body(
        "Each individual I-to-Q delay measurement has a quantization uncertainty "
        "of +/-1 clock cycle. Over N cycles the accumulated delay has "
        "uncertainty +/-N (worst case with correlated errors, but typically "
        "+/-sqrt(N) for uncorrelated jitter). The phase resolution for the "
        "accumulated value is:"
    )
    pdf.equation("delta_phi = 360 / total_clks   [degrees, for +/-1 count]")
    pdf.body("At representative frequencies:")
    w = [40, 30, 35, 35, 35]
    pdf.table_row(list(zip(w, ["Signal Freq", "Period (clks)", "Total Clks (C)", "delta_phi", "After Avg"])), bold=True, fill=True)
    pdf.table_row(list(zip(w, ["1 MHz", "125", "~40000", "0.009 deg", "~0.0005 deg"])))
    pdf.table_row(list(zip(w, ["10 MHz", "12.5", "~50000", "0.007 deg", "~0.0004 deg"])))
    pdf.table_row(list(zip(w, ["62.5 MHz", "2", "~8000", "0.045 deg", "~0.002 deg"])))
    pdf.ln(2)
    pdf.body(
        "The 'After Avg' column accounts for the Python host's 20-sample batch "
        "averaging, which further reduces noise by approximately sqrt(20) ~ 4.5x. "
        "The phase measurement is normalized to [-180, +180] degrees by the host."
    )
    pdf.body(
        "Important limitation: at very high frequencies near Nyquist (62.5 MHz), "
        "the period is only 2 clocks, so the I-to-Q delay can only resolve "
        "integer clock values of 0 or 1 -- giving a phase precision of about "
        "180 degrees per count. At these frequencies, the phase measurement is "
        "effectively binary (leading or lagging by roughly 180 degrees). Useful "
        "phase resolution requires signal frequencies well below Nyquist, "
        "typically below ~10 MHz for sub-degree accuracy."
    )

    # ======== 3. PACKET FORMAT ========
    pdf.add_page()
    pdf.section("3", "Packet Format")
    pdf.body(
        "Each completed measurement produces a 12-byte packet on the AXI-Stream "
        "output of adc_stats. Bytes are emitted sequentially (one byte per "
        "clock when the downstream sink is ready)."
    )
    w = [20, 30, 55, 69]
    pdf.table_row(list(zip(w, ["Byte", "Field", "Bits", "Description"])), bold=True, fill=True)
    pdf.table_row(list(zip(w, ["[0]", "Sync", "8'hA7", "Frame synchronization byte"])))
    pdf.table_row(list(zip(w, ["[1]", "Peak+ hi", "peak_pos[11:4]", "Upper 8 bits of positive peak (offset-binary)"])))
    pdf.table_row(list(zip(w, ["[2]", "Pk+lo|Pk-hi", "pk_pos[3:0] || pk_neg[11:8]", "Lower 4 of peak+ concat upper 4 of peak-"])))
    pdf.table_row(list(zip(w, ["[3]", "Peak- lo", "peak_neg[7:0]", "Lower 8 bits of negative peak (offset-binary)"])))
    pdf.table_row(list(zip(w, ["[4]", "IQ delay[31:24]", "iq_delay_sum MSB", "I-to-Q delay sum, byte 3 (big-endian)"])))
    pdf.table_row(list(zip(w, ["[5]", "IQ delay[23:16]", "iq_delay_sum", "I-to-Q delay sum, byte 2"])))
    pdf.table_row(list(zip(w, ["[6]", "IQ delay[15:8]", "iq_delay_sum", "I-to-Q delay sum, byte 1"])))
    pdf.table_row(list(zip(w, ["[7]", "IQ delay[7:0]", "iq_delay_sum LSB", "I-to-Q delay sum, byte 0"])))
    pdf.table_row(list(zip(w, ["[8]", "Clk count hi", "total_clk[15:8]", "Total clock count over N crossings (hi)"])))
    pdf.table_row(list(zip(w, ["[9]", "Clk count lo", "total_clk[7:0]", "Total clock count over N crossings (lo)"])))
    pdf.table_row(list(zip(w, ["[10]", "N cycles hi", "n_cycles[15:8]", "Number of zero crossings used (hi)"])))
    pdf.table_row(list(zip(w, ["[11]", "N cycles lo", "n_cycles[7:0]", "Number of zero crossings used (lo)"])))
    pdf.ln(2)
    pdf.body(
        "The sync byte 0xA7 enables the host to lock onto the frame boundary "
        "within an arbitrary byte stream. The host validates alignment by "
        "checking for another 0xA7 at multiples of 12 bytes ahead."
    )

    # ======== 4. ETHERNET TRANSPORT ========
    pdf.add_page()
    pdf.section("4", "Ethernet Transport Path")

    pdf.subsection("4.1", "Clock Domain Crossing")
    pdf.body(
        "The adc_stats module runs on adc1_clk (the recovered clock from the "
        "AD9627, nominally 125 MHz but asynchronous to the Ethernet clock). "
        "Its AXI-Stream output feeds a Xilinx XPM asynchronous FIFO "
        "(xpm_fifo_async) configured as:"
    )
    pdf.bullet("Write side: adc1_clk domain, 8-bit data width.")
    pdf.bullet("Read side: clk_int (125 MHz Ethernet/system clock), 8-bit data width.")
    pdf.bullet("Depth: 2048 entries with almost-full flow control.")
    pdf.bullet("CDC synchronization: 2-stage flip-flop (CDC_SYNC_STAGES = 2).")
    pdf.body(
        "Backpressure from the FIFO's almost-full flag throttles the adc_stats "
        "output. Since measurement packets are small (12 bytes) and infrequent "
        "relative to the FIFO depth, overflow should not occur under normal "
        "operation."
    )

    pdf.subsection("4.2", "Frame Packetization (Ping-Pong Buffer)")
    pdf.body(
        "On the Ethernet clock side, bytes read from the FIFO enter a "
        "ping-pong buffer (ping_pong_buffer_rx, depth 2048, 8-bit) that "
        "accumulates data until a 512-byte frame is complete. The buffer "
        "then asserts tlast and presents the frame to the Ethernet subsystem "
        "as a single AXI-Stream transaction."
    )
    pdf.body(
        "Each 512-byte UDP payload therefore contains 512/12 = 42 complete "
        "stat packets plus 8 remainder bytes that straddle the next UDP "
        "datagram. The host parser handles this with a persistent byte "
        "buffer across UDP datagrams."
    )

    pdf.subsection("4.3", "UDP/IP Stack and Routing")
    pdf.body(
        "The Ethernet subsystem (based on Alex Forencich's verilog-ethernet) "
        "implements a full UDP/IP stack with ARP, ICMP, and multiple "
        "application ports:"
    )
    pdf.bullet("UDP/1234 -- Echo (diagnostic).")
    pdf.bullet("UDP/10000 -- AXI-Lite register bridge for host control of DAC, LED, DDS, etc.")
    pdf.bullet("UDP/20000 -- Ingress: host-to-FPGA streaming (also latches egress destination).")
    pdf.bullet("UDP/30000 -- Egress: FPGA-to-host streaming (ADC stat packets).")
    pdf.body(
        "When the host sends any UDP packet to port 20000, the Ethernet "
        "subsystem latches the source IP and source port from the received "
        "header. All subsequent egress traffic on port 30000 is addressed "
        "to that latched destination. This 'prime' mechanism eliminates the "
        "need for static host IP configuration in the FPGA bitstream."
    )

    pdf.subsection("4.4", "Network Configuration")
    w2 = [50, 80]
    pdf.table_row(list(zip(w2, ["Parameter", "Value"])), bold=True, fill=True)
    pdf.table_row(list(zip(w2, ["FPGA MAC", "02:00:00:00:00:00"])))
    pdf.table_row(list(zip(w2, ["FPGA IP", "192.168.1.128"])))
    pdf.table_row(list(zip(w2, ["Subnet", "255.255.255.0"])))
    pdf.table_row(list(zip(w2, ["Gateway", "192.168.1.1"])))
    pdf.table_row(list(zip(w2, ["PHY Interface", "1000BASE-T RGMII"])))
    pdf.table_row(list(zip(w2, ["MAC TX/RX FIFO", "4096 bytes each"])))
    pdf.table_row(list(zip(w2, ["Egress payload size", "512 bytes"])))
    pdf.table_row(list(zip(w2, ["UDP TTL", "64"])))

    # ======== 5. HOST ANALYSIS ========
    pdf.add_page()
    pdf.section("5", "Host-Side Analysis (adc_stats_analyzer.py)")

    pdf.subsection("5.1", "Frame Synchronization")
    pdf.body(
        "The analyzer maintains a persistent byte buffer across UDP receives. "
        "It scans for the sync byte 0xA7 and validates alignment by looking "
        "for another 0xA7 at frame boundaries (multiples of 12 bytes ahead, "
        "up to 4 frame lookahead). If no confirming sync is found, the byte "
        "is rejected and the search advances by one byte."
    )

    pdf.subsection("5.2", "Field Decoding")
    pdf.body("After stripping the sync byte, the 11 payload bytes are decoded:")
    pdf.code(
        "peak_pos = (byte[0] << 4) | (byte[1] >> 4)       # 12-bit offset-binary\n"
        "peak_neg = ((byte[1] & 0x0F) << 8) | byte[2]     # 12-bit offset-binary\n"
        "iq_delay = (byte[3]<<24)|(byte[4]<<16)|(byte[5]<<8)|byte[6]  # 32-bit\n"
        "total_clks = (byte[7] << 8) | byte[8]             # 16-bit\n"
        "n_cycles   = (byte[9] << 8) | byte[10]            # 16-bit"
    )

    pdf.subsection("5.3", "Computed Quantities")
    pdf.body("Frequency:")
    pdf.equation("f [MHz] = sample_rate_MSPS * n_cycles / total_clks")
    pdf.body("Phase:")
    pdf.equation("phase [deg] = 360 * iq_delay_sum / total_clks - phase_ref")
    pdf.body(
        "The phase is normalized to [-180, +180] degrees. An optional "
        "phase_reference_deg argument allows zeroing the display at a "
        "known calibration point."
    )
    pdf.body("Voltage (from peak codes):")
    pdf.equation("V = (code - 2048) * (5 / 4096)")

    pdf.subsection("5.4", "Batch Averaging")
    pdf.body(
        "The analyzer accumulates 20 decoded stats before computing and "
        "displaying averaged metrics. This reduces jitter and provides "
        "stable readings. The batch size is configurable in the source. "
        "The curses UI refreshes at a configurable interval (default 1.5 s)."
    )

    pdf.subsection("5.5", "Validation Guards")
    pdf.body("Each decoded stat is checked for physical plausibility:")
    pdf.bullet("n_cycles must be in [4, 30000]. Values outside this range are rejected.")
    pdf.bullet("Frequency must be positive and below Nyquist (62.5 MHz).")
    pdf.bullet("Period per cycle (total_clks / n_cycles) must be >= 2 clocks.")
    pdf.bullet("Stream mismatch detection: if the upper byte of n_cycles equals 0xA7, the parser warns that the FPGA may be using a different packet format.")

    # ======== 6. RESOLUTION SUMMARY ========
    pdf.add_page()
    pdf.section("6", "Resolution Summary")
    w3 = [45, 45, 40, 45]
    pdf.table_row(list(zip(w3, ["Measurement", "FPGA Resolution", "Host Batch (20x)", "Limiting Factor"])), bold=True, fill=True)
    pdf.table_row(list(zip(w3, ["Amplitude", "1 LSB = 1.221 mV", "~0.27 mV", "12-bit ADC quantization"])))
    pdf.table_row(list(zip(w3, ["Frequency", "1/C relative", "same (C >> 1)", "Clock count integer"])))
    pdf.table_row(list(zip(w3, ["Phase", "360/C degrees", "~360/(C*4.5) deg", "Clock count + jitter"])))
    pdf.ln(3)
    pdf.body(
        "C is the total accumulated clock count over the N-crossing window, "
        "typically 8000-50000. The frequency and phase resolutions improve "
        "proportionally to C, which is why the adaptive-N scheme targets "
        "this range."
    )

    pdf.subsection("6.1", "Fundamental Limits")
    pdf.bullet("Amplitude: limited by ADC ENOB (effective number of bits). The AD9627 has a typical ENOB of ~11.0 bits at low frequencies, degrading at higher input frequencies.")
    pdf.bullet("Frequency: limited by clock quantization. For a perfectly stable signal, the error is at most +/-1 count in C, giving the expressions above. Jitter on the ADC clock or input signal adds additional uncertainty.")
    pdf.bullet("Phase: limited by both clock quantization and zero-crossing jitter from noise. As signal frequency approaches Nyquist, the I-to-Q delay granularity becomes coarse (only 0 or 1 clock count per cycle), destroying phase resolution.")
    pdf.bullet("Hysteresis dead zone: signals with amplitude below +/-16 codes (~39 mV peak) will not trigger zero crossings, so frequency and phase measurements will stall.")

    pdf.subsection("6.2", "Recommended Operating Ranges")
    w4 = [55, 55, 65]
    pdf.table_row(list(zip(w4, ["Parameter", "Recommended Range", "Notes"])), bold=True, fill=True)
    pdf.table_row(list(zip(w4, ["Input frequency", "10 kHz to 30 MHz", "Best resolution at lower freqs"])))
    pdf.table_row(list(zip(w4, ["Input amplitude", "> 100 mV pp", "Ensures reliable ZC triggering"])))
    pdf.table_row(list(zip(w4, ["Phase accuracy", "< 10 MHz for < 1 deg", "Coarsens above ~10 MHz"])))

    # ======== 7. USAGE ========
    pdf.add_page()
    pdf.section("7", "Usage")
    pdf.body("Run the analyzer from the project root:")
    pdf.code(
        "python3 python/adc_stats_analyzer.py \\\n"
        "    --bind-port 40000 \\\n"
        "    --fpga-ip 192.168.1.128 \\\n"
        "    --duration-sec 1"
    )
    pdf.body("Key command-line options:")
    pdf.bullet("--sample-rate-msps: ADC sample rate (default 125.0). Must match FPGA clock.")
    pdf.bullet("--phase-reference-deg: Subtract a reference phase for calibrated display.")
    pdf.bullet("--csv-output: Record all batch reports to CSV while analyzing.")
    pdf.bullet("--debug-stats: Print raw decoded hex for the first 10 stats and every 100th.")
    pdf.bullet("--no-prime: Skip the auto-prime packet (useful if FPGA egress already latched).")
    pdf.bullet("--ui-refresh-sec: Curses display refresh interval (default 1.5 s).")

    # Output
    out = "/home/tony/sambashare/school/clean/eee299_KC705/doc/adc_stats_subsystem.pdf"
    pdf.output(out)
    print(f"PDF written to: {out}")


if __name__ == "__main__":
    build()
