/*
Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

/* Addition's made to fpga_core.v
 * UDP application routing note:
 * The UDP AXI-Lite bridge enables multiple UDP application ports to coexist
 * on the same Ethernet/UDP stack in this design. Current ports are:
 * - UDP/1234: echo path
 * - UDP/10000: AXI-Lite register access bridge
 * - Tony DiMichele Feb 2026
 */

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA core logic
 */
module ethernet_subsystem #
(
    parameter TARGET = "GENERIC"
)
(
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    input  wire       clk,
    input  wire       clk90,
    input  wire       rst,

    /*
     * GPIO
     */
    input  wire       btnu,
    input  wire       btnl,
    input  wire       btnd,
    input  wire       btnr,
    input  wire       btnc,
    input  wire [7:0] sw,
    output wire [7:0] led,

    /*
     * Ethernet: 1000BASE-T RGMII
     */
    input  wire       phy_rx_clk,
    input  wire [3:0] phy_rxd,
    input  wire       phy_rx_ctl,
    output wire       phy_tx_clk,
    output wire [3:0] phy_txd,
    output wire       phy_tx_ctl,
    output wire       phy_reset_n,
    input  wire       phy_int_n,

    /*
     * UART: 115200 bps, 8N1
     */
    input  wire       uart_rxd,
    output wire       uart_txd,
    output wire       uart_rts,
    input  wire       uart_cts
);

// -----------------------------------------------------------------------------
// AXI between MAC and Ethernet modules
// -----------------------------------------------------------------------------
wire [7:0] rx_axis_tdata;
wire       rx_axis_tvalid;
wire       rx_axis_tready;
wire       rx_axis_tlast;
wire       rx_axis_tuser;

wire [7:0] tx_axis_tdata;
wire       tx_axis_tvalid;
wire       tx_axis_tready;
wire       tx_axis_tlast;
wire       tx_axis_tuser;

// -----------------------------------------------------------------------------
// Ethernet frame between Ethernet modules and UDP stack
// -----------------------------------------------------------------------------
wire        rx_eth_hdr_ready;
wire        rx_eth_hdr_valid;
wire [47:0] rx_eth_dest_mac;
wire [47:0] rx_eth_src_mac;
wire [15:0] rx_eth_type;
wire [7:0]  rx_eth_payload_axis_tdata;
wire        rx_eth_payload_axis_tvalid;
wire        rx_eth_payload_axis_tready;
wire        rx_eth_payload_axis_tlast;
wire        rx_eth_payload_axis_tuser;

wire        tx_eth_hdr_ready;
wire        tx_eth_hdr_valid;
wire [47:0] tx_eth_dest_mac;
wire [47:0] tx_eth_src_mac;
wire [15:0] tx_eth_type;
wire [7:0]  tx_eth_payload_axis_tdata;
wire        tx_eth_payload_axis_tvalid;
wire        tx_eth_payload_axis_tready;
wire        tx_eth_payload_axis_tlast;
wire        tx_eth_payload_axis_tuser;

// -----------------------------------------------------------------------------
// IP frame connections
// -----------------------------------------------------------------------------
wire        rx_ip_hdr_valid;
wire        rx_ip_hdr_ready;
wire [47:0] rx_ip_eth_dest_mac;
wire [47:0] rx_ip_eth_src_mac;
wire [15:0] rx_ip_eth_type;
wire [3:0]  rx_ip_version;
wire [3:0]  rx_ip_ihl;
wire [5:0]  rx_ip_dscp;
wire [1:0]  rx_ip_ecn;
wire [15:0] rx_ip_length;
wire [15:0] rx_ip_identification;
wire [2:0]  rx_ip_flags;
wire [12:0] rx_ip_fragment_offset;
wire [7:0]  rx_ip_ttl;
wire [7:0]  rx_ip_protocol;
wire [15:0] rx_ip_header_checksum;
wire [31:0] rx_ip_source_ip;
wire [31:0] rx_ip_dest_ip;
wire [7:0]  rx_ip_payload_axis_tdata;
wire        rx_ip_payload_axis_tvalid;
wire        rx_ip_payload_axis_tready;
wire        rx_ip_payload_axis_tlast;
wire        rx_ip_payload_axis_tuser;

