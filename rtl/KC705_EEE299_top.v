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

	//spi interface
	output wire           CLK_SPI_CE,
	output wire           DAC1_SPI_CE,
	output wire           DAC2_SPI_CE,
	output wire           SPI_SCLK,
	inout wire            SPI_SDIO,
	input wire            SPI_SDO,

	//dac input clock from ad9518
	input wire		      DAC1_DCO_P,
	input wire   		  DAC1_DCO_N,
	input wire		      DAC2_DCO_P,
	input wire   		  DAC2_DCO_N,
	//dac1 signals
	output wire            DAC1_DCI_P,	//dac output clock p
	output wire            DAC1_DCI_N,	//dac output clock n
	output wire[13:0]      DAC1_DATA_P, //dac output data p
	output wire[13:0]      DAC1_DATA_N, //dac output data n
	//dac2 signals
	output wire            DAC2_DCI_P,	//dac output clock p
	output wire            DAC2_DCI_N,  //dac output clock n
	output wire[13:0]      DAC2_DATA_P, //dac output data p
	output wire[13:0]      DAC2_DATA_N,  //dac output data n

    output wire            USER_SMA_GPIO_P


);

// Clock and reset

wire clk_200mhz_ibufg;

// Internal 125 MHz clock
wire clk_mmcm_out;
wire clk_int;
wire clk90_mmcm_out;
wire clk90_int;
wire rst_int;

wire clk_200mhz_mmcm_out, clk_50mhz_mmcm_out, clk_250mhz_mmcm_out, clk_500mhz_mmcm_out, clk_spi;
wire clk_200mhz_int;
wire clk_250mhz_int;
wire clk_500mhz_int;

wire mmcm_rst = RESET;
wire mmcm_locked;
wire mmcm_clkfb;
localparam [31:0] DAC_CFG_DELAY_CYCLES = 32'd400000000; // 8 s at 50 MHz
localparam DEBUG_SKIP_DAC_SPI_RECONFIG = 1'b0;
reg [31:0] dac_cfg_delay_cnt;
reg delay_done;

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
    .CLKOUT3_DIVIDE(4),
    .CLKOUT3_DUTY_CYCLE(0.5),
    .CLKOUT3_PHASE(0),
    .CLKOUT4_DIVIDE(4),
    .CLKOUT4_DUTY_CYCLE(0.5),
    .CLKOUT4_PHASE(0),
    .CLKOUT5_DIVIDE(3),
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
    .CLKOUT3(clk_50mhz_mmcm_out),
    .CLKOUT3B(),
    .CLKOUT4(clk_250mhz_mmcm_out),
    .CLKOUT5(clk_500mhz_mmcm_out),
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

BUFG
clk_50mhz_bufg_inst (
    .I(clk_50mhz_mmcm_out),
    .O(clk_spi)
);

BUFG
clk_250mhz_bufg_inst (
    .I(clk_250mhz_mmcm_out),
    .O(clk_250mhz_int)
);

BUFG
clk_500mhz_bufg_inst (
    .I(clk_500mhz_mmcm_out),
    .O(clk_500mhz_int)
);

always @(posedge clk_spi) begin
    if (!mmcm_locked) begin
        dac_cfg_delay_cnt <= 32'd0;
        delay_done <= 1'b0;
    end else if (!delay_done) begin
        if (dac_cfg_delay_cnt >= DAC_CFG_DELAY_CYCLES-1) begin
            delay_done <= 1'b1;
        end else begin
            dac_cfg_delay_cnt <= dac_cfg_delay_cnt + 1'b1;
        end
    end
end

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

