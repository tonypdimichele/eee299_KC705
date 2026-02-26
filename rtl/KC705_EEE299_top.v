/*
 * KC705 EEE299 top-level design
 *
 * The Ethernet subsystem in this design is based on Alex Forencich's
 * verilog-ethernet KC705 implementation.
 *
 * System integration and application design by Tony DiMichele.
 *
 * Project intent:
 * - Implement a streaming I/Q modulation and demodulation scheme
 * - Support power and beam alignment workflows
 * - Enable path loss measurement and related channel characterization
 * - Interface with a Sivers EVK06002 mmWave kit
 *
 * Host/control path:
 * - A Raspberry Pi connects to the KC705 via UDP over Ethernet
 */

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA top-level module
 */
module KC705_EEE299_top (
    /*
     * Clock: 200MHz
     * Reset: Push button, active high
     */
    input  wire       CLK_200MHZ_P,
    input  wire       CLK_200MHZ_N,
    input  wire       RESET,

    /*
     * GPIO
     */
    input  wire       BTNU,
    input  wire       BTNL,
    input  wire       BTND,
    input  wire       BTNR,
    input  wire       BTNC,
    input  wire [3:0] SW,
    output wire [7:0] LED,

    /*
     * Ethernet: 1000BASE-T RGMII
     */
    input  wire       PHY_RX_CLK,
    input  wire [3:0] PHY_RXD,
    input  wire       PHY_RX_CTL,
    output wire       PHY_TX_CLK,
    output wire [3:0] PHY_TXD,
    output wire       PHY_TX_CTL,
    output wire       PHY_RESET_N,
    input  wire       PHY_INT_N,

    /*
     * UART: 500000 bps, 8N1
     */
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire       UART_RTS,
    input  wire       UART_CTS,

    /*
     * FMC DAC
     */
    output wire       FMC_LPC_LA16_P,
    output wire       FMC_LPC_LA16_N,
    output wire       FMC_LPC_LA14_P,
    output wire       FMC_LPC_LA14_N
);

// Clock and reset

wire clk_200mhz_ibufg;

// Internal 125 MHz clock
wire clk_mmcm_out;
wire clk_int;
wire clk90_mmcm_out;
wire clk90_int;
wire rst_int;

wire clk_200mhz_mmcm_out;
wire clk_200mhz_int;

wire mmcm_rst = RESET;
wire mmcm_locked;
wire mmcm_clkfb;

IBUFGDS
clk_200mhz_ibufgds_inst(
    .I(CLK_200MHZ_P),
    .IB(CLK_200MHZ_N),
    .O(clk_200mhz_ibufg)
);

// MMCM instance
// 200 MHz in, 125 MHz out
// PFD range: 10 MHz to 500 MHz
// VCO range: 600 MHz to 1440 MHz
// M = 5, D = 1 sets Fvco = 1000 MHz (in range)
// Divide by 8 to get output frequency of 125 MHz
// Need two 125 MHz outputs with 90 degree offset
// Also need 200 MHz out for IODELAY
// 1000 / 5 = 200 MHz
MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKOUT0_DIVIDE_F(8),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    .CLKOUT1_DIVIDE(8),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(90),
    .CLKOUT2_DIVIDE(5),
    .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT2_PHASE(0),
    .CLKOUT3_DIVIDE(1),
    .CLKOUT3_DUTY_CYCLE(0.5),
    .CLKOUT3_PHASE(0),
    .CLKOUT4_DIVIDE(1),
    .CLKOUT4_DUTY_CYCLE(0.5),
    .CLKOUT4_PHASE(0),
    .CLKOUT5_DIVIDE(1),
    .CLKOUT5_DUTY_CYCLE(0.5),
    .CLKOUT5_PHASE(0),
    .CLKOUT6_DIVIDE(1),
    .CLKOUT6_DUTY_CYCLE(0.5),
    .CLKOUT6_PHASE(0),
    .CLKFBOUT_MULT_F(5),
    .CLKFBOUT_PHASE(0),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.010),
    .CLKIN1_PERIOD(5.0),
    .STARTUP_WAIT("FALSE"),
    .CLKOUT4_CASCADE("FALSE")
)
clk_mmcm_inst (
    .CLKIN1(clk_200mhz_ibufg),
    .CLKFBIN(mmcm_clkfb),
    .RST(mmcm_rst),
    .PWRDWN(1'b0),
    .CLKOUT0(clk_mmcm_out),
    .CLKOUT0B(),
    .CLKOUT1(clk90_mmcm_out),
    .CLKOUT1B(),
    .CLKOUT2(clk_200mhz_mmcm_out),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6(),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    .LOCKED(mmcm_locked)
);

BUFG
clk_bufg_inst (
    .I(clk_mmcm_out),
    .O(clk_int)
);

BUFG
clk90_bufg_inst (
    .I(clk90_mmcm_out),
    .O(clk90_int)
);

BUFG
clk_200mhz_bufg_inst (
    .I(clk_200mhz_mmcm_out),
    .O(clk_200mhz_int)
);

sync_reset #(
    .N(4)
)
sync_reset_inst (
    .clk(clk_int),
    .rst(~mmcm_locked),
    .out(rst_int)
);

// GPIO
wire btnu_int;
wire btnl_int;
wire btnd_int;
wire btnr_int;
wire btnc_int;
wire [3:0] sw_int;

debounce_switch #(
    .WIDTH(9),
    .N(4),
    .RATE(125000)
)
debounce_switch_inst (
    .clk(clk_int),
    .rst(rst_int),
    .in({BTNU,
        BTNL,
        BTND,
        BTNR,
        BTNC,
        SW}),
    .out({btnu_int,
        btnl_int,
        btnd_int,
        btnr_int,
        btnc_int,
        sw_int})
);