wire        tx_ip_hdr_valid;
wire        tx_ip_hdr_ready;
wire [5:0]  tx_ip_dscp;
wire [1:0]  tx_ip_ecn;
wire [15:0] tx_ip_length;
wire [7:0]  tx_ip_ttl;
wire [7:0]  tx_ip_protocol;
wire [31:0] tx_ip_source_ip;
wire [31:0] tx_ip_dest_ip;
wire [7:0]  tx_ip_payload_axis_tdata;
wire        tx_ip_payload_axis_tvalid;
wire        tx_ip_payload_axis_tready;
wire        tx_ip_payload_axis_tlast;
wire        tx_ip_payload_axis_tuser;

// -----------------------------------------------------------------------------
// UDP frame connections
// -----------------------------------------------------------------------------
wire        rx_udp_hdr_valid;
wire        rx_udp_hdr_ready;
wire [47:0] rx_udp_eth_dest_mac;
wire [47:0] rx_udp_eth_src_mac;
wire [15:0] rx_udp_eth_type;
wire [3:0]  rx_udp_ip_version;
wire [3:0]  rx_udp_ip_ihl;
wire [5:0]  rx_udp_ip_dscp;
wire [1:0]  rx_udp_ip_ecn;
wire [15:0] rx_udp_ip_length;
wire [15:0] rx_udp_ip_identification;
wire [2:0]  rx_udp_ip_flags;
wire [12:0] rx_udp_ip_fragment_offset;
wire [7:0]  rx_udp_ip_ttl;
wire [7:0]  rx_udp_ip_protocol;
wire [15:0] rx_udp_ip_header_checksum;
wire [31:0] rx_udp_ip_source_ip;
wire [31:0] rx_udp_ip_dest_ip;
wire [15:0] rx_udp_source_port;
wire [15:0] rx_udp_dest_port;
wire [15:0] rx_udp_length;
wire [15:0] rx_udp_checksum;
wire [7:0]  rx_udp_payload_axis_tdata;
wire        rx_udp_payload_axis_tvalid;
wire        rx_udp_payload_axis_tready;
wire        rx_udp_payload_axis_tlast;
wire        rx_udp_payload_axis_tuser;

wire        tx_udp_hdr_valid;
wire        tx_udp_hdr_ready;
wire [5:0]  tx_udp_ip_dscp;
wire [1:0]  tx_udp_ip_ecn;
wire [7:0]  tx_udp_ip_ttl;
wire [31:0] tx_udp_ip_source_ip;
wire [31:0] tx_udp_ip_dest_ip;
wire [15:0] tx_udp_source_port;
wire [15:0] tx_udp_dest_port;
wire [15:0] tx_udp_length;
wire [15:0] tx_udp_checksum;
wire [7:0]  tx_udp_payload_axis_tdata;
wire        tx_udp_payload_axis_tvalid;
wire        tx_udp_payload_axis_tready;
wire        tx_udp_payload_axis_tlast;
wire        tx_udp_payload_axis_tuser;

wire [7:0]  rx_fifo_udp_payload_axis_tdata;
wire        rx_fifo_udp_payload_axis_tvalid;
wire        rx_fifo_udp_payload_axis_tready;
wire        rx_fifo_udp_payload_axis_tlast;
wire        rx_fifo_udp_payload_axis_tuser;

wire [7:0]  tx_fifo_udp_payload_axis_tdata;
wire        tx_fifo_udp_payload_axis_tvalid;
wire        tx_fifo_udp_payload_axis_tready;
wire        tx_fifo_udp_payload_axis_tlast;
wire        tx_fifo_udp_payload_axis_tuser;

// -----------------------------------------------------------------------------
// App 1 (register bridge on UDP/10000)
// -----------------------------------------------------------------------------
wire         app1_rx_hdr_valid;
wire         app1_rx_hdr_ready;
wire [31:0]  app1_rx_ip_src;
wire [31:0]  app1_rx_ip_dst;
wire [15:0]  app1_rx_udp_src_port;
wire [15:0]  app1_rx_udp_dst_port;
wire [15:0]  app1_rx_length;