// This system is adapted for streaming I/Q
// modulation/demodulation experiments with Sivers EVK06002 and UDP host
// connectivity from a Raspberry Pi.
wire [7:0] rpi_ingress_tdata;
wire       rpi_ingress_tvalid;
wire       rpi_ingress_tready;
wire       rpi_ingress_tlast;
wire [7:0] tx_ring_buffer_tdata;
wire       tx_ring_buffer_tvalid;
wire       tx_ring_buffer_tready;
wire       tx_ring_buffer_tlast;
wire [7:0] iq_codec_tdata;
wire       iq_codec_tvalid;
wire       iq_codec_tready;
wire       iq_codec_tlast;
wire       iq_dac_sample_valid;
wire [13:0] iq_dac1_h;
wire [13:0] iq_dac1_l;
wire [13:0] iq_dac2_h;
wire [13:0] iq_dac2_l;
wire [13:0] dac1_h;
wire [13:0] dac1_l;
wire [13:0] dac2_h;
wire [13:0] dac2_l;
wire       dac1_dco_buf;
wire       dac2_dco_buf;
wire       dac_tone_mode;
wire [31:0] tone_pinc;
wire [4:0] dac1_delay_reg;
wire [4:0] dac2_delay_reg;
wire       dac_delay_apply_toggle_reg;
wire [7:0] dac_spi_read_addr_reg;
wire       dac_spi_read_toggle_reg;
wire [11:0] dac_ctrl_sync;
wire [4:0] dac1_delay_spi;
wire [4:0] dac2_delay_spi;
wire       dac_delay_apply_toggle_spi;
reg        dac_delay_apply_toggle_spi_d;
wire       dac_delay_apply_pulse_spi;
wire [8:0] dac_spi_read_ctrl_sync;
wire [7:0] dac_spi_read_addr_spi;
wire       dac_spi_read_toggle_spi;
reg        dac_spi_read_toggle_spi_d;
wire       dac_spi_read_pulse_spi;
wire [7:0] dac_spi_read_data_spi;
wire       dac_spi_read_done_toggle_spi;
wire       dac_spi_read_busy_spi;
wire [9:0] dac_spi_read_status_sync;
wire [7:0] dac_spi_read_data_reg;
wire       dac_spi_read_done_toggle_reg;
wire       dac_spi_read_busy_reg;
wire [7:0] rx_ring_buffer_tdata;
wire       rx_ring_buffer_tvalid;
wire       rx_ring_buffer_tready;
wire       rx_ring_buffer_tlast;

ethernet_subsystem #(
    .TARGET("XILINX")
)
ethernet_subsystem (
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
    .uart_cts(uart_cts_int),
    .reg_tone_mode(dac_tone_mode),
    .o_reg_tone_pinc(tone_pinc),
    .reg_dac1_delay(dac1_delay_reg),
    .reg_dac2_delay(dac2_delay_reg),
    .reg_dac_delay_apply_toggle(dac_delay_apply_toggle_reg),
    .reg_dac_spi_read_addr(dac_spi_read_addr_reg),
    .reg_dac_spi_read_toggle(dac_spi_read_toggle_reg),
    .dac_spi_read_data(dac_spi_read_data_reg),
    .dac_spi_read_busy(dac_spi_read_busy_reg),
    .dac_spi_read_done_toggle(dac_spi_read_done_toggle_reg),

    .m_axis_rpi_rx_tdata(rpi_ingress_tdata),
    .m_axis_rpi_rx_tvalid(rpi_ingress_tvalid),
    .m_axis_rpi_rx_tready(rpi_ingress_tready),
    .m_axis_rpi_rx_tlast(rpi_ingress_tlast),
    .s_axis_rpi_tx_tdata(rx_ring_buffer_tdata),
    .s_axis_rpi_tx_tvalid(rx_ring_buffer_tvalid),
    .s_axis_rpi_tx_tready(rx_ring_buffer_tready),
    .s_axis_rpi_tx_tlast(rx_ring_buffer_tlast)
);

ping_pong_buffer #(
    .DATA_WIDTH(8),
    .DEPTH(2048)
) ping_pong_buffer_tx (
    .clk(clk_int),
    .rst(rst_int),
    .i_s_axis_tdata(rpi_ingress_tdata),
    .i_s_axis_tvalid(rpi_ingress_tvalid),
    .o_s_axis_tready(rpi_ingress_tready),
    .i_s_axis_tlast(rpi_ingress_tlast),
    .o_m_axis_tdata(tx_ring_buffer_tdata),
    .o_m_axis_tvalid(tx_ring_buffer_tvalid),
    .i_m_axis_tready(tx_ring_buffer_tready),
    .o_m_axis_tlast(tx_ring_buffer_tlast)
);