wire uart_rxd_int;
wire uart_cts_int;

sync_signal #(
    .WIDTH(2),
    .N(2)
)
sync_signal_inst (
    .clk(clk_int),
    .in({UART_RXD, UART_CTS}),
    .out({uart_rxd_int, uart_cts_int})
);

// IODELAY elements for RGMII interface to PHY
wire [3:0] phy_rxd_delay;
wire       phy_rx_ctl_delay;

IDELAYCTRL
idelayctrl_inst (
    .REFCLK(clk_200mhz_int),
    .RST(rst_int),
    .RDY()
);

IDELAYE2 #(
    .IDELAY_TYPE("FIXED")
)
phy_rxd_idelay_0 (
    .IDATAIN(PHY_RXD[0]),
    .DATAOUT(phy_rxd_delay[0]),
    .DATAIN(1'b0),
    .C(1'b0),
    .CE(1'b0),
    .INC(1'b0),
    .CINVCTRL(1'b0),
    .CNTVALUEIN(5'd0),
    .CNTVALUEOUT(),
    .LD(1'b0),
    .LDPIPEEN(1'b0),
    .REGRST(1'b0)
);

IDELAYE2 #(
    .IDELAY_TYPE("FIXED")
)
phy_rxd_idelay_1 (
    .IDATAIN(PHY_RXD[1]),
    .DATAOUT(phy_rxd_delay[1]),
    .DATAIN(1'b0),
    .C(1'b0),
    .CE(1'b0),
    .INC(1'b0),
    .CINVCTRL(1'b0),
    .CNTVALUEIN(5'd0),
    .CNTVALUEOUT(),
    .LD(1'b0),
    .LDPIPEEN(1'b0),
    .REGRST(1'b0)
);

IDELAYE2 #(
    .IDELAY_TYPE("FIXED")
)
phy_rxd_idelay_2 (
    .IDATAIN(PHY_RXD[2]),
    .DATAOUT(phy_rxd_delay[2]),
    .DATAIN(1'b0),
    .C(1'b0),
    .CE(1'b0),
    .INC(1'b0),
    .CINVCTRL(1'b0),
    .CNTVALUEIN(5'd0),
    .CNTVALUEOUT(),
    .LD(1'b0),
    .LDPIPEEN(1'b0),
    .REGRST(1'b0)
);

IDELAYE2 #(
    .IDELAY_TYPE("FIXED")
)
phy_rxd_idelay_3 (
    .IDATAIN(PHY_RXD[3]),
    .DATAOUT(phy_rxd_delay[3]),
    .DATAIN(1'b0),
    .C(1'b0),
    .CE(1'b0),
    .INC(1'b0),
    .CINVCTRL(1'b0),
    .CNTVALUEIN(5'd0),
    .CNTVALUEOUT(),
    .LD(1'b0),
    .LDPIPEEN(1'b0),
    .REGRST(1'b0)
);

IDELAYE2 #(
    .IDELAY_TYPE("FIXED")
)
phy_rx_ctl_idelay (
    .IDATAIN(PHY_RX_CTL),
    .DATAOUT(phy_rx_ctl_delay),
    .DATAIN(1'b0),
    .C(1'b0),
    .CE(1'b0),
    .INC(1'b0),
    .CINVCTRL(1'b0),
    .CNTVALUEIN(5'd0),
    .CNTVALUEOUT(),
    .LD(1'b0),
    .LDPIPEEN(1'b0),
    .REGRST(1'b0)
);

// Ethernet data path in this integration is based on Alex Forencich's
// verilog-ethernet KC705 design. This system is adapted for streaming I/Q
// modulation/demodulation experiments with Sivers EVK06002 and UDP host
// connectivity from a Raspberry Pi.
fpga_core #(
    .TARGET("XILINX")
)
core_inst (
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    .clk(clk_int),
    .clk90(clk90_int),
    .rst(rst_int),
    /*
     * GPIO
     */
    .btnu(btnu_int),
    .btnl(btnl_int),
    .btnd(btnd_int),
    .btnr(btnr_int),
    .btnc(btnc_int),
    .sw(sw_int),
    .led(LED),
    /*
     * Ethernet: 1000BASE-T RGMII
     */
    .phy_rx_clk(PHY_RX_CLK),
    .phy_rxd(phy_rxd_delay),
    .phy_rx_ctl(phy_rx_ctl_delay),
    .phy_tx_clk(PHY_TX_CLK),
    .phy_txd(PHY_TXD),
    .phy_tx_ctl(PHY_TX_CTL),
    .phy_reset_n(PHY_RESET_N),
    .phy_int_n(PHY_INT_N),
    /*
     * UART: 115200 bps, 8N1
     */
    .uart_rxd(uart_rxd_int),
    .uart_txd(UART_TXD),
    .uart_rts(UART_RTS),
    .uart_cts(uart_cts_int)
);

wire tvalid_dummy;
wire [31:0] tdata_dummy;
wire tvalid_phase_dummy;
wire [15:0] tdata_phase_dummy;

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
 dds_compiler_0 dds_tx_side (
  .aclk(clk_mmcm_out),                                // input wire aclk
  .aresetn(rst_int),                          // input wire aresetn
  .m_axis_data_tvalid(tvalid_dummy),    // output wire m_axis_data_tvalid
  .m_axis_data_tdata(tdata_dummy),      // output wire [31 : 0] m_axis_data_tdata
  .m_axis_phase_tvalid(tvalid_phase_dummy),  // output wire m_axis_phase_tvalid
  .m_axis_phase_tdata(tdata_phase_dummy)    // output wire [15 : 0] m_axis_phase_tdata
); 



endmodule

`resetall