wire [7:0]   app1_rx_tdata;
wire         app1_rx_tvalid;
wire         app1_rx_tready;
wire         app1_rx_tlast;

wire         app1_tx_hdr_valid;
wire         app1_tx_hdr_ready;
wire         echo_tx_hdr_ready;
wire [31:0]  app1_tx_ip_dst;
wire [31:0]  app1_tx_ip_src;
wire [15:0]  app1_tx_udp_dst_port;
wire [15:0]  app1_tx_udp_src_port;
wire [15:0]  app1_tx_length;

wire [7:0]   app1_tx_tdata;
wire         app1_tx_tvalid;
wire         app1_tx_tready;
wire         app1_tx_tlast;

// Point-to-point AXI-Lite between register app and regs block
wire [31:0] rb_AWADDR, rb_WDATA, rb_ARADDR, rb_RDATA;
wire [3:0]  rb_WSTRB;
wire        rb_AWVALID, rb_AWREADY, rb_WVALID, rb_WREADY;
wire [1:0]  rb_BRESP;
wire        rb_BVALID, rb_BREADY, rb_ARVALID, rb_ARREADY, rb_RVALID, rb_RREADY;
wire [1:0]  rb_RRESP;

wire [7:0]  regs_led;

// -----------------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------------
wire [47:0] local_mac   = 48'h02_00_00_00_00_00;
wire [31:0] local_ip    = {8'd192, 8'd168, 8'd1, 8'd128};
wire [31:0] gateway_ip  = {8'd192, 8'd168, 8'd1, 8'd1};
wire [31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0};

// IP ports not used
assign rx_ip_hdr_ready            = 1'b1;
assign rx_ip_payload_axis_tready  = 1'b1;

assign tx_ip_hdr_valid            = 1'b0;
assign tx_ip_dscp                 = 6'd0;
assign tx_ip_ecn                  = 2'd0;
assign tx_ip_length               = 16'd0;
assign tx_ip_ttl                  = 8'd0;
assign tx_ip_protocol             = 8'd0;
assign tx_ip_source_ip            = 32'd0;
assign tx_ip_dest_ip              = 32'd0;
assign tx_ip_payload_axis_tdata   = 8'd0;
assign tx_ip_payload_axis_tvalid  = 1'b0;
assign tx_ip_payload_axis_tlast   = 1'b0;
assign tx_ip_payload_axis_tuser   = 1'b0;