ping_pong_buffer #(
    .DATA_WIDTH(8),
    .DEPTH(2048)
) ping_pong_buffer_rx (
    .clk(clk_int),
    .rst(rst_int),
    .i_s_axis_tdata(iq_codec_tdata),
    .i_s_axis_tvalid(iq_codec_tvalid),
    .o_s_axis_tready(iq_codec_tready),
    .i_s_axis_tlast(iq_codec_tlast),
    .o_m_axis_tdata(rx_ring_buffer_tdata),
    .o_m_axis_tvalid(rx_ring_buffer_tvalid),
    .i_m_axis_tready(rx_ring_buffer_tready),
    .o_m_axis_tlast(rx_ring_buffer_tlast)
);

iq_codec_loop iq_codec_loop_inst (
    .i_clk(clk_int),
    .i_rst(rst_int),
    .i_dac1_clk(dac1_dco_buf),
    .i_dac2_clk(dac2_dco_buf),
    .i_tone_mode(dac_tone_mode),
    .i_tone_pinc(tone_pinc),
    .i_s_axis_tdata(tx_ring_buffer_tdata),
    .i_s_axis_tvalid(tx_ring_buffer_tvalid),
    .o_s_axis_tready(tx_ring_buffer_tready),
    .i_s_axis_tlast(tx_ring_buffer_tlast),
    .o_m_axis_tdata(iq_codec_tdata),
    .o_m_axis_tvalid(iq_codec_tvalid),
    .i_m_axis_tready(iq_codec_tready),
    .o_m_axis_tlast(iq_codec_tlast),
    .o_dac_sample_valid(iq_dac_sample_valid),
    .o_dac1_h(iq_dac1_h),
    .o_dac1_l(iq_dac1_l),
    .o_dac2_h(iq_dac2_h),
    .o_dac2_l(iq_dac2_l)
);
(* mark_debug = "true"*)
reg helpme;


(* mark_debug = "true" *) reg [13:0] dac1_h_dbg_250;
(* mark_debug = "true" *) reg [13:0] dac1_l_dbg_250;
(* mark_debug = "true" *) reg        dac_tone_mode_dbg_250;
always @(posedge clk_250mhz_int) begin
    dac1_h_dbg_250 <= dac1_h;
    dac1_l_dbg_250 <= dac1_l;
    dac_tone_mode_dbg_250 <= dac_tone_mode;
end

(* mark_debug = "true" *) reg [13:0] dac1_h_dbg_500;
(* mark_debug = "true" *) reg [13:0] dac1_l_dbg_500;
(* mark_debug = "true" *) reg        dac_tone_mode_dbg_500;
always @(posedge clk_500mhz_int) begin
    dac1_h_dbg_500 <= dac1_h;
    dac1_l_dbg_500 <= dac1_l;
    dac_tone_mode_dbg_500 <= dac_tone_mode;
end

assign dac1_h = iq_dac1_h;
assign dac1_l = iq_dac1_l;
assign dac2_h = iq_dac2_h;
assign dac2_l = iq_dac2_l;

sync_signal #(
    .WIDTH(12),
    .N(2)
)
dac_ctrl_sync_inst (
    .clk(clk_spi),
    .in({dac_delay_apply_toggle_reg, dac2_delay_reg, dac1_delay_reg, 1'b0}),
    .out(dac_ctrl_sync)
);

assign dac_delay_apply_toggle_spi = dac_ctrl_sync[11];
assign dac2_delay_spi = dac_ctrl_sync[10:6];
assign dac1_delay_spi = dac_ctrl_sync[5:1];
assign dac_delay_apply_pulse_spi = dac_delay_apply_toggle_spi ^ dac_delay_apply_toggle_spi_d;

sync_signal #(
    .WIDTH(9),
    .N(2)
)
dac_spi_read_ctrl_sync_inst (
    .clk(clk_spi),
    .in({dac_spi_read_toggle_reg, dac_spi_read_addr_reg}),
    .out(dac_spi_read_ctrl_sync)
);

assign dac_spi_read_toggle_spi = dac_spi_read_ctrl_sync[8];
assign dac_spi_read_addr_spi = dac_spi_read_ctrl_sync[7:0];
assign dac_spi_read_pulse_spi = dac_spi_read_toggle_spi ^ dac_spi_read_toggle_spi_d;

sync_signal #(
    .WIDTH(10),
    .N(2)
)
dac_spi_read_status_sync_inst (
    .clk(clk_int),
    .in({dac_spi_read_busy_spi, dac_spi_read_done_toggle_spi, dac_spi_read_data_spi}),
    .out(dac_spi_read_status_sync)
);

