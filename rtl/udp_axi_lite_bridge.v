// rtl/udp_axi_lite_bridge.v
// Verilog-2001 (no SystemVerilog).
// UDP single 32-bit read/write on BRIDGE_PORT (default 10000).
//
// Request:
//   READ  : [0x00][ADDR(4)]
//   WRITE : [0x01][ADDR(4)][DATA(4)]
// Response:
//   [STATUS(1)][ADDR(4)][DATA(4)]   STATUS: 0x00=OK, 0x01=ERROR
//
// Connect to udp_complete app interface. AXI4-Lite master issues single-beat R/W.

`timescale 1ns/1ps
`default_nettype none

module udp_axi_lite_bridge #
(
    parameter BRIDGE_PORT = 16'd10000
)
(
    input  wire         clk,
    input  wire         rst,

    // ---- UDP RX app (from udp_complete) ----
    input  wire         s_udp_rx_hdr_valid,
    output wire         s_udp_rx_hdr_ready,
    input  wire [31:0]  s_udp_rx_ip_src,
    input  wire [31:0]  s_udp_rx_ip_dst,
    input  wire [15:0]  s_udp_rx_udp_src_port,
    input  wire [15:0]  s_udp_rx_udp_dst_port,
    input  wire [15:0]  s_udp_rx_length,

    input  wire [7:0]   s_udp_rx_tdata,
    input  wire         s_udp_rx_tvalid,
    output wire         s_udp_rx_tready,
    input  wire         s_udp_rx_tlast,

    // ---- UDP TX app (to udp_complete) ----
    output reg          m_udp_tx_hdr_valid,
    input  wire         m_udp_tx_hdr_ready,
    output reg  [31:0]  m_udp_tx_ip_dst,
    output reg  [31:0]  m_udp_tx_ip_src,
    output reg  [15:0]  m_udp_tx_udp_dst_port,
    output reg  [15:0]  m_udp_tx_udp_src_port,
    output reg  [15:0]  m_udp_tx_length,

    output reg  [7:0]   m_udp_tx_tdata,
    output reg          m_udp_tx_tvalid,
    input  wire         m_udp_tx_tready,
    output reg          m_udp_tx_tlast,

    // ---- AXI4-Lite master ----
    output reg  [31:0]  M_AXI_AWADDR,
    output reg          M_AXI_AWVALID,
    input  wire         M_AXI_AWREADY,

    output reg  [31:0]  M_AXI_WDATA,
    output reg  [3:0]   M_AXI_WSTRB,
    output reg          M_AXI_WVALID,
    input  wire         M_AXI_WREADY,

    input  wire [1:0]   M_AXI_BRESP,
    input  wire         M_AXI_BVALID,
    output reg          M_AXI_BREADY,

    output reg  [31:0]  M_AXI_ARADDR,
    output reg          M_AXI_ARVALID,
    input  wire         M_AXI_ARREADY,

    input  wire [31:0]  M_AXI_RDATA,
    input  wire [1:0]   M_AXI_RRESP,
    input  wire         M_AXI_RVALID,
    output reg          M_AXI_RREADY,

    input  wire [31:0]  local_ip
);

    // --------------------------
    // Constants
    // --------------------------
    localparam [7:0] OP_READ  = 8'h00;
    localparam [7:0] OP_WRITE = 8'h01;

    localparam [2:0]
        ST_IDLE   = 3'd0,
        ST_DO_AR  = 3'd1,
        ST_WAIT_R = 3'd2,
        ST_DO_AW  = 3'd3,
        ST_DO_W   = 3'd4,
        ST_WAIT_B = 3'd5,
        ST_BUILD  = 3'd6,
        ST_SEND   = 3'd7;

    // --------------------------
    // RX capture (unique RX counter: rx_cnt)
    // --------------------------
    reg        rx_hdr_take;
    reg        capturing;
    reg        packet_ok;
    reg [3:0]  rx_cnt;

    reg [7:0]  op_reg;
    reg [31:0] addr_reg;
    reg [31:0] data_reg;

    reg [31:0] ip_src_reg;
    reg [15:0] udp_src_port_reg;
    reg [15:0] udp_dst_port_reg;
    reg [15:0] rx_len_reg;

    assign s_udp_rx_hdr_ready = !rst && !rx_hdr_take;
    assign s_udp_rx_tready    = capturing && !rst;

    always @(posedge clk) begin
        if (rst) begin
            rx_hdr_take   <= 1'b0;
            capturing     <= 1'b0;
            packet_ok     <= 1'b0;
            rx_cnt        <= 4'd0;
        end else begin
            // Latch header
            if (s_udp_rx_hdr_valid && s_udp_rx_hdr_ready) begin
                ip_src_reg        <= s_udp_rx_ip_src;
                udp_src_port_reg  <= s_udp_rx_udp_src_port;
                udp_dst_port_reg  <= s_udp_rx_udp_dst_port;
                rx_len_reg        <= s_udp_rx_length;
                rx_hdr_take       <= 1'b1;

                if (s_udp_rx_udp_dst_port == BRIDGE_PORT) begin
                    capturing <= 1'b1;
                    packet_ok <= 1'b1;
                    rx_cnt    <= 4'd0;
                end else begin
                    capturing <= 1'b0; // ignore other ports
                end
            end

            // Capture payload
            if (capturing && s_udp_rx_tvalid) begin
                case (rx_cnt)
                    4'd0: op_reg            <= s_udp_rx_tdata;
                    4'd1: addr_reg[31:24]   <= s_udp_rx_tdata;
                    4'd2: addr_reg[23:16]   <= s_udp_rx_tdata;
                    4'd3: addr_reg[15:8]    <= s_udp_rx_tdata;
                    4'd4: addr_reg[7:0]     <= s_udp_rx_tdata;
                    4'd5: data_reg[31:24]   <= s_udp_rx_tdata;
                    4'd6: data_reg[23:16]   <= s_udp_rx_tdata;
                    4'd7: data_reg[15:8]    <= s_udp_rx_tdata;
                    4'd8: data_reg[7:0]     <= s_udp_rx_tdata;
                    default: ;
                endcase
                rx_cnt <= rx_cnt + 1'b1;
            end

            // End of frame
            if (s_udp_rx_tvalid && s_udp_rx_tlast) begin
                capturing <= 1'b0;
                if ((op_reg == OP_READ  && rx_len_reg < 16'd5) ||
                    (op_reg == OP_WRITE && rx_len_reg < 16'd9)) begin
                    packet_ok <= 1'b0;
                end
            end

            // Ready for next header after payload completes
            if (~capturing && rx_hdr_take && (!s_udp_rx_tvalid || (s_udp_rx_tvalid && s_udp_rx_tlast))) begin
                rx_hdr_take <= 1'b0;
            end
        end
    end

    // --------------------------
    // AXI-Lite master FSM
    // --------------------------
    reg [2:0] state, state_next;

    // Reply fields
    reg [7:0]  status_reg;    // 0=OK, 1=ERR
    reg [31:0] reply_data;

    // Unique TX serializer counter: tx_cnt
    reg [3:0]  tx_cnt;

    // Combinational defaults
    always @* begin
        // AXI-Lite defaults
        M_AXI_ARVALID = 1'b0;
        M_AXI_ARADDR  = addr_reg;
        M_AXI_RREADY  = 1'b0;

        M_AXI_AWVALID = 1'b0;
        M_AXI_AWADDR  = addr_reg;
        M_AXI_WVALID  = 1'b0;
        M_AXI_WDATA   = data_reg;
        M_AXI_WSTRB   = 4'hF;
        M_AXI_BREADY  = 1'b0;

        // TX header/payload controlled in sequential
        state_next = state;

        case (state)
            ST_IDLE: begin
                if (packet_ok && !capturing && rx_hdr_take) begin
                    if (op_reg == OP_READ)       state_next = ST_DO_AR;
                    else if (op_reg == OP_WRITE) state_next = ST_DO_AW;
                    else                         state_next = ST_BUILD;
                end
            end

            ST_DO_AR: begin
                M_AXI_ARVALID = 1'b1;
                if (M_AXI_ARREADY) state_next = ST_WAIT_R;
            end

            ST_WAIT_R: begin
                M_AXI_RREADY = 1'b1;
                if (M_AXI_RVALID) state_next = ST_BUILD;
            end

            ST_DO_AW: begin
                M_AXI_AWVALID = 1'b1;
                if (M_AXI_AWREADY) state_next = ST_DO_W;
            end

            ST_DO_W: begin
                M_AXI_WVALID = 1'b1;
                if (M_AXI_WREADY) state_next = ST_WAIT_B;
            end

            ST_WAIT_B: begin
                M_AXI_BREADY = 1'b1;
                if (M_AXI_BVALID) state_next = ST_BUILD;
            end

            ST_BUILD: begin
                state_next = ST_SEND;
            end

            ST_SEND: begin
                // advance handled in sequential
            end

            default: state_next = ST_IDLE;
        endcase
    end

    // Sequential side effects and outputs
    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;

            status_reg <= 8'h00;
            reply_data <= 32'h0000_0000;

            m_udp_tx_hdr_valid <= 1'b0;
            m_udp_tx_ip_dst    <= 32'h0;
            m_udp_tx_ip_src    <= 32'h0;
            m_udp_tx_udp_dst_port <= 16'h0;
            m_udp_tx_udp_src_port <= BRIDGE_PORT;
            m_udp_tx_length    <= 16'd9;

            m_udp_tx_tdata     <= 8'h00;
            m_udp_tx_tvalid    <= 1'b0;
            m_udp_tx_tlast     <= 1'b0;

            tx_cnt             <= 4'd0;
        end else begin
            state <= state_next;

            case (state)
                ST_WAIT_R: begin
                    if (M_AXI_RVALID) begin
                        reply_data <= M_AXI_RDATA;
                        status_reg <= (M_AXI_RRESP == 2'b00) ? 8'h00 : 8'h01;
                    end
                end

                ST_WAIT_B: begin
                    if (M_AXI_BVALID) begin
                        reply_data <= data_reg; // echo written data
                        status_reg <= (M_AXI_BRESP == 2'b00) ? 8'h00 : 8'h01;
                    end
                end

                ST_BUILD: begin
                    // Build TX header
                    m_udp_tx_ip_dst       <= ip_src_reg;
                    m_udp_tx_udp_dst_port <= udp_src_port_reg;
                    m_udp_tx_ip_src       <= local_ip;
                    m_udp_tx_length       <= 16'd9;

                    // Unknown op -> error
                    if (op_reg != OP_READ && op_reg != OP_WRITE)
                        status_reg <= 8'h01;

                    // Emit header
                    m_udp_tx_hdr_valid <= 1'b1;
                    m_udp_tx_tvalid    <= 1'b0;
                    m_udp_tx_tlast     <= 1'b0;
                end

                ST_SEND: begin
                    // After header accepted, stream 9 bytes
                    if (m_udp_tx_hdr_valid && m_udp_tx_hdr_ready) begin
                        m_udp_tx_hdr_valid <= 1'b0;
                        // Start payload
                        m_udp_tx_tvalid <= 1'b1;
                        m_udp_tx_tlast  <= 1'b0;
                        m_udp_tx_tdata  <= status_reg;
                        tx_cnt          <= 4'd0;
                    end else if (m_udp_tx_tvalid && m_udp_tx_tready) begin
                        tx_cnt <= tx_cnt + 1'b1;
                        case (tx_cnt)
                            4'd0:  m_udp_tx_tdata <= addr_reg[31:24];
                            4'd1:  m_udp_tx_tdata <= addr_reg[23:16];
                            4'd2:  m_udp_tx_tdata <= addr_reg[15:8];
                            4'd3:  m_udp_tx_tdata <= addr_reg[7:0];
                            4'd4:  m_udp_tx_tdata <= reply_data[31:24];
                            4'd5:  m_udp_tx_tdata <= reply_data[23:16];
                            4'd6:  m_udp_tx_tdata <= reply_data[15:8];
                            4'd7:  begin
                                      m_udp_tx_tdata <= reply_data[7:0];
                                      m_udp_tx_tlast <= 1'b1;
                                   end
                            default: begin
                                      m_udp_tx_tvalid <= 1'b0;
                                      m_udp_tx_tlast  <= 1'b0;
                                     end
                        endcase
                    end

                    // End of transmit
                    if (m_udp_tx_tvalid && m_udp_tx_tready && m_udp_tx_tlast) begin
                        m_udp_tx_tvalid <= 1'b0;
                        m_udp_tx_tlast  <= 1'b0;
                        state           <= ST_IDLE;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule

`default_nettype wire