// -----------------------------------------------------------------------------
// UDP application routing
//   - Echo on port 1234 (stock behavior)
//   - Register bridge on port 10000 (new)
// -----------------------------------------------------------------------------
wire match_echo   = (rx_udp_dest_port == 16'd1234);
wire match_regapp = (rx_udp_dest_port == 16'd10000);

// Category latch per payload frame (prevents mid-frame switching)
reg cat_echo = 1'b0, cat_reg = 1'b0;
always @(posedge clk) begin
    if (rst) begin
        cat_echo <= 1'b0;
        cat_reg  <= 1'b0;
    end else begin
        if (rx_udp_hdr_valid && rx_udp_hdr_ready) begin
            cat_echo <= match_echo;
            cat_reg  <= match_regapp;
        end else if (rx_udp_payload_axis_tvalid && rx_udp_payload_axis_tready && rx_udp_payload_axis_tlast) begin
            cat_echo <= 1'b0;
            cat_reg  <= 1'b0;
        end
    end
end

// ---------------- RX header+payload routing ----------------
// Header valid to selected app
assign app1_rx_hdr_valid    = rx_udp_hdr_valid & match_regapp;

// Fanout header fields (values are valid when their *_hdr_valid is asserted)
assign app1_rx_ip_src       = rx_udp_ip_source_ip;
assign app1_rx_ip_dst       = rx_udp_ip_dest_ip;
assign app1_rx_udp_src_port = rx_udp_source_port;
assign app1_rx_udp_dst_port = rx_udp_dest_port;
assign app1_rx_length       = rx_udp_length;

// IMPORTANT: preserve stock echo gating for 1234, and let app1 accept its own
// headers. For all other ports, 'accept and drop' to keep RX pipeline moving.
wire echo_rx_hdr_ready_int  = echo_tx_hdr_ready;
assign rx_udp_hdr_ready     = match_echo   ? echo_rx_hdr_ready_int :
                              match_regapp ? app1_rx_hdr_ready      :
                                             1'b1; // drop others

// Payload demux
assign app1_rx_tdata   = rx_udp_payload_axis_tdata;
assign app1_rx_tvalid  = rx_udp_payload_axis_tvalid & cat_reg;
assign app1_rx_tlast   = rx_udp_payload_axis_tlast & cat_reg;

assign rx_fifo_udp_payload_axis_tdata  = rx_udp_payload_axis_tdata;
assign rx_fifo_udp_payload_axis_tvalid = rx_udp_payload_axis_tvalid & cat_echo;
assign rx_fifo_udp_payload_axis_tlast  = rx_udp_payload_axis_tlast & cat_echo;

// Backpressure to selected sink
assign rx_udp_payload_axis_tready = cat_echo ? rx_fifo_udp_payload_axis_tready :
                                     cat_reg ? app1_rx_tready :
                                               1'b1; // drop others

/// Echo side (unchanged fields)
assign tx_udp_ip_dscp  = 6'd0;
assign tx_udp_ip_ecn   = 2'd0;
assign tx_udp_ip_ttl   = 8'd64;
assign tx_udp_checksum = 16'd0;

// Echo header-valid matches stock condition
wire echo_tx_hdr_valid = rx_udp_hdr_valid & match_echo;

// Latch TX payload source per packet so payload routing does not depend on
// one-cycle header-valid pulses.
reg tx_sel_app1 = 1'b0;
always @(posedge clk) begin
    if (rst) begin
        tx_sel_app1 <= 1'b0;
    end else begin
        if (tx_udp_hdr_valid && tx_udp_hdr_ready) begin
            tx_sel_app1 <= app1_tx_hdr_valid;
        end else if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready && tx_udp_payload_axis_tlast) begin
            tx_sel_app1 <= 1'b0;
        end
    end
end

// Priority: app1 (bridge) > echo
assign tx_udp_hdr_valid    = app1_tx_hdr_valid | echo_tx_hdr_valid;

// Proper backpressure to sources
assign app1_tx_hdr_ready   = tx_udp_hdr_ready &  app1_tx_hdr_valid;
assign echo_tx_hdr_ready   = tx_udp_hdr_ready & ~app1_tx_hdr_valid;

// Header fields
assign tx_udp_ip_source_ip = app1_tx_hdr_valid ? app1_tx_ip_src       : local_ip;
assign tx_udp_ip_dest_ip   = app1_tx_hdr_valid ? app1_tx_ip_dst       : rx_udp_ip_source_ip;
assign tx_udp_source_port  = app1_tx_hdr_valid ? app1_tx_udp_src_port : rx_udp_dest_port;
assign tx_udp_dest_port    = app1_tx_hdr_valid ? app1_tx_udp_dst_port : rx_udp_source_port;
assign tx_udp_length       = app1_tx_hdr_valid ? app1_tx_length       : rx_udp_length;

// Payload mux
assign tx_udp_payload_axis_tdata  = tx_sel_app1 ? app1_tx_tdata  : tx_fifo_udp_payload_axis_tdata;
assign tx_udp_payload_axis_tvalid = tx_sel_app1 ? app1_tx_tvalid : tx_fifo_udp_payload_axis_tvalid;
assign tx_udp_payload_axis_tlast  = tx_sel_app1 ? app1_tx_tlast  : tx_fifo_udp_payload_axis_tlast;
assign tx_udp_payload_axis_tuser  = tx_sel_app1 ? 1'b0           : tx_fifo_udp_payload_axis_tuser;

// Backpressure on payload stream
assign app1_tx_tready             = tx_sel_app1 ? tx_udp_payload_axis_tready : 1'b0;
assign tx_fifo_udp_payload_axis_tready = tx_sel_app1 ? 1'b0 : tx_udp_payload_axis_tready;
// -----------------------------------------------------------------------------
// Register bridge (UDP/10000) and small AXI-Lite regs (REG3[7:0] -> LEDs)
// -----------------------------------------------------------------------------
udp_axi_lite_bridge #(.BRIDGE_PORT(16'd10000)) u_regbridge (
    .clk(clk), .rst(rst),

    // UDP RX (from demux)
    .s_udp_rx_hdr_valid(app1_rx_hdr_valid),
    .s_udp_rx_hdr_ready(app1_rx_hdr_ready),
    .s_udp_rx_ip_src(app1_rx_ip_src),
    .s_udp_rx_ip_dst(app1_rx_ip_dst),
    .s_udp_rx_udp_src_port(app1_rx_udp_src_port),
    .s_udp_rx_udp_dst_port(app1_rx_udp_dst_port),
    .s_udp_rx_length(app1_rx_length),

    .s_udp_rx_tdata(app1_rx_tdata),
    .s_udp_rx_tvalid(app1_rx_tvalid),
    .s_udp_rx_tready(app1_rx_tready),
    .s_udp_rx_tlast(app1_rx_tlast),

    // UDP TX (to mux)
    .m_udp_tx_hdr_valid(app1_tx_hdr_valid),
    .m_udp_tx_hdr_ready(app1_tx_hdr_ready),
    .m_udp_tx_ip_dst(app1_tx_ip_dst),
    .m_udp_tx_ip_src(app1_tx_ip_src),
    .m_udp_tx_udp_dst_port(app1_tx_udp_dst_port),
    .m_udp_tx_udp_src_port(app1_tx_udp_src_port),
    .m_udp_tx_length(app1_tx_length),

    .m_udp_tx_tdata(app1_tx_tdata),
    .m_udp_tx_tvalid(app1_tx_tvalid),
    .m_udp_tx_tready(app1_tx_tready),
    .m_udp_tx_tlast(app1_tx_tlast),

    // AXI-Lite master
    .M_AXI_AWADDR(rb_AWADDR),
    .M_AXI_AWVALID(rb_AWVALID),
    .M_AXI_AWREADY(rb_AWREADY),

    .M_AXI_WDATA(rb_WDATA),
    .M_AXI_WSTRB(rb_WSTRB),
    .M_AXI_WVALID(rb_WVALID),
    .M_AXI_WREADY(rb_WREADY),

    .M_AXI_BRESP(rb_BRESP),
    .M_AXI_BVALID(rb_BVALID),
    .M_AXI_BREADY(rb_BREADY),

    .M_AXI_ARADDR(rb_ARADDR),
    .M_AXI_ARVALID(rb_ARVALID),
    .M_AXI_ARREADY(rb_ARREADY),

    .M_AXI_RDATA(rb_RDATA),
    .M_AXI_RRESP(rb_RRESP),
    .M_AXI_RVALID(rb_RVALID),
    .M_AXI_RREADY(rb_RREADY),

    .local_ip(local_ip)
);