assign dac_spi_read_busy_reg = dac_spi_read_status_sync[9];
assign dac_spi_read_done_toggle_reg = dac_spi_read_status_sync[8];
assign dac_spi_read_data_reg = dac_spi_read_status_sync[7:0];

wire dac_cfg_rst = DEBUG_SKIP_DAC_SPI_RECONFIG ? 1'b1 : (~mmcm_locked || ~delay_done);

always @(posedge clk_spi) begin
    if (~mmcm_locked || ~delay_done) begin
        dac_delay_apply_toggle_spi_d <= 1'b0;
        dac_spi_read_toggle_spi_d <= 1'b0;
    end else begin
        dac_delay_apply_toggle_spi_d <= dac_delay_apply_toggle_spi;
        dac_spi_read_toggle_spi_d <= dac_spi_read_toggle_spi;
    end
end

dac_iobuf dac_iobuf_inst
	(
	 .dac1_dco_p	(DAC1_DCO_P),
	 .dac1_dco_n	(DAC1_DCO_N),
	 .dac2_dco_p	(DAC2_DCO_P),
	 .dac2_dco_n	(DAC2_DCO_N),
	 .dac1_dci_p	(DAC1_DCI_P),	
	 .dac1_dci_n	(DAC1_DCI_N),	
	 .dac1_data_p	(DAC1_DATA_P), 
	 .dac1_data_n	(DAC1_DATA_N), 
	 .dac2_dci_p	(DAC2_DCI_P),	
	 .dac2_dci_n	(DAC2_DCI_N),  
	 .dac2_data_p	(DAC2_DATA_P), 
	 .dac2_data_n	(DAC2_DATA_N), 
	 .dac1_h 		(dac1_h),  
	 .dac1_l 		(dac1_l),  
	 .dac2_h 		(dac2_h),  
	 .dac2_l 		(dac2_l),  
	 .dac1_dco_buf 	(dac1_dco_buf),  
	 .dac2_dco_buf 	(dac2_dco_buf)  
    );

dac_config dac_config_inst(
	.rst			   (dac_cfg_rst),
	.clk			   (clk_spi),
    .i_dac1_delay       (dac1_delay_spi),
    .i_dac2_delay       (dac2_delay_spi),
    .i_apply            (dac_delay_apply_pulse_spi),
    .i_manual_read_addr (dac_spi_read_addr_spi),
    .i_manual_read      (dac_spi_read_pulse_spi),
    .o_manual_read_data (dac_spi_read_data_spi),
    .o_manual_read_done_toggle(dac_spi_read_done_toggle_spi),
    .o_manual_read_busy (dac_spi_read_busy_spi),
	.clk_spi_ce		   (CLK_SPI_CE),
	.dac1_spi_ce	   (DAC1_SPI_CE),
	.dac2_spi_ce	   (DAC2_SPI_CE),
	.spi_sclk		   (SPI_SCLK),
	.spi_sdio		   (SPI_SDIO),
	.spi_sdo           (SPI_SDO)
    );


reg [7:0] dac1_clk_divide;
always @(posedge dac1_dco_buf) begin
    dac1_clk_divide <= dac1_clk_divide + 1'b1;
    if (dac1_clk_divide == 8'd99) begin
        helpme <= ~helpme;
        dac1_clk_divide <= 8'd0;
    end
end

assign USER_SMA_GPIO_P = helpme;


endmodule



`resetall
