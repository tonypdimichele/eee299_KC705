#!/usr/bin/env python3
"""Generate PDF: DAC Subsystem -- Architecture, Configuration, and Host Control."""

from fpdf import FPDF


class DocPDF(FPDF):
    MARGIN = 18
    COL_W = 174  # 210 - 2*18

    def header(self):
        if self.page_no() > 1:
            self.set_font("Helvetica", "I", 8)
            self.cell(0, 5, "EEE299 KC705 -- DAC Subsystem", align="C")
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

    def code(self, text):
        self.set_font("Courier", "", 8.5)
        self.set_fill_color(240, 240, 240)
        for line in text.strip().split("\n"):
            self.cell(self.COL_W, 4.5, "  " + line, fill=True,
                      new_x="LMARGIN", new_y="NEXT")
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
        """Render an equation line centered in monospace."""
        self.set_font("Courier", "B", 10)
        self.cell(self.COL_W, 7, tex, align="C", new_x="LMARGIN", new_y="NEXT")
        self.ln(2)


def build():
    pdf = DocPDF("P", "mm", "A4")
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.set_left_margin(DocPDF.MARGIN)
    pdf.set_right_margin(DocPDF.MARGIN)

    # ================================================================
    #  TITLE PAGE
    # ================================================================
    pdf.add_page()
    pdf.ln(50)
    pdf.set_font("Helvetica", "B", 26)
    pdf.cell(0, 14, "DAC Subsystem", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 16)
    pdf.cell(0, 10, "Architecture, Ethernet Access, and Host Control",
             align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(10)
    pdf.set_font("Helvetica", "", 12)
    pdf.cell(0, 8, "EEE299  --  KC705 FPGA Platform", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 8, "Tony DiMichele", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(20)
    pdf.set_font("Helvetica", "I", 10)
    pdf.cell(0, 6,
             "Design based on Xilinx KC705, AD9781 dual-channel 14-bit DAC,",
             align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6,
             "AD9518-3 clock synthesizer, Alex Forencich verilog-ethernet IP,",
             align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, "and custom RTL.", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(6)
    pdf.set_font("Helvetica", "B", 11)
    pdf.set_text_color(180, 0, 0)
    pdf.cell(0, 7, "NOTE: The IQ / QPSK data path is under active development.",
             align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 7, "Only tone mode (DDS) produces validated DAC output at this time.",
             align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_text_color(0)

    # ================================================================
    #  1. SYSTEM OVERVIEW
    # ================================================================
    pdf.add_page()
    pdf.section("1", "System Overview")
    pdf.body(
        "The DAC subsystem converts digital waveform data into analog "
        "outputs on a dual-channel AD9781 14-bit DAC. The DAC clock "
        "(dac1_clk) runs at 166.667 MHz, and with DDR (double data rate) "
        "output the effective sample rate is 333.333 MSPS. A Raspberry Pi "
        "host communicates with the FPGA over Gigabit Ethernet for both "
        "streaming DAC sample data and register-level control of the DAC, "
        "DDS, and clock synthesizer configuration."
    )
    pdf.set_font("Helvetica", "B", 10)
    pdf.set_text_color(180, 0, 0)
    pdf.multi_cell(pdf.COL_W, 5,
        "Development status: The IQ / baseband QPSK data path is under "
        "active development. The output mux for IQ mode is not yet wired "
        "to the QPSK processing pipeline. Only tone mode (DDS) currently "
        "produces validated analog output.")
    pdf.set_text_color(0)
    pdf.set_font("Helvetica", "", 10)
    pdf.ln(3)
    pdf.body("The end-to-end data path is:")
    pdf.bullet(
        "A Raspberry Pi host transmits UDP datagrams on port 20000 "
        "carrying raw sample data to the FPGA."
    )
    pdf.bullet(
        "The Ethernet subsystem (UDP/IP stack based on Alex Forencich "
        "verilog-ethernet) receives and routes the payload to a ping-pong "
        "buffer for frame reassembly."
    )
    pdf.bullet(
        "An asynchronous FIFO (Xilinx XPM, 2048-deep) crosses the "
        "8-bit data from the 125 MHz Ethernet clock to the 166.667 MHz "
        "DAC clock domain, packing two bytes into 16-bit words."
    )
    pdf.bullet(
        "iq_codec_loop selects between a DDS tone generator (tone mode) "
        "and Ethernet-sourced IQ data, producing 14-bit sample pairs for "
        "DDR launch."
    )
    pdf.bullet(
        "dac_iobuf uses Kintex-7 ODDR primitives in SAME_EDGE mode to "
        "launch 14-bit differential data and a forwarded clock to each "
        "AD9781 channel."
    )
    pdf.body("The control path is:")
    pdf.bullet(
        "The host sends register read/write commands over UDP port 10000, "
        "which a UDP-AXI-Lite bridge converts to AXI4-Lite transactions."
    )
    pdf.bullet(
        "AXI-Lite registers control tone mode selection, DDS phase "
        "increment, DAC DCI delay values, and SPI read-back."
    )
    pdf.bullet(
        "CDC synchronizers carry control signals from the 125 MHz logic "
        "domain to the 50 MHz SPI domain. dac_config runs a startup "
        "state machine that programs the AD9518 clock chip and both "
        "AD9781 DAC channels over SPI."
    )

    # ================================================================
    #  2. STARTUP PROCESS
    # ================================================================
    pdf.add_page()
    pdf.section("2", "Startup Process")

    pdf.subsection("2.1", "MMCM Clocking")
    pdf.body(
        "A mixed-mode clock manager (MMCM) derives all on-chip clocks "
        "from a 200 MHz reference crystal:"
    )
    w_clk = [55, 40, 80]
    pdf.table_row(list(zip(w_clk,
        ["Output", "Frequency", "Purpose"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_clk,
        ["clk_int", "125 MHz", "Ethernet / system logic"])))
    pdf.table_row(list(zip(w_clk,
        ["clk90_int", "125 MHz (90\u00b0)", "RGMII TX clock"])))
    pdf.table_row(list(zip(w_clk,
        ["clk_200mhz", "200 MHz", "IODELAY reference"])))
    pdf.table_row(list(zip(w_clk,
        ["clk_spi", "50 MHz", "DAC SPI configuration"])))
    pdf.table_row(list(zip(w_clk,
        ["clk_250mhz", "250 MHz", "General fast logic"])))
    pdf.table_row(list(zip(w_clk,
        ["clk_500mhz", "500 MHz", "High-speed fabric"])))
    pdf.ln(2)
    pdf.body(
        "The external DAC clocks (dac1_dco, dac2_dco) are source-"
        "synchronous clocks generated by the AD9518 and recovered "
        "on-chip through IBUFDS + BUFG. These run at 166.667 MHz once "
        "the AD9518 PLL locks."
    )

    pdf.subsection("2.2", "Power-On Delay")
    pdf.body(
        "A configurable delay counter (DAC_CFG_DELAY_CYCLES = "
        "400,000,000, or 8 seconds at 50 MHz) holds the SPI "
        "configuration state machine in reset after MMCM lock. This "
        "ensures the DAC board power rails and clock distribution have "
        "fully settled before SPI programming begins. A "
        "DEBUG_SKIP_DAC_SPI_RECONFIG define bypasses this for fast "
        "iteration during development."
    )

    pdf.subsection("2.3", "SPI Configuration State Machine (dac_config)")
    pdf.body(
        "Once the startup delay expires, dac_config executes a "
        "sequential programming sequence through five states:"
    )
    pdf.code(
        "S_IDLE  -->  S_CONFIG_AD9518  -->  S_CONFIG_AD9781_1\n"
        "         -->  S_CONFIG_AD9781_2  -->  S_CONFIG_DONE\n"
        "                                      |<--> S_MANUAL_READ"
    )

    pdf.bullet(
        "S_IDLE: Assert start, enable 3-wire SPI mode and 2-byte "
        "addressing for the AD9518."
    )
    pdf.bullet(
        "S_CONFIG_AD9518: Walk through the 37-entry AD9518 LUT. Each "
        "entry is a {16-bit address, 8-bit data} tuple written via "
        "spi_config. The state machine waits for both done and "
        "pll_locked before advancing."
    )
    pdf.bullet(
        "S_CONFIG_AD9781_1: Switch to 2-wire SPI, 1-byte addressing. "
        "Write the 10-entry AD9781 LUT for DAC channel 1, including "
        "the DCI delay value from register i_dac1_delay."
    )
    pdf.bullet(
        "S_CONFIG_AD9781_2: Repeat the AD9781 LUT for DAC channel 2 "
        "with i_dac2_delay."
    )
    pdf.bullet(
        "S_CONFIG_DONE: Idle. Monitors i_apply for re-configuration "
        "and i_manual_read for register read-back."
    )

    pdf.subsection("2.4", "AD9518 Clock Synthesizer Configuration")
    pdf.body(
        "The AD9518-3 is a multi-output clock synthesizer. The 37-entry "
        "LUT (ad9518_lut_config.v) programs the internal PLL and output "
        "dividers as follows:"
    )
    pdf.bullet("Reference input: 25 MHz crystal.")
    pdf.bullet("PLL parameters: R = 1, Prescaler P = 8, B = 10, A = 0.")
    pdf.equation("f_VCO = (25 MHz / 1) * (8 * 10 + 0) = 2000 MHz")
    pdf.bullet("Divider 0 (OUT0/1): divide-by-2 = 1000 MHz LVPECL.")
    pdf.bullet(
        "Divider 2 (OUT4/5): (4+1)+(4+1) = 10, giving 200 MHz output."
    )
    pdf.bullet(
        "DAC DCO output path: the divider chain produces 166.667 MHz "
        "for the DAC source-synchronous clocks (dac1_dco, dac2_dco)."
    )
    pdf.body(
        "The LUT also includes a soft reset, VCO calibration trigger, "
        "and an update-all-registers command. A termination sentinel "
        "(0xFFFFFF) marks the end of the table."
    )

    pdf.subsection("2.5", "AD9781 DAC Configuration")
    pdf.body(
        "Each AD9781 is programmed with a 10-entry LUT "
        "(ad9781_lut_config.v):"
    )
    w_lut = [25, 30, 120]
    pdf.table_row(list(zip(w_lut,
        ["Index", "Address", "Description"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_lut,
        ["0", "0x02", "Mode register (0x00)"])))
    pdf.table_row(list(zip(w_lut,
        ["1-2", "0x0B-0x0C", "DAC1 full-scale current (both 0x00)"])))
    pdf.table_row(list(zip(w_lut,
        ["3-4", "0x0D-0x0E", "AUXDAC1 (0x00)"])))
    pdf.table_row(list(zip(w_lut,
        ["5-6", "0x0F-0x10", "DAC2 full-scale current (both 0x00)"])))
    pdf.table_row(list(zip(w_lut,
        ["7-8", "0x11-0x12", "AUXDAC2 (0x00)"])))
    pdf.table_row(list(zip(w_lut,
        ["9", "0x05", "DCI delay = delay_value (runtime param)"])))
    pdf.ln(2)
    pdf.body(
        "The full-scale current registers are set to 0x00 (minimum). "
        "The DCI delay (register 0x05) is the primary tuning parameter "
        "for aligning the data-clock relationship at the DAC input; the "
        "default value from the register map is 18."
    )

    pdf.subsection("2.6", "SPI Bus Details")
    pdf.body(
        "A single SPI engine (spi_config) drives a shared bus with "
        "three active-low chip selects:"
    )
    pdf.bullet(
        "clk_spi_ce: AD9518 -- active only during S_CONFIG_AD9518."
    )
    pdf.bullet(
        "dac1_spi_ce: AD9781 channel 1 -- active during "
        "S_CONFIG_AD9781_1 and S_MANUAL_READ."
    )
    pdf.bullet(
        "dac2_spi_ce: AD9781 channel 2 -- active during "
        "S_CONFIG_AD9781_2."
    )
    pdf.body(
        "The SPI clock is derived from clk_spi (50 MHz) with a "
        "divider of 500, producing a ~100 kHz SCLK. The AD9518 uses "
        "3-wire SPI with bidirectional SDIO; the AD9781 uses standard "
        "2-wire SPI (SDIO out, SDO in)."
    )

    # ================================================================
    #  3. ETHERNET ACCESS
    # ================================================================
    pdf.add_page()
    pdf.section("3", "Ethernet Access")

    pdf.subsection("3.1", "Network Configuration")
    w_net = [55, 85]
    pdf.table_row(list(zip(w_net,
        ["Parameter", "Value"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_net,
        ["FPGA MAC", "02:00:00:00:00:00"])))
    pdf.table_row(list(zip(w_net,
        ["FPGA IP", "192.168.1.128"])))
    pdf.table_row(list(zip(w_net,
        ["Subnet mask", "255.255.255.0"])))
    pdf.table_row(list(zip(w_net,
        ["Gateway IP", "192.168.1.1"])))
    pdf.table_row(list(zip(w_net,
        ["PHY interface", "1000BASE-T RGMII"])))
    pdf.table_row(list(zip(w_net,
        ["MAC TX/RX FIFO", "4096 bytes each"])))
    pdf.table_row(list(zip(w_net,
        ["UDP TTL", "64"])))
    pdf.ln(2)

    pdf.subsection("3.2", "UDP Port Map")
    pdf.body(
        "The Ethernet subsystem demultiplexes incoming UDP packets by "
        "destination port:"
    )
    w_port = [30, 50, 95]
    pdf.table_row(list(zip(w_port,
        ["Port", "Direction", "Function"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_port,
        ["1234", "Loopback", "Echo diagnostic"])))
    pdf.table_row(list(zip(w_port,
        ["10000", "Bidirectional", "AXI-Lite register bridge"])))
    pdf.table_row(list(zip(w_port,
        ["20000", "RX (host->FPGA)", "DAC data streaming ingress"])))
    pdf.table_row(list(zip(w_port,
        ["30000", "TX (FPGA->host)", "ADC data streaming egress"])))
    pdf.ln(2)

    pdf.subsection("3.3", "Destination Latching (Prime Mechanism)")
    pdf.body(
        "When the host sends any UDP datagram to port 20000, the "
        "Ethernet subsystem latches the source IP and source UDP port "
        "from that packet's header. All subsequent egress traffic on "
        "port 30000 is addressed to that latched destination. This "
        "eliminates the need for static host IP configuration in the "
        "FPGA bitstream -- the host simply 'primes' the link by sending "
        "a single packet."
    )

    pdf.subsection("3.4", "UDP-AXI-Lite Register Bridge (Port 10000)")
    pdf.body(
        "Register access uses a simple 9-byte request / 9-byte response "
        "protocol over UDP port 10000:"
    )
    pdf.body("Write request: [0x01] [ADDR_3..ADDR_0] [DATA_3..DATA_0]")
    pdf.body("Read request:  [0x00] [ADDR_3..ADDR_0]")
    pdf.body(
        "Response (both): [STATUS] [ADDR_3..ADDR_0] [DATA_3..DATA_0]"
    )
    pdf.body(
        "STATUS is 0x00 for success, 0x01 for error. The bridge module "
        "(udp_axi_lite_bridge) captures the incoming UDP payload, issues "
        "a single-beat AXI4-Lite transaction, and serializes the 9-byte "
        "response back over UDP."
    )

    pdf.subsection("3.5", "DAC Data Ingress Path (Port 20000)")
    pdf.body(
        "Raw sample bytes arrive on UDP port 20000 and pass through "
        "a ping-pong buffer (ping_pong_buffer_tx) for frame reassembly "
        "in the 125 MHz Ethernet clock domain. The reassembled AXI-Stream "
        "data then enters iq_codec_loop via the slave AXI-Stream "
        "interface (i_s_axis_tdata[7:0])."
    )
    pdf.body(
        "Inside iq_codec_loop, an asynchronous FIFO (afifo_wrapper) "
        "crosses the 8-bit stream from 125 MHz to the 166.667 MHz DAC "
        "clock domain, packing two consecutive bytes into a single "
        "16-bit word (eth_data_dac1[15:0]) with an accompanying valid "
        "strobe (eth_data_valid)."
    )

    pdf.subsection("3.6", "Host-Side Tools")
    pdf.body("Two Python utilities support DAC operation:")
    pdf.bullet(
        "dac_pattern_sender.py: Continuous UDP TX to port 20000. Sends "
        "a repeating hex pattern (default 0x55AA) with configurable "
        "--tx-gap-us pacing (default 50 us). Reports throughput stats."
    )
    pdf.bullet(
        "rpi_eth_io.py: General-purpose interactive UDP tool. Binds "
        "port 40000, sends to port 20000. Supports interactive send, "
        "sendhex, and stats commands with TX pacing and RX idle "
        "detection."
    )
    pdf.bullet(
        "regs.py: Register access utility. Provides udp_write(), "
        "udp_read(), trigger_dac_spi_read(), and decode functions "
        "for all DAC control registers."
    )

    # ================================================================
    #  4. REGISTER MAP
    # ================================================================
    pdf.add_page()
    pdf.section("4", "Register Map")
    pdf.body(
        "The AXI-Lite register file (axi_lite_regs.v) exposes a 6-bit "
        "address space. Register addresses are word-aligned (addr[5:2] "
        "selects the register). All registers are 32 bits wide."
    )

    pdf.subsection("4.1", "Register Summary")
    w_reg = [20, 30, 25, 80]
    pdf.table_row(list(zip(w_reg,
        ["Word", "Address", "R/W", "Description"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_reg,
        ["0x0", "0x00", "RW", "General purpose (reg0)"])))
    pdf.table_row(list(zip(w_reg,
        ["0x1", "0x04", "RW", "General purpose (reg1)"])))
    pdf.table_row(list(zip(w_reg,
        ["0x2", "0x08", "RO", "Free-running 32-bit counter (125 MHz)"])))
    pdf.table_row(list(zip(w_reg,
        ["0x3", "0x0C", "RW", "LED control (reg3, bits [7:0])"])))
    pdf.table_row(list(zip(w_reg,
        ["0x4", "0x10", "RW", "DAC control (tone mode, DCI delays)"])))
    pdf.table_row(list(zip(w_reg,
        ["0x5", "0x14", "RW", "DDS phase increment (32-bit)"])))
    pdf.table_row(list(zip(w_reg,
        ["0x6", "0x18", "RW", "DAC SPI read control / status"])))
    pdf.ln(3)

    pdf.subsection("4.2", "reg4_ctrl -- DAC Control (0x10)")
    pdf.body(
        "This register controls tone/IQ mode selection and the DCI "
        "delay for each AD9781 DAC channel. Default value at reset: "
        "0x0001_2121."
    )
    w_bits = [30, 25, 25, 75]
    pdf.table_row(list(zip(w_bits,
        ["Bits", "Reset", "Output", "Description"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_bits,
        ["[0]", "1", "tone_mode_out", "1 = DDS tone mode, 0 = IQ mode"])))
    pdf.table_row(list(zip(w_bits,
        ["[3:1]", "-", "-", "Reserved"])))
    pdf.table_row(list(zip(w_bits,
        ["[8:4]", "0x12 (18)", "dac1_delay[4:0]",
         "AD9781 DAC1 DCI delay (0-31)"])))
    pdf.table_row(list(zip(w_bits,
        ["[11:9]", "-", "-", "Reserved"])))
    pdf.table_row(list(zip(w_bits,
        ["[16:12]", "0x12 (18)", "dac2_delay[4:0]",
         "AD9781 DAC2 DCI delay (0-31)"])))
    pdf.table_row(list(zip(w_bits,
        ["[27:17]", "-", "-", "Reserved"])))
    pdf.table_row(list(zip(w_bits,
        ["[28]", "0", "apply_toggle",
         "Toggle to re-apply DAC SPI config"])))
    pdf.table_row(list(zip(w_bits,
        ["[31:29]", "-", "-", "Reserved"])))
    pdf.ln(2)
    pdf.body(
        "To change DCI delays at runtime: write new values to bits "
        "[8:4] and [16:12], then toggle bit [28]. The toggle edge is "
        "detected across clock domains and triggers a full AD9781 "
        "re-configuration cycle for both DAC channels."
    )

    pdf.subsection("4.3", "reg_tone_pinc -- DDS Phase Increment (0x14)")
    pdf.body(
        "This 32-bit register sets the DDS phase increment for tone "
        "mode. The DDS Compiler IP is configured with a 16-bit phase "
        "accumulator, so only the lower 16 bits are effective. "
        "Default value at reset: 0x0000_13AF."
    )
    pdf.body(
        "The phase increment determines the output frequency according "
        "to:"
    )
    pdf.equation(
        "f_out = f_clk * phase_inc / 2^15"
    )
    pdf.body(
        "where f_clk = 166.667 MHz (the DAC clock) and the divisor is "
        "2^15 = 32768 because the 16th bit is used for sign. With the "
        "default increment of 0x13AF = 5039:"
    )
    pdf.equation(
        "f_out = 166.667e6 * 5039 / 32768 = ~25.64 MHz"
    )

    pdf.subsection("4.4", "reg6_spi_read -- DAC SPI Read Control (0x18)")
    pdf.body("Write side (host -> FPGA):")
    w_spi = [30, 125]
    pdf.table_row(list(zip(w_spi,
        ["Bits", "Description"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_spi,
        ["[7:0]", "AD9781 register address to read"])))
    pdf.table_row(list(zip(w_spi,
        ["[16]", "Toggle bit to trigger read operation"])))
    pdf.ln(2)
    pdf.body("Read-back (FPGA -> host):")
    pdf.table_row(list(zip(w_spi,
        ["Bits", "Description"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_spi,
        ["[7:0]", "Echo of requested address"])))
    pdf.table_row(list(zip(w_spi,
        ["[15:8]", "Read data from AD9781 SPI"])))
    pdf.table_row(list(zip(w_spi,
        ["[16]", "Echo of request toggle"])))
    pdf.table_row(list(zip(w_spi,
        ["[17]", "Busy flag (1 = read in progress)"])))
    pdf.table_row(list(zip(w_spi,
        ["[18]", "Done toggle (flips on completion)"])))
    pdf.ln(2)
    pdf.body(
        "The host triggers a read by writing the target address to "
        "[7:0] and toggling bit [16]. It then polls the register until "
        "busy clears and the done toggle matches, then reads the data "
        "from bits [15:8]. The regs.py utility provides a "
        "trigger_dac_spi_read() helper that automates this sequence."
    )

    # ================================================================
    #  5. DAC DATAPATH (iq_codec_loop)
    # ================================================================
    pdf.add_page()
    pdf.section("5", "DAC Datapath (iq_codec_loop.sv)")
    pdf.body(
        "The iq_codec_loop module is the central DAC datapath. It "
        "bridges the 125 MHz Ethernet domain and the 166.667 MHz DAC "
        "clock domain, selects between operating modes, and pipelines "
        "the 14-bit sample pairs for DDR output."
    )

    pdf.subsection("5.1", "Clock Domain Crossing")
    pdf.body(
        "An afifo_wrapper instance (Xilinx xpm_fifo_async, 2048-deep) "
        "crosses 8-bit AXI-Stream data from clk_int (125 MHz write "
        "side) to i_dac1_clk (166.667 MHz read side). The read port "
        "is configured at 16-bit width, so two consecutive byte writes "
        "produce one 16-bit read. Outputs:"
    )
    pdf.bullet(
        "eth_data_dac1[15:0]: 16-bit packed sample word."
    )
    pdf.bullet(
        "eth_data_valid: Strobe indicating a valid 16-bit word."
    )
    pdf.body(
        "The FIFO has an almost-full flag that propagates backpressure "
        "to the Ethernet-side AXI-Stream interface."
    )

    pdf.subsection("5.2", "Reset Synchronizer")
    pdf.body(
        "The i_rst signal (125 MHz domain) is safely brought into "
        "the i_dac1_clk domain using a 2-stage async-assert / "
        "sync-deassert flip-flop chain. The resulting tone_aresetn "
        "signal (active-low) is used as the reset for both DDS "
        "compiler instances and all DAC-domain logic."
    )
    pdf.code(
        "always @(posedge i_dac1_clk or posedge i_rst)\n"
        "  if (i_rst)  {sync2, sync1} <= 2'b00;\n"
        "  else         {sync2, sync1} <= {sync1, 1'b1};\n"
        "assign tone_aresetn = sync2;"
    )

    pdf.subsection("5.3", "Tone Mode (DDS)")
    pdf.body(
        "When tone_mode = 1 (the default), the DAC output is driven "
        "by a dedicated DDS compiler instance (dds_tone_core). The DDS "
        "runs at i_dac1_clk (166.667 MHz) and produces a continuous "
        "sinusoidal tone."
    )
    pdf.body("The output mapping is:")
    pdf.code(
        "tone_dac1_h = tone_dds_i_s16[13:0]   // I channel -> DAC1 posedge\n"
        "tone_dac1_l = tone_dds_q_s16[13:0]   // Q channel -> DAC1 negedge\n"
        "tone_dac2_h = tone_dds_q_s16[15:2]   // Q channel -> DAC2 posedge\n"
        "tone_dac2_l = tone_dds_q_s16[15:2]   // Q channel -> DAC2 negedge"
    )
    pdf.body(
        "DAC1 receives the I component on the rising edge and Q on "
        "the falling edge of the DDR clock, effectively interleaving "
        "sine and cosine at 333.333 MSPS aggregate. DAC2 receives Q "
        "on both edges."
    )

    pdf.subsection("5.4", "Phase Increment CDC")
    pdf.body(
        "The 32-bit tone_pinc register (125 MHz domain) is crossed "
        "into the 166.667 MHz DAC domain using a two-stage double-flop "
        "synchronizer with a stability check:"
    )
    pdf.bullet(
        "Stage 1 (posedge i_dac1_clk): i_tone_pinc is captured into "
        "tone_pinc_dac1_ff1, then ff2."
    )
    pdf.bullet(
        "Stage 2 (negedge i_dac1_clk): Only when ff1 == ff2 (two "
        "consecutive samples agree) is the value latched into "
        "tone_pinc_dac1_stable[23:0] and fed to the DDS."
    )
    pdf.body(
        "This ensures glitch-free phase increment updates even though "
        "the 32-bit value is not atomically transferred across the "
        "clock boundary."
    )

    pdf.subsection("5.5", "IQ / Baseband QPSK Processing Path (In Development)")
    pdf.body(
        "When tone_mode = 0, a secondary processing path is intended "
        "to transmit baseband IQ data for QPSK modulation. Each "
        "16-bit word from the FIFO carries one I bit and one Q bit "
        "per symbol period. The I and Q channels are independently "
        "BPSK-modulated onto quadrature carriers; when combined at "
        "the wireless front-end, this is equivalent to QPSK."
    )
    pdf.bullet(
        "Each 16-bit word from the FIFO is loaded into iq_word_hold. "
        "A 7-bit phase counter (iq_bit_phase, 0-127) steps through "
        "8 bit pairs with a symbol strobe every 16 clock cycles."
    )
    pdf.bullet(
        "At each symbol strobe, bits from the lower byte map to the "
        "I channel and bits from the upper byte map to the Q channel, "
        "each driven to signed levels (+127 / -128)."
    )
    pdf.bullet(
        "Between symbol strobes, I and Q are driven to zero, "
        "providing natural pulse boundaries for downstream shaping."
    )
    pdf.bullet(
        "A dedicated DDS (dds_iq_core) generates quadrature carriers. "
        "Each channel applies BPSK: bpsk_i = bit ? +carrier_i : "
        "-carrier_i (and likewise for Q). The combination of "
        "independent I and Q BPSK streams is mathematically equivalent "
        "to QPSK when the carriers are in quadrature."
    )
    pdf.bullet(
        "A FIR filter wrapper (fir_filter_wrapper) provides RRC "
        "pulse shaping on the I and Q streams."
    )
    pdf.set_font("Helvetica", "B", 10)
    pdf.set_text_color(180, 0, 0)
    pdf.multi_cell(pdf.COL_W, 5,
        "Note: In the current RTL, the output mux selects tone DDS "
        "data when tone_mode=1 and hardcoded constants when "
        "tone_mode=0. The QPSK path outputs are instantiated but "
        "not yet wired to the DAC output mux. This path is under "
        "active development.")
    pdf.set_text_color(0)
    pdf.set_font("Helvetica", "", 10)
    pdf.ln(2)

    pdf.subsection("5.6", "Output Mux and Pipeline")
    pdf.body("The 14-bit DAC sample pairs are selected by tone_mode:")
    pdf.code(
        "dac1_h_mux = tone_mode ? tone_dac1_h : 1'b0;\n"
        "dac1_l_mux = tone_mode ? tone_dac1_l : 1'b1;\n"
        "dac2_h_mux = DAC_PARK_MIDSCALE;  // always 0\n"
        "dac2_l_mux = DAC_PARK_MIDSCALE;  // always 0"
    )
    pdf.body(
        "DAC2 is always parked at midscale (signed zero) regardless "
        "of the operating mode."
    )
    pdf.body(
        "The mux outputs pass through a two-stage negedge-clocked "
        "pipeline register chain before assignment to the module "
        "outputs. Clocking on negedge provides a full half-cycle of "
        "setup time for the downstream SAME_EDGE ODDR primitives "
        "(which capture D1/D2 on posedge), ensuring reliable timing "
        "at 166.667 MHz."
    )

    pdf.subsection("5.7", "AXI-Stream Loopback (Codec Echo)")
    pdf.body(
        "A parallel logic path in the 125 MHz domain XOR-encodes "
        "each received byte with a mask (0x93), processes the encoded "
        "byte through a symbol mapper (fl9781_tx_wrapper), then XOR-"
        "decodes and echoes the byte on the master AXI-Stream "
        "interface. In the current top-level integration, the echo "
        "output is tied to tready=1 (output discarded)."
    )

    # ================================================================
    #  6. DDS COMPILER BEHAVIOR
    # ================================================================
    pdf.add_page()
    pdf.section("6", "DDS Compiler Behavior")

    pdf.subsection("6.1", "IP Core Configuration")
    pdf.body(
        "Two instances of the Xilinx DDS Compiler IP (dds_compiler_0) "
        "are used within iq_codec_loop:"
    )
    w_dds = [50, 55, 70]
    pdf.table_row(list(zip(w_dds,
        ["Instance", "Clock", "Purpose"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_dds,
        ["dds_tone_core", "i_dac1_clk (166.667 MHz)",
         "Tone mode output"])))
    pdf.table_row(list(zip(w_dds,
        ["dds_iq_core", "i_dac1_clk (166.667 MHz)",
         "QPSK carrier generation"])))
    pdf.ln(2)
    pdf.body(
        "Both instances share the same IP configuration: 16-bit phase "
        "accumulator width, 16-bit output width, producing a 32-bit "
        "output word with I (sine) in [15:0] and Q (cosine) in "
        "[31:16]. Although the RTL wires 24 bits to s_axis_phase_tdata, "
        "the DDS Compiler IP is configured for 16-bit phase increment "
        "and ignores the upper bits."
    )

    pdf.subsection("6.2", "Interface Signals")
    pdf.code(
        "dds_compiler_0 dds_tone_core (\n"
        "    .aclk(i_dac1_clk),\n"
        "    .aresetn(tone_aresetn),\n"
        "    .s_axis_phase_tvalid(tone_aresetn),\n"
        "    .s_axis_phase_tdata(tone_pinc_dac1_stable),\n"
        "    .m_axis_data_tvalid(tone_dds_tvalid),\n"
        "    .m_axis_data_tdata(tone_dds_tdata)\n"
        ");"
    )
    pdf.body(
        "The phase input port (s_axis_phase_tdata) is driven "
        "continuously with the stable phase increment value, and "
        "tvalid is tied to aresetn so the DDS free-runs whenever "
        "not in reset. A new output sample is produced every clock "
        "cycle at 166.667 MHz."
    )

    pdf.subsection("6.3", "Frequency Calculation")
    pdf.body(
        "The DDS output frequency is determined by the 16-bit phase "
        "accumulator and the clock rate:"
    )
    pdf.equation(
        "f_out = f_clk * phase_inc / 2^15"
    )
    pdf.body(
        "The divisor is 2^15 = 32768 because the 16th bit encodes "
        "the sign (+/-). The frequency resolution (minimum step) is:"
    )
    pdf.equation(
        "f_res = f_clk / 2^15 = 166.667e6 / 32768 = ~5086 Hz"
    )
    pdf.body("Representative frequency settings:")
    w_freq = [45, 45, 45, 40]
    pdf.table_row(list(zip(w_freq,
        ["Target freq", "phase_inc (dec)", "phase_inc (hex)",
         "Actual freq"])), bold=True, fill=True)
    pdf.table_row(list(zip(w_freq,
        ["~25.6 MHz", "5039", "0x13AF", "25.64 MHz"])))
    pdf.table_row(list(zip(w_freq,
        ["1 MHz", "197", "0x00C5", "~1.002 MHz"])))
    pdf.table_row(list(zip(w_freq,
        ["10 MHz", "1966", "0x07AE", "~9.999 MHz"])))
    pdf.table_row(list(zip(w_freq,
        ["50 MHz", "9830", "0x2666", "~49.999 MHz"])))
    pdf.table_row(list(zip(w_freq,
        ["62.5 MHz", "12288", "0x3000", "62.500 MHz"])))
    pdf.table_row(list(zip(w_freq,
        ["83.3 MHz", "16384", "0x4000", "83.333 MHz"])))
    pdf.ln(2)
    pdf.body(
        "The theoretical maximum output frequency (Nyquist) is "
        "83.333 MHz for the 166.667 MHz DAC clock. However, in this "
        "system the practical upper limit is 62.5 MHz, constrained "
        "by the ADC sampling rate of 125 MSPS on the receive side. "
        "The Xilinx DDS Compiler uses a phase accumulator with "
        "truncation to address the sine/cosine LUT, producing SFDR "
        "typically > 90 dBc."
    )

    pdf.subsection("6.4", "DDS Output Bit Mapping")
    pdf.body(
        "The 32-bit DDS output word is split into two 16-bit signed "
        "values. The lower 14 bits of each are used for the 14-bit "
        "DAC inputs. In tone mode:"
    )
    pdf.bullet(
        "DAC1_H (posedge): DDS I channel [13:0] -- sine."
    )
    pdf.bullet(
        "DAC1_L (negedge): DDS Q channel [13:0] -- cosine."
    )
    pdf.body(
        "For the IQ carrier DDS (used in the QPSK path, under "
        "development), the full 16-bit values are used for BPSK "
        "multiplication on each quadrature channel before saturation "
        "to 14 bits via a sat_s16_to_s14 function that clamps to "
        "[-8192, +8191]."
    )

    # ================================================================
    #  7. IO BUFFER (dac_iobuf)
    # ================================================================
    pdf.add_page()
    pdf.section("7", "IO Buffer (dac_iobuf.v)")

    pdf.subsection("7.1", "Overview")
    pdf.body(
        "The dac_iobuf module handles all physical IO for both DAC "
        "channels. It performs three functions: differential clock "
        "recovery from the AD9518, DDR data launch via ODDR "
        "primitives, and differential signaling via OBUFDS."
    )

    pdf.subsection("7.2", "Clock Recovery")
    pdf.body(
        "Each DAC channel receives a source-synchronous clock pair "
        "(dac*_dco_p/n) from the AD9518. These are converted to "
        "single-ended signals and buffered:"
    )
    pdf.code(
        "IBUFDS  -->  dac*_dco_ibuf  -->  BUFG  -->  dac*_dco_buf"
    )
    pdf.body(
        "The resulting dac1_dco_buf and dac2_dco_buf clocks "
        "(166.667 MHz) are distributed to the fabric as the "
        "DAC-domain clocks."
    )

    pdf.subsection("7.3", "Clock Forwarding")
    pdf.body(
        "A DCI (data clock input) is forwarded back to each AD9781 "
        "as a source-synchronous clock. This is generated by an ODDR "
        "primitive with D1=1, D2=0, creating a clock waveform "
        "phase-aligned to the recovered DCO:"
    )
    pdf.code(
        "ODDR(SAME_EDGE, D1=1, D2=0, C=dac*_dco_buf)\n"
        "  --> dac*_dci --> OBUFDS --> dac*_dci_p/n"
    )

    pdf.subsection("7.4", "DDR Data Launch")
    pdf.body(
        "Each of the 14 data bits per DAC channel is launched through "
        "an individual ODDR primitive in SAME_EDGE mode:"
    )
    pdf.code(
        "ODDR #(.DDR_CLK_EDGE(\"SAME_EDGE\")) dac1_data_oddr (\n"
        "    .Q(dac1_data[i]),\n"
        "    .C(dac1_dco_buf),\n"
        "    .D1(dac1_h[i]),    // posedge data\n"
        "    .D2(dac1_l[i]),    // negedge data\n"
        "    .CE(1'b1), .R(1'b0), .S(1'b0)\n"
        ");"
    )
    pdf.body(
        "SAME_EDGE mode means both D1 and D2 are captured on the "
        "rising edge of C, then D1 is output on the rising edge and "
        "D2 on the falling edge. This matches the negedge pipeline "
        "register strategy in iq_codec_loop, which presents both H "
        "and L samples stable by the rising edge."
    )

    pdf.subsection("7.5", "Differential Output Buffers")
    pdf.body(
        "Each ODDR output is routed through an OBUFDS to produce "
        "differential LVDS pairs:"
    )
    pdf.code(
        "OBUFDS dac1_data_obufds (\n"
        "    .O  (dac1_data_p[i]),\n"
        "    .OB (dac1_data_n[i]),\n"
        "    .I  (dac1_data[i])\n"
        ");"
    )
    pdf.body(
        "In total, each DAC channel uses: 1 IBUFDS + 1 BUFG (clock "
        "recovery), 1 ODDR + 1 OBUFDS (clock forwarding), and "
        "14 x (ODDR + OBUFDS) for data -- 30 IO primitives per "
        "channel, 60 total."
    )

    # ================================================================
    #  8. TIMING AND PIPELINE SUMMARY
    # ================================================================
    pdf.add_page()
    pdf.section("8", "Timing and Pipeline Summary")

    pdf.body(
        "The end-to-end pipeline from Ethernet RX to DAC output "
        "involves multiple clock domain crossings and pipeline stages:"
    )

    w_pipe = [25, 40, 40, 70]
    pdf.table_row(list(zip(w_pipe,
        ["Stage", "Clock Domain", "Latency", "Description"])),
        bold=True, fill=True)
    pdf.table_row(list(zip(w_pipe,
        ["1", "125 MHz", "Variable",
         "UDP RX + ping-pong buffer"])))
    pdf.table_row(list(zip(w_pipe,
        ["2", "125 -> 166.667 MHz", "~4-6 cycles",
         "Async FIFO (CDC)"])))
    pdf.table_row(list(zip(w_pipe,
        ["3", "166.667 MHz", "0 cycles",
         "DDS / mux (combinational)"])))
    pdf.table_row(list(zip(w_pipe,
        ["4", "166.667 MHz (neg)", "2 cycles",
         "Negedge pipeline FFs"])))
    pdf.table_row(list(zip(w_pipe,
        ["5", "166.667 MHz", "1 cycle",
         "ODDR (SAME_EDGE)"])))
    pdf.table_row(list(zip(w_pipe,
        ["6", "Analog", "~1 ns",
         "OBUFDS + PCB trace"])))
    pdf.ln(3)

    pdf.body(
        "In tone mode, the DDS runs independently and the pipeline "
        "latency from phase increment change to DAC output is "
        "approximately 4 DAC clock cycles (24 ns at 166.667 MHz) "
        "due to the DDS internal pipeline plus the negedge FF chain."
    )

    pdf.body(
        "The total latency from a UDP packet arriving at the Ethernet "
        "MAC to the corresponding sample appearing at the DAC output "
        "is dominated by the asynchronous FIFO and ping-pong buffer, "
        "typically on the order of a few microseconds."
    )

    # ================================================================
    #  9. USAGE EXAMPLES
    # ================================================================
    pdf.add_page()
    pdf.section("9", "Usage Examples")

    pdf.subsection("9.1", "Setting Tone Frequency")
    pdf.body(
        "The Raspberry Pi has shell aliases 'rr' (read register) and "
        "'wr' (write register) for quick access. To set a 1 MHz tone:"
    )
    pdf.code(
        "rr 0x10              # Verify current DAC control value\n"
        "wr 0x10 0x00012121   # Ensure tone mode (bit 0 = 1), default delays\n"
        "wr 0x14 0x000000C5   # phase_inc = 197 -> ~1.0 MHz\n"
        "                     # f = 166.667e6 * 197 / 2^15"
    )

    pdf.subsection("9.2", "Changing DCI Delay")
    pdf.body(
        "To adjust the DAC1 DCI delay to 20 and DAC2 to 15, then "
        "apply:"
    )
    pdf.code(
        "# reg4_ctrl: tone_mode=1, dac1_delay=20, dac2_delay=15\n"
        "# Bit layout: [28]=toggle, [16:12]=15, [8:4]=20, [0]=1\n"
        "wr 0x10 0x1000F141   # toggle bit [28] = 1 to trigger re-config"
    )

    pdf.subsection("9.3", "Reading DAC SPI Register")
    pdf.body(
        "To read back AD9781 register 0x05 (DCI delay):"
    )
    pdf.code(
        "from python.regs import trigger_dac_spi_read\n"
        "\n"
        "data = trigger_dac_spi_read('192.168.1.128', 10000, 0x05)\n"
        "print(f'DCI delay register = 0x{data:02X}')"
    )

    pdf.subsection("9.4", "Streaming DAC Data")
    pdf.body(
        "To send a repeating pattern to the DAC:"
    )
    pdf.code(
        "python3 python/dac_pattern_sender.py \\\n"
        "    --fpga-ip 192.168.1.128 \\\n"
        "    --pattern 55AA \\\n"
        "    --tx-gap-us 50 \\\n"
        "    --duration-sec 1"
    )

    pdf.subsection("9.5", "Quick Register Reference")
    pdf.body("Common register operations using the rr/wr aliases:")
    pdf.code(
        "rr 0x08        # Read free-running counter (link test)\n"
        "rr 0x10        # Read DAC control register\n"
        "rr 0x14        # Read current DDS phase increment\n"
        "rr 0x18        # Read DAC SPI read status\n"
        "wr 0x0C 0xFF   # Set all LEDs on\n"
        "wr 0x14 0x07AE # Set DDS to ~10 MHz"
    )

    # Output
    out = "/home/tony/sambashare/school/clean/eee299_KC705/doc/dac_subsystem.pdf"
    pdf.output(out)
    print(f"PDF written to: {out}")


if __name__ == "__main__":
    build()