axi_lite_regs u_regs (
    .s_axi_aclk   (clk),
    .s_axi_aresetn(~rst),

    .s_axi_awaddr (rb_AWADDR[5:0]),
    .s_axi_awvalid(rb_AWVALID),
    .s_axi_awready(rb_AWREADY),

    .s_axi_wdata  (rb_WDATA),
    .s_axi_wstrb  (rb_WSTRB),
    .s_axi_wvalid (rb_WVALID),
    .s_axi_wready (rb_WREADY),

    .s_axi_bresp  (rb_BRESP),
    .s_axi_bvalid (rb_BVALID),
    .s_axi_bready (rb_BREADY),

    .s_axi_araddr (rb_ARADDR[5:0]),
    .s_axi_arvalid(rb_ARVALID),
    .s_axi_arready(rb_ARREADY),

    .s_axi_rdata  (rb_RDATA),
    .s_axi_rresp  (rb_RRESP),
    .s_axi_rvalid (rb_RVALID),
    .s_axi_rready (rb_RREADY),

    .reg3_out(regs_led)
);

// -----------------------------------------------------------------------------
// LED behavior:
//   - led_reg shows first TX payload byte (original behavior)
//   - regs_led shows REG3[7:0] written via UDP/10000
//   - final LED bus is OR of both (customize as you like)
// -----------------------------------------------------------------------------
reg       valid_last = 1'b0;
reg [7:0] led_reg    = 8'h00;

