`timescale 1ns / 1ps
`default_nettype none

module tb_iq_codec_tone;

    // ------------------------------------------------------------------
    // Clocks:  sys = 125 MHz (8 ns),  DAC = 50 MHz (20 ns)
    // ------------------------------------------------------------------
    localparam real SYS_HALF_PERIOD = 4.0;   // ns  (125 MHz)
    localparam real DAC_HALF_PERIOD = 10.0;  // ns  (50 MHz)

    logic clk     = 1'b0;
    logic dac_clk = 1'b0;
    logic rst     = 1'b1;

    always #(SYS_HALF_PERIOD) clk     = ~clk;
    always #(DAC_HALF_PERIOD) dac_clk = ~dac_clk;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    logic        tone_mode;
    logic [7:0]  s_axis_tdata;
    logic        s_axis_tvalid;
    wire         s_axis_tready;
    logic        s_axis_tlast;

    wire  [7:0]  m_axis_tdata;
    wire         m_axis_tvalid;
    logic        m_axis_tready;
    wire         m_axis_tlast;

    wire         dac_sample_valid;
    wire  [13:0] dac1_h, dac1_l, dac2_h, dac2_l;

    iq_codec_loop dut (
        .i_clk           (clk),
        .i_rst           (rst),
        .i_dac1_clk      (dac_clk),
        .i_dac2_clk      (dac_clk),
        .i_tone_mode     (tone_mode),
        .i_s_axis_tdata  (s_axis_tdata),
        .i_s_axis_tvalid (s_axis_tvalid),
        .o_s_axis_tready (s_axis_tready),
        .i_s_axis_tlast  (s_axis_tlast),
        .o_m_axis_tdata  (m_axis_tdata),
        .o_m_axis_tvalid (m_axis_tvalid),
        .i_m_axis_tready (m_axis_tready),
        .o_m_axis_tlast  (m_axis_tlast),
        .o_dac_sample_valid (dac_sample_valid),
        .o_dac1_h        (dac1_h),
        .o_dac1_l        (dac1_l),
        .o_dac2_h        (dac2_h),
        .o_dac2_l        (dac2_l)
    );

    // ------------------------------------------------------------------
    // Convert offset-binary DAC output back to signed for easy viewing
    // ------------------------------------------------------------------
    wire signed [14:0] dac1_h_signed = $signed({1'b0, dac1_h}) - 15'sd8192;
    wire signed [14:0] dac1_l_signed = $signed({1'b0, dac1_l}) - 15'sd8192;
    wire signed [14:0] dac2_h_signed = $signed({1'b0, dac2_h}) - 15'sd8192;
    wire signed [14:0] dac2_l_signed = $signed({1'b0, dac2_l}) - 15'sd8192;

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_iq_codec_tone.vcd");
        $dumpvars(0, tb_iq_codec_tone);

        // Park AXI-Stream inputs
        tone_mode     = 1'b0;
        s_axis_tdata  = 8'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;

        // Hold reset for 200 ns
        #200;
        @(posedge clk);
        rst = 1'b0;

        // Let system settle for 100 ns then enable tone mode
        #100;
        @(posedge clk);
        tone_mode = 1'b1;

        // Run for 1 ms  (1_000_000 ns)
        #1_000_000;

        $display("=== Simulation complete: 1 ms of tone-mode output ===");
        $display("DAC clock = 50 MHz, TONE_PHASE_INC = 3356");
        $display("Expected tone freq = 50e6 * 3356 / 2^24 = %.1f Hz",
                  50.0e6 * 3356.0 / (2.0**24));
        $finish;
    end

endmodule

`default_nettype wire
