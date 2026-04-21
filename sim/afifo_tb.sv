`timescale 1ns/1ps
`default_nettype none

module afifo_tb;
    localparam integer CLK_125_HALF_NS = 4;
    localparam integer CLK_166_HALF_NS = 3;
    localparam integer CLK_100_HALF_NS = 5;
    localparam int unsigned CLK_HZ = 166_666_667;
    localparam int unsigned BIT_RATE_BPS = 5_000_000;
    localparam real CLK_PERIOD_NS = 6.0;
    localparam int BURST_BYTES = 64;
    localparam int BURST_WORDS = BURST_BYTES/2;
    localparam int BURST_COUNT = 100;
    localparam time BURST_GAP = 850_000ns;
    localparam logic [63:0] START_SEQ_64 = 64'hD5_AA_96_C3_F0_0F_5A_3C;
    localparam logic [63:0] STOP_SEQ_64  = 64'h3C_5A_0F_F0_C3_96_AA_D5;
    localparam int FRAMED_BYTES_PER_BURST = BURST_BYTES + 16;

    reg i_clk = 1'b0;
    reg i_dac1_clk = 1'b0;
    reg i_dac2_clk = 1'b0;
    reg i_eth_clk = 1'b0;
    always #CLK_125_HALF_NS i_clk = ~i_clk;
    always #CLK_166_HALF_NS i_dac1_clk = ~i_dac1_clk;
    always #CLK_166_HALF_NS i_dac2_clk = ~i_dac2_clk;
    always #CLK_100_HALF_NS i_eth_clk = ~i_eth_clk;

    reg         i_rst = 1'b1;
    reg         i_tone_mode = 1'b0;
    reg [31:0]  i_tone_pinc = 32'h0000_1200;
    reg [7:0]   i_s_axis_tdata = 8'd0;
    reg         i_s_axis_tvalid = 1'b0;
    wire        o_s_axis_tready;
    reg         i_s_axis_tlast = 1'b0;

    wire [7:0]  o_m_axis_tdata;
    wire        o_m_axis_tvalid;
    reg         i_m_axis_tready = 1'b1;
    wire        o_m_axis_tlast;

    wire        o_dac_sample_valid;
    wire [13:0] o_dac1_h;
    wire [13:0] o_dac1_l;
    wire [13:0] o_dac2_h;
    wire [13:0] o_dac2_l;

    integer dac_sign_flip_count = 0;
    reg signed [13:0] prev_dac_i = 14'sd0;

    reg [7:0]  tb_eth_data = 8'd0;
    reg [7:0]  tb_pattern_idx = 8'd0;
    reg        tb_eth_valid = 1'b0;
    wire [15:0] tb_fifo_data;
    wire        tb_fifo_valid;
    reg [15:0] axis_word_buf = 16'd0;
    reg        axis_have_word = 1'b0;
    reg        axis_send_hi = 1'b0;

    afifo_wrapper tb_ingress_cdc (
        .i_r_clk(i_clk),
        .i_w_clk(i_eth_clk),
        .i_w_rst(i_rst),
        .i_w_data(tb_eth_data),
        .i_w_valid(tb_eth_valid),
        .o_r_data(tb_fifo_data),
        .o_data_valid(tb_fifo_valid)
    );

    qpsk_tx_modulator #(
    .CLK_HZ(CLK_HZ),
    .BIT_RATE_BPS(BIT_RATE_BPS),
    .FIFO_DEPTH(2048),
    .PAYLOAD_BYTES_PER_PACKET(BURST_BYTES),
    .START_SEQ_64(START_SEQ_64),
    .STOP_SEQ_64(STOP_SEQ_64),
    .SYMBOL_AMP(14'sd6000),
    .ENABLE_SHAPING(1'b0),
    .ENABLE_RRC(1'b1)
) dut (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_word_data(tb_fifo_data),
    .i_word_valid(tb_fifo_valid),
    .o_word_ready(),
    .o_sample_valid(),
    .o_i(o_dac1_h),
    .o_q(o_dac1_l),
    .o_symbol_tick(),
    .o_dbg_symbol_bits()
);

/*     iq_codec_loop dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_dac1_clk(i_dac1_clk),
        .i_dac2_clk(i_dac2_clk),
        .i_tone_mode(i_tone_mode),
        .i_tone_pinc(i_tone_pinc),
        .i_s_axis_tdata(i_s_axis_tdata),
        .i_s_axis_tvalid(i_s_axis_tvalid),
        .o_s_axis_tready(o_s_axis_tready),
        .i_s_axis_tlast(i_s_axis_tlast),
        .o_m_axis_tdata(o_m_axis_tdata),
        .o_m_axis_tvalid(o_m_axis_tvalid),
        .i_m_axis_tready(i_m_axis_tready),
        .o_m_axis_tlast(o_m_axis_tlast),
        .o_dac_sample_valid(o_dac_sample_valid),
        .o_dac1_h(o_dac1_h),
        .o_dac1_l(o_dac1_l),
        .o_dac2_h(o_dac2_h),
        .o_dac2_l(o_dac2_l)
    ); */

    // ----------------------------------------------------------------
    // Stimulus: BURST_COUNT x BURST_BYTES bursts, BURST_GAP idle between
    // ----------------------------------------------------------------
    initial begin
        i_rst      = 1'b1;
        tb_eth_data = 8'd0;
           tb_eth_valid = 1'b0;
        repeat(20) @(posedge i_eth_clk);
        i_rst = 1'b0;

        repeat(BURST_COUNT) begin
            for (int b = 0; b < BURST_BYTES; b++) begin
                @(posedge i_eth_clk);
                   tb_eth_data  = 8'hAA;
                   tb_eth_valid = 1'b1;
            end
            @(posedge i_eth_clk);
               tb_eth_valid = 1'b0;           // stop writing during gap

            #BURST_GAP;                    // 850 us idle between bursts
        end

        #(BURST_GAP);
       // $finish;
    end

endmodule




`default_nettype wire
