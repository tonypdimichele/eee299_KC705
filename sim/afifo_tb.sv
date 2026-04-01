`timescale 1ns/1ps
`default_nettype none

module afifo_tb;
    localparam integer CLK_125_HALF_NS = 4;
    localparam integer CLK_166_HALF_NS = 3;
    localparam integer CLK_100_HALF_NS = 5;

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
        .o_r_data(tb_fifo_data),
        .o_data_valid(tb_fifo_valid)
    );

    iq_codec_loop dut (
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
    );

    always @(posedge i_eth_clk) begin
        if (i_rst) begin
            tb_pattern_idx <= 8'd0;
            tb_eth_data <= 8'hF0;
        end else begin
            // Non-zero pattern bytes: afifo_wrapper writes only when i_w_data != 0.
            case (tb_pattern_idx[2:0])
                3'd0: tb_eth_data <= 8'hAA;
                3'd1: tb_eth_data <= 8'h55;
                3'd2: tb_eth_data <= 8'hF0;
                3'd3: tb_eth_data <= 8'h0F;
                3'd4: tb_eth_data <= 8'hCC;
                3'd5: tb_eth_data <= 8'h33;
                3'd6: tb_eth_data <= 8'hFE;
                default: tb_eth_data <= 8'h7F;
            endcase
            tb_pattern_idx <= tb_pattern_idx + 1'b1;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            i_s_axis_tvalid <= 1'b0;
            i_s_axis_tdata <= 8'd0;
            i_s_axis_tlast <= 1'b0;
            axis_word_buf <= 16'd0;
            axis_have_word <= 1'b0;
            axis_send_hi <= 1'b0;
        end else begin
            i_s_axis_tlast <= 1'b0;

            if (i_s_axis_tvalid && o_s_axis_tready) begin
                i_s_axis_tvalid <= 1'b0;
                if (axis_send_hi) begin
                    axis_send_hi <= 1'b0;
                    axis_have_word <= 1'b0;
                end else begin
                    axis_send_hi <= 1'b1;
                end
            end

            if (!i_s_axis_tvalid) begin
                if (!axis_have_word && tb_fifo_valid) begin
                    axis_word_buf <= tb_fifo_data;
                    axis_have_word <= 1'b1;
                    axis_send_hi <= 1'b0;
                end

                if (axis_have_word) begin
                    i_s_axis_tdata <= axis_send_hi ? axis_word_buf[15:8] : axis_word_buf[7:0];
                    i_s_axis_tvalid <= 1'b1;
                end
            end
        end
    end

    always @(posedge i_dac1_clk) begin
        if (!i_rst && o_dac_sample_valid) begin
            if (o_dac1_h[13] ^ prev_dac_i[13]) begin
                dac_sign_flip_count <= dac_sign_flip_count + 1;
            end
            prev_dac_i <= o_dac1_h;
        end
    end

    initial begin
        repeat (20) @(posedge i_clk);
        i_rst <= 1'b0;

        repeat (4000) @(posedge i_dac1_clk);
        $display("BPSK TB done: dac_sign_flip_count=%0d last_I=%0d last_Q=%0d",
                 dac_sign_flip_count, $signed(o_dac1_h), $signed(o_dac1_l));
        $finish;
    end

endmodule




`default_nettype wire
