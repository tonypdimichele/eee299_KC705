`timescale 1ns / 1ps


module ping_pong_buffer #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH = 2048
)(
    input  logic                 clk,
    input  logic                 rst,

    input  logic [DATA_WIDTH-1:0] i_s_axis_tdata,
    input  logic                  i_s_axis_tvalid,
    output logic                  o_s_axis_tready,
    input  logic                  i_s_axis_tlast,
   (*mark_debug = "true"*)
    output logic [DATA_WIDTH-1:0] o_m_axis_tdata,
    output logic                  o_m_axis_tvalid,
    input  logic                  i_m_axis_tready,
    output logic                  o_m_axis_tlast
);

localparam integer PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
localparam integer WORD_W = DATA_WIDTH + 1;

logic             bank_full [0:1];
logic             wr_bank;
logic             wr_in_pkt;
logic [PTR_W-1:0] wr_ptr;

logic             rd_bank;
logic             rd_active;
logic [PTR_W-1:0] rd_ptr;

logic             out_bank_has_data;
logic [WORD_W-1:0] out_word;
logic             out_word_valid;

logic [WORD_W-1:0] bram0_dout;
logic [WORD_W-1:0] bram1_dout;
logic             wr_bank_eff;
logic [PTR_W-1:0] wr_addr_eff;
logic [WORD_W-1:0] wr_data_eff;
logic             wr_en0;
logic             wr_en1;

logic             rd_req_fire;
logic             rd_req_bank;
logic [PTR_W-1:0] rd_req_addr;
logic             rd_data_pending;
logic             rd_data_bank;

// If preferred bank is full, fall back to the other bank.
logic preferred_wr_full;
logic other_wr_full;
logic can_start_pkt;
logic sel_wr_bank;

logic in_hs;
logic out_hs;

assign out_bank_has_data = bank_full[rd_bank];
assign preferred_wr_full = bank_full[wr_bank];
assign other_wr_full = bank_full[~wr_bank];
assign can_start_pkt = ~preferred_wr_full || ~other_wr_full;
assign sel_wr_bank = ~preferred_wr_full ? wr_bank : ~wr_bank;
assign in_hs = i_s_axis_tvalid && o_s_axis_tready;
assign out_hs = out_word_valid && i_m_axis_tready;

assign wr_bank_eff = wr_in_pkt ? wr_bank : sel_wr_bank;
assign wr_addr_eff = wr_ptr;
assign wr_data_eff = {i_s_axis_tlast, i_s_axis_tdata};
assign wr_en0 = in_hs && !wr_bank_eff;
assign wr_en1 = in_hs &&  wr_bank_eff;

assign rd_req_fire = rd_active && !rd_data_pending && !out_word_valid;
assign rd_req_bank = rd_bank;
assign rd_req_addr = rd_ptr;

assign o_s_axis_tready = wr_in_pkt ? (wr_ptr < DEPTH) : can_start_pkt;

assign o_m_axis_tvalid = out_word_valid;
assign o_m_axis_tdata  = out_word[DATA_WIDTH-1:0];
assign o_m_axis_tlast  = out_word[DATA_WIDTH];

// Two BRAM banks (packet ping-pong), each word is {tlast,tdata}.
xpm_memory_sdpram #(
    .ADDR_WIDTH_A(PTR_W),
    .ADDR_WIDTH_B(PTR_W),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(WORD_W),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(WORD_W*DEPTH),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(WORD_W),
    .READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_A("SYNC"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(0),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(WORD_W),
    .WRITE_MODE_B("read_first")
) bank0_bram (
    .clka(clk),
    .ena(wr_en0),
    .wea(wr_en0),
    .addra(wr_addr_eff),
    .dina(wr_data_eff),
    .injectsbiterra(1'b0),
    .injectdbiterra(1'b0),

    .clkb(clk),
    .enb(rd_req_fire && !rd_req_bank),
    .rstb(rst),
    .regceb(1'b1),
    .addrb(rd_req_addr),
    .doutb(bram0_dout),
    .sbiterrb(),
    .dbiterrb()
);

xpm_memory_sdpram #(
    .ADDR_WIDTH_A(PTR_W),
    .ADDR_WIDTH_B(PTR_W),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(WORD_W),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(WORD_W*DEPTH),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(WORD_W),
    .READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_A("SYNC"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(0),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(WORD_W),
    .WRITE_MODE_B("read_first")
) bank1_bram (
    .clka(clk),
    .ena(wr_en1),
    .wea(wr_en1),
    .addra(wr_addr_eff),
    .dina(wr_data_eff),
    .injectsbiterra(1'b0),
    .injectdbiterra(1'b0),

    .clkb(clk),
    .enb(rd_req_fire && rd_req_bank),
    .rstb(rst),
    .regceb(1'b1),
    .addrb(rd_req_addr),
    .doutb(bram1_dout),
    .sbiterrb(),
    .dbiterrb()
);

always @(posedge clk) begin
    if (rst) begin
        bank_full[0] <= 1'b0;
        bank_full[1] <= 1'b0;
        wr_bank      <= 1'b0;
        wr_in_pkt    <= 1'b0;
        wr_ptr       <= {PTR_W{1'b0}};
        rd_bank      <= 1'b0;
        rd_active    <= 1'b0;
        rd_ptr       <= {PTR_W{1'b0}};
        out_word     <= {WORD_W{1'b0}};
        out_word_valid <= 1'b0;
        rd_data_pending <= 1'b0;
        rd_data_bank    <= 1'b0;
    end else begin
        // Launch a read when idle and at least one bank is full.
        if (!rd_active) begin
            if (bank_full[rd_bank]) begin
                rd_active <= 1'b1;
                rd_ptr    <= {PTR_W{1'b0}};
            end else if (bank_full[~rd_bank]) begin
                rd_bank   <= ~rd_bank;
                rd_active <= 1'b1;
                rd_ptr    <= {PTR_W{1'b0}};
            end
        end

        // Track BRAM read requests and capture returned data (1-cycle latency).
        if (rd_req_fire) begin
            rd_data_pending <= 1'b1;
            rd_data_bank    <= rd_req_bank;
        end else if (rd_data_pending) begin
            rd_data_pending <= 1'b0;
            out_word        <= rd_data_bank ? bram1_dout : bram0_dout;
            out_word_valid  <= 1'b1;
        end

        if (in_hs) begin
            // Start packet on selected writable bank.
            if (!wr_in_pkt) begin
                wr_bank   <= sel_wr_bank;
                wr_in_pkt <= 1'b1;
                wr_ptr    <= {PTR_W{1'b0}};
            end

            if (i_s_axis_tlast) begin
                // Packet complete: mark bank full and switch preferred bank.
                if (wr_in_pkt ? wr_bank : sel_wr_bank)
                    bank_full[1] <= 1'b1;
                else
                    bank_full[0] <= 1'b1;

                wr_in_pkt <= 1'b0;
                wr_ptr    <= {PTR_W{1'b0}};
                wr_bank   <= ~(wr_in_pkt ? wr_bank : sel_wr_bank);
            end else begin
                wr_ptr <= wr_ptr + 1'b1;
            end
        end

        if (out_hs) begin
            if (out_word[DATA_WIDTH]) begin
                // End of packet: free bank and prepare to alternate.
                bank_full[rd_bank] <= 1'b0;
                rd_active          <= 1'b0;
                rd_ptr             <= {PTR_W{1'b0}};
                rd_bank            <= ~rd_bank;
                out_word_valid     <= 1'b0;
            end else begin
                rd_ptr <= rd_ptr + 1'b1;
                out_word_valid <= 1'b0;
            end
        end
    end
end

endmodule

`default_nettype wire