always @(posedge clk) begin
    if (rst) begin
        led_reg   <= 8'h00;
        valid_last<= 1'b0;
    end else begin
        if (tx_udp_payload_axis_tvalid) begin
            if (!valid_last) begin
                led_reg   <= tx_udp_payload_axis_tdata;
                valid_last<= 1'b1;
            end
            if (tx_udp_payload_axis_tlast) begin
                valid_last<= 1'b0;
            end
        end
    end
end

// --- DEBUG PULSES ---
// LED7: header accepted for port 10000 (RX demux works)
// LED6: bridge won a TX header handshake (TX arbiter works)

reg [23:0] rx_pulse, tx_pulse;
always @(posedge clk) begin
    if (rst) begin
        rx_pulse <= 24'd0;
        tx_pulse <= 24'd0;
    end else begin
        if (app1_rx_hdr_valid && app1_rx_hdr_ready)
            rx_pulse <= 24'hFFFFFF;
        else if (rx_pulse != 0)
            rx_pulse <= rx_pulse - 1;

        if (app1_tx_hdr_valid && app1_tx_hdr_ready)
            tx_pulse <= 24'hFFFFFF;
        else if (tx_pulse != 0)
            tx_pulse <= tx_pulse - 1;
    end
end

wire led_rx = |rx_pulse;  // LED7
wire led_tx = |tx_pulse;  // LED6

// Combine with existing LED drivers (regs_led and echo's led_reg)
assign led = ({led_rx, led_tx, 6'b0} | {2'b00, regs_led[5:0]} | led_reg);
assign phy_reset_n = ~rst;

assign uart_txd = 1'b0;
assign uart_rts = 1'b0;

// -----------------------------------------------------------------------------
// MAC + framing + UDP/IP stack (unchanged from example)
// -----------------------------------------------------------------------------
eth_mac_1g_rgmii_fifo #(
    .TARGET(TARGET),
    .IODDR_STYLE("IODDR"),
    .CLOCK_INPUT_STYLE("BUFR"),
    .USE_CLK90("TRUE"),
    .ENABLE_PADDING(1),
    .MIN_FRAME_LENGTH(64),
    .TX_FIFO_DEPTH(4096),
    .TX_FRAME_FIFO(1),
    .RX_FIFO_DEPTH(4096),
    .RX_FRAME_FIFO(1)
)
eth_mac_inst (
    .gtx_clk(clk),
    .gtx_clk90(clk90),
    .gtx_rst(rst),
    .logic_clk(clk),
    .logic_rst(rst),

    .tx_axis_tdata(tx_axis_tdata),
    .tx_axis_tvalid(tx_axis_tvalid),
    .tx_axis_tready(tx_axis_tready),
    .tx_axis_tlast(tx_axis_tlast),
    .tx_axis_tuser(tx_axis_tuser),

    .rx_axis_tdata(rx_axis_tdata),
    .rx_axis_tvalid(rx_axis_tvalid),
    .rx_axis_tready(rx_axis_tready),
    .rx_axis_tlast(rx_axis_tlast),
    .rx_axis_tuser(rx_axis_tuser),

    .rgmii_rx_clk(phy_rx_clk),
    .rgmii_rxd(phy_rxd),
    .rgmii_rx_ctl(phy_rx_ctl),
    .rgmii_tx_clk(phy_tx_clk),
    .rgmii_txd(phy_txd),
    .rgmii_tx_ctl(phy_tx_ctl),

    .tx_fifo_overflow(),
    .tx_fifo_bad_frame(),
    .tx_fifo_good_frame(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .rx_fifo_overflow(),
    .rx_fifo_bad_frame(),
    .rx_fifo_good_frame(),
    .speed(),

    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

eth_axis_rx
eth_axis_rx_inst (
    .clk(clk),
    .rst(rst),
    // AXI input
    .s_axis_tdata(rx_axis_tdata),
    .s_axis_tvalid(rx_axis_tvalid),
    .s_axis_tready(rx_axis_tready),
    .s_axis_tlast(rx_axis_tlast),
    .s_axis_tuser(rx_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid(rx_eth_hdr_valid),
    .m_eth_hdr_ready(rx_eth_hdr_ready),
    .m_eth_dest_mac(rx_eth_dest_mac),
    .m_eth_src_mac(rx_eth_src_mac),
    .m_eth_type(rx_eth_type),
    .m_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(rx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
    // Status signals
    .busy(),
    .error_header_early_termination()
);

eth_axis_tx
eth_axis_tx_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(tx_eth_hdr_valid),
    .s_eth_hdr_ready(tx_eth_hdr_ready),
    .s_eth_dest_mac(tx_eth_dest_mac),
    .s_eth_src_mac(tx_eth_src_mac),
    .s_eth_type(tx_eth_type),
    .s_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(tx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
    // AXI output
    .m_axis_tdata(tx_axis_tdata),
    .m_axis_tvalid(tx_axis_tvalid),
    .m_axis_tready(tx_axis_tready),
    .m_axis_tlast(tx_axis_tlast),
    .m_axis_tuser(tx_axis_tuser),
    // Status signals
    .busy()
);

udp_complete
udp_complete_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(rx_eth_hdr_valid),
    .s_eth_hdr_ready(rx_eth_hdr_ready),
    .s_eth_dest_mac(rx_eth_dest_mac),
    .s_eth_src_mac(rx_eth_src_mac),
    .s_eth_type(rx_eth_type),
    .s_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(rx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid(tx_eth_hdr_valid),
    .m_eth_hdr_ready(tx_eth_hdr_ready),
    .m_eth_dest_mac(tx_eth_dest_mac),
    .m_eth_src_mac(tx_eth_src_mac),
    .m_eth_type(tx_eth_type),
    .m_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(tx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
    // IP frame input
    .s_ip_hdr_valid(tx_ip_hdr_valid),
    .s_ip_hdr_ready(tx_ip_hdr_ready),
    .s_ip_dscp(tx_ip_dscp),
    .s_ip_ecn(tx_ip_ecn),
    .s_ip_length(tx_ip_length),
    .s_ip_ttl(tx_ip_ttl),
    .s_ip_protocol(tx_ip_protocol),
    .s_ip_source_ip(tx_ip_source_ip),
    .s_ip_dest_ip(tx_ip_dest_ip),
    .s_ip_payload_axis_tdata(tx_ip_payload_axis_tdata),
    .s_ip_payload_axis_tvalid(tx_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(tx_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast(tx_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser(tx_ip_payload_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid(rx_ip_hdr_valid),
    .m_ip_hdr_ready(rx_ip_hdr_ready),
    .m_ip_eth_dest_mac(rx_ip_eth_dest_mac),
    .m_ip_eth_src_mac(rx_ip_eth_src_mac),
    .m_ip_eth_type(rx_ip_eth_type),
    .m_ip_version(rx_ip_version),
    .m_ip_ihl(rx_ip_ihl),
    .m_ip_dscp(rx_ip_dscp),
    .m_ip_ecn(rx_ip_ecn),
    .m_ip_length(rx_ip_length),
    .m_ip_identification(rx_ip_identification),
    .m_ip_flags(rx_ip_flags),
    .m_ip_fragment_offset(rx_ip_fragment_offset),
    .m_ip_ttl(rx_ip_ttl),
    .m_ip_protocol(rx_ip_protocol),
    .m_ip_header_checksum(rx_ip_header_checksum),
    .m_ip_source_ip(rx_ip_source_ip),
    .m_ip_dest_ip(rx_ip_dest_ip),
    .m_ip_payload_axis_tdata(rx_ip_payload_axis_tdata),
    .m_ip_payload_axis_tvalid(rx_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(rx_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(rx_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser(rx_ip_payload_axis_tuser),
    // UDP frame input
    .s_udp_hdr_valid(tx_udp_hdr_valid),
    .s_udp_hdr_ready(tx_udp_hdr_ready),
    .s_udp_ip_dscp(tx_udp_ip_dscp),
    .s_udp_ip_ecn(tx_udp_ip_ecn),
    .s_udp_ip_ttl(tx_udp_ip_ttl),
    .s_udp_ip_source_ip(tx_udp_ip_source_ip),
    .s_udp_ip_dest_ip(tx_udp_ip_dest_ip),
    .s_udp_source_port(tx_udp_source_port),
    .s_udp_dest_port(tx_udp_dest_port),
    .s_udp_length(tx_udp_length),
    .s_udp_checksum(tx_udp_checksum),
    .s_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
    .s_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready(tx_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
    // UDP frame output
    .m_udp_hdr_valid(rx_udp_hdr_valid),
    .m_udp_hdr_ready(rx_udp_hdr_ready),
    .m_udp_eth_dest_mac(rx_udp_eth_dest_mac),
    .m_udp_eth_src_mac(rx_udp_eth_src_mac),
    .m_udp_eth_type(rx_udp_eth_type),
    .m_udp_ip_version(rx_udp_ip_version),
    .m_udp_ip_ihl(rx_udp_ip_ihl),
    .m_udp_ip_dscp(rx_udp_ip_dscp),
    .m_udp_ip_ecn(rx_udp_ip_ecn),
    .m_udp_ip_length(rx_udp_ip_length),
    .m_udp_ip_identification(rx_udp_ip_identification),
    .m_udp_ip_flags(rx_udp_ip_flags),
    .m_udp_ip_fragment_offset(rx_udp_ip_fragment_offset),
    .m_udp_ip_ttl(rx_udp_ip_ttl),
    .m_udp_ip_protocol(rx_udp_ip_protocol),
    .m_udp_ip_header_checksum(rx_udp_ip_header_checksum),
    .m_udp_ip_source_ip(rx_udp_ip_source_ip),
    .m_udp_ip_dest_ip(rx_udp_ip_dest_ip),
    .m_udp_source_port(rx_udp_source_port),
    .m_udp_dest_port(rx_udp_dest_port),
    .m_udp_length(rx_udp_length),
    .m_udp_checksum(rx_udp_checksum),
    .m_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
    .m_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
    .m_udp_payload_axis_tready(rx_udp_payload_axis_tready),
    .m_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
    .m_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),
    // Status signals
    .ip_rx_busy(),
    .ip_tx_busy(),
    .udp_rx_busy(),
    .udp_tx_busy(),
    .ip_rx_error_header_early_termination(),
    .ip_rx_error_payload_early_termination(),
    .ip_rx_error_invalid_header(),
    .ip_rx_error_invalid_checksum(),
    .ip_tx_error_payload_early_termination(),
    .ip_tx_error_arp_failed(),
    .udp_rx_error_header_early_termination(),
    .udp_rx_error_payload_early_termination(),
    .udp_tx_error_payload_early_termination(),
    // Configuration
    .local_mac(local_mac),
    .local_ip(local_ip),
    .gateway_ip(gateway_ip),
    .subnet_mask(subnet_mask),
    .clear_arp_cache(1'b0)
);

axis_fifo #(
    .DEPTH(8192),
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .FRAME_FIFO(0)
)
udp_payload_fifo (
    .clk(clk),
    .rst(rst),

    // AXI input
    .s_axis_tdata(rx_fifo_udp_payload_axis_tdata),
    .s_axis_tkeep(1'b0),
    .s_axis_tvalid(rx_fifo_udp_payload_axis_tvalid),
    .s_axis_tready(rx_fifo_udp_payload_axis_tready),
    .s_axis_tlast(rx_fifo_udp_payload_axis_tlast),
    .s_axis_tid(1'b0),
    .s_axis_tdest(1'b0),
    .s_axis_tuser(rx_fifo_udp_payload_axis_tuser),

    // AXI output
    .m_axis_tdata(tx_fifo_udp_payload_axis_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(tx_fifo_udp_payload_axis_tvalid),
    .m_axis_tready(tx_fifo_udp_payload_axis_tready),
    .m_axis_tlast(tx_fifo_udp_payload_axis_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(tx_fifo_udp_payload_axis_tuser),

    // Status
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);


endmodule

`resetall