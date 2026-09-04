`timescale 1ns / 1ps
`default_nettype none
//
// tb_qpsk_loopback.sv
//
// End-to-end simulation of the QPSK packet modem:
//   TX framer -> channel model -> RX demodulator
//
// Tests:
//   1. Perfect loopback (no noise, no phase offset)
//   2. Loopback with 90-degree phase rotation
//   3. Loopback with 180-degree phase rotation
//   4. Loopback with 270-degree phase rotation
//   5. Loopback with timing offset (non-aligned dump boundaries)
//   6. Multiple back-to-back frames
//
module tb_qpsk_loopback;

// ──────────────────────────────────────────────────────────────────────
// Parameters
// ──────────────────────────────────────────────────────────────────────
localparam real DAC_CLK_PERIOD_NS = 6.0;            // 166.67 MHz
localparam real ADC_CLK_PERIOD_NS = 8.0;            // 125 MHz
localparam int  CLKS_PER_SYMBOL   = 32;
localparam int  SAMPLES_PER_SYMBOL = 24;
localparam int  PAYLOAD_BYTES     = 32;
localparam int  PREAMBLE_LEN      = 20;
localparam int  POSTAMBLE_LEN     = 20;
localparam int  TOTAL_SYMBOLS     = PREAMBLE_LEN + PAYLOAD_BYTES*4 + POSTAMBLE_LEN;
// A true 8-symbol sync match reaches ~498,000 at this amplitude/window. But the
// correlator also sees a partial-match sidelobe of ~276,000 when its 8-symbol
// window straddles the tail of the timing preamble and the head of the sync
// section (2 symbols before the true alignment) -- 250000 was low enough to let
// that sidelobe false-lock the receiver 2 symbols early, corrupting every byte.
// 400000 sits with margin above the sidelobe and below the true peak.
localparam int  CORR_THRESHOLD    = 400000;

// ──────────────────────────────────────────────────────────────────────
// Clocks & Resets
// ──────────────────────────────────────────────────────────────────────
logic dac_clk = 1'b0;
logic adc_clk = 1'b0;
logic rst     = 1'b1;

always #(DAC_CLK_PERIOD_NS/2.0) dac_clk = ~dac_clk;
always #(ADC_CLK_PERIOD_NS/2.0) adc_clk = ~adc_clk;

// ──────────────────────────────────────────────────────────────────────
// TX Framer Signals
// ──────────────────────────────────────────────────────────────────────
logic [7:0]  tx_tdata;
logic        tx_tvalid;
wire         tx_tready;
logic        tx_tlast;

wire signed [13:0] tx_i_sample;
wire signed [13:0] tx_q_sample;
wire               tx_symbol_valid;
wire               tx_frame_active;

qpsk_tx_framer #(
    .CLKS_PER_SYMBOL(CLKS_PER_SYMBOL),
    .PAYLOAD_BYTES(PAYLOAD_BYTES),
    .PREAMBLE_LEN(PREAMBLE_LEN),
    .POSTAMBLE_LEN(POSTAMBLE_LEN),
    .SYMBOL_AMP(14'sd6000)
) u_tx (
    .i_clk(dac_clk),
    .i_rst(rst),
    .i_s_axis_tdata(tx_tdata),
    .i_s_axis_tvalid(tx_tvalid),
    .o_s_axis_tready(tx_tready),
    .i_s_axis_tlast(tx_tlast),
    .o_i_sample(tx_i_sample),
    .o_q_sample(tx_q_sample),
    .o_symbol_valid(tx_symbol_valid),
    .o_frame_active(tx_frame_active)
);

// ──────────────────────────────────────────────────────────────────────
// Channel Model
// ──────────────────────────────────────────────────────────────────────
// Models:
//   - Clock domain crossing (DAC -> ADC, asynchronous)
//   - Optional phase rotation (0, 90, 180, 270 degrees)
//   - Amplitude scaling (14-bit DAC -> 12-bit ADC range)
//   - Optional timing offset
//
logic [1:0] channel_phase_rot = 2'd0;  // 0=0, 1=90, 2=180, 3=270 degrees
logic signed [13:0] ch_i_dac, ch_q_dac;
logic signed [11:0] ch_i_adc, ch_q_adc;

// Latch DAC outputs (simulate DAC hold behavior)
always @(posedge dac_clk) begin
    if (rst) begin
        ch_i_dac <= 14'sd0;
        ch_q_dac <= 14'sd0;
    end else begin
        ch_i_dac <= tx_i_sample;
        ch_q_dac <= tx_q_sample;
    end
end

// Phase rotation + scale (14-bit -> 12-bit with sign extension)
logic signed [13:0] rot_i, rot_q;
always_comb begin
    case (channel_phase_rot)
        2'd0: begin rot_i =  ch_i_dac; rot_q =  ch_q_dac; end  // 0 deg
        2'd1: begin rot_i =  ch_q_dac; rot_q = -ch_i_dac; end  // +90 deg
        2'd2: begin rot_i = -ch_i_dac; rot_q = -ch_q_dac; end  // +180 deg
        2'd3: begin rot_i = -ch_q_dac; rot_q =  ch_i_dac; end  // +270 deg
    endcase
end

// Scale 14-bit signed to 12-bit signed (shift right 2, preserving sign)
wire signed [11:0] scaled_i = rot_i[13:2];
wire signed [11:0] scaled_q = rot_q[13:2];

// CDC: sample into ADC clock domain (models asynchronous nature)
always @(posedge adc_clk) begin
    if (rst) begin
        ch_i_adc <= 12'sd0;
        ch_q_adc <= 12'sd0;
    end else begin
        ch_i_adc <= scaled_i;
        ch_q_adc <= scaled_q;
    end
end

// ──────────────────────────────────────────────────────────────────────
// RX Demodulator
// ──────────────────────────────────────────────────────────────────────
wire [7:0]  rx_tdata;
wire        rx_tvalid;
wire        rx_tlast;
wire        rx_frame_detected;
wire        rx_frame_done;
wire [1:0]  rx_phase_rot;

qpsk_rx_demod #(
    .SAMPLES_PER_SYMBOL(SAMPLES_PER_SYMBOL),
    .PAYLOAD_BYTES(PAYLOAD_BYTES),
    .PREAMBLE_LEN(PREAMBLE_LEN),
    .POSTAMBLE_LEN(POSTAMBLE_LEN),
    .CORR_THRESHOLD(CORR_THRESHOLD)
) u_rx (
    .i_clk(adc_clk),
    .i_rst(rst),
    .i_sample_i(ch_i_adc),
    .i_sample_q(ch_q_adc),
    .i_sample_valid(1'b1),
    .i_corr_threshold(24'(CORR_THRESHOLD)),
    .o_m_axis_tdata(rx_tdata),
    .o_m_axis_tvalid(rx_tvalid),
    .i_m_axis_tready(1'b1),
    .o_m_axis_tlast(rx_tlast),
    .o_frame_detected(rx_frame_detected),
    .o_frame_done(rx_frame_done),
    .o_phase_rot(rx_phase_rot),
    .o_corr_mag()
);

// ──────────────────────────────────────────────────────────────────────
// Carrier path (TX mixer -> channel -> RX downmix -> second RX demod)
// Validates the AC-coupling mitigation added to iq_codec_loop.sv /
// KC705_EEE299_top.v before committing to hardware bring-up.
// ──────────────────────────────────────────────────────────────────────
wire signed [13:0] tx_i_carrier, tx_q_carrier;

qpsk_tx_carrier_mix #(.CARRIER_PERIOD(8), .CARRIER_AMP(14'sd8000)) u_tx_mix_i (
    .i_clk(dac_clk), .i_rst(rst), .i_frame_active(tx_frame_active),
    .i_sample(tx_i_sample), .o_carrier_sample(tx_i_carrier)
);
qpsk_tx_carrier_mix #(.CARRIER_PERIOD(8), .CARRIER_AMP(14'sd8000)) u_tx_mix_q (
    .i_clk(dac_clk), .i_rst(rst), .i_frame_active(tx_frame_active),
    .i_sample(tx_q_sample), .o_carrier_sample(tx_q_carrier)
);

logic signed [13:0] ch2_i_dac, ch2_q_dac;
always @(posedge dac_clk) begin
    if (rst) begin
        ch2_i_dac <= 14'sd0;
        ch2_q_dac <= 14'sd0;
    end else begin
        ch2_i_dac <= tx_i_carrier;
        ch2_q_dac <= tx_q_carrier;
    end
end

logic signed [13:0] rot2_i, rot2_q;
always_comb begin
    case (channel_phase_rot)
        2'd0: begin rot2_i =  ch2_i_dac; rot2_q =  ch2_q_dac; end
        2'd1: begin rot2_i =  ch2_q_dac; rot2_q = -ch2_i_dac; end
        2'd2: begin rot2_i = -ch2_i_dac; rot2_q = -ch2_q_dac; end
        2'd3: begin rot2_i = -ch2_q_dac; rot2_q =  ch2_i_dac; end
    endcase
end

wire signed [11:0] scaled2_i = rot2_i[13:2];
wire signed [11:0] scaled2_q = rot2_q[13:2];

logic signed [11:0] ch2_i_adc, ch2_q_adc;
always @(posedge adc_clk) begin
    if (rst) begin
        ch2_i_adc <= 12'sd0;
        ch2_q_adc <= 12'sd0;
    end else begin
        ch2_i_adc <= scaled2_i;
        ch2_q_adc <= scaled2_q;
    end
end

logic [2:0] carrier_phase_offset = 3'd0;
wire signed [11:0] downmix_i, downmix_q;

qpsk_rx_downmix u_rx_downmix (
    .i_clk(adc_clk), .i_rst(rst), .i_enable(1'b1),
    .i_phase_offset(carrier_phase_offset),
    .i_sample_i(ch2_i_adc), .i_sample_q(ch2_q_adc),
    .o_sample_i(downmix_i), .o_sample_q(downmix_q)
);

wire [7:0]  rx2_tdata;
wire        rx2_tvalid;
wire        rx2_tlast;
wire        rx2_frame_done;
wire [1:0]  rx2_phase_rot;

qpsk_rx_demod #(
    .SAMPLES_PER_SYMBOL(SAMPLES_PER_SYMBOL),
    .PAYLOAD_BYTES(PAYLOAD_BYTES),
    .PREAMBLE_LEN(PREAMBLE_LEN),
    .POSTAMBLE_LEN(POSTAMBLE_LEN),
    .CORR_THRESHOLD(CORR_THRESHOLD)
) u_rx2 (
    .i_clk(adc_clk),
    .i_rst(rst),
    .i_sample_i(downmix_i),
    .i_sample_q(downmix_q),
    .i_sample_valid(1'b1),
    .i_corr_threshold(24'(CORR_THRESHOLD)),
    .o_m_axis_tdata(rx2_tdata),
    .o_m_axis_tvalid(rx2_tvalid),
    .i_m_axis_tready(1'b1),
    .o_m_axis_tlast(rx2_tlast),
    .o_frame_detected(),
    .o_frame_done(rx2_frame_done),
    .o_phase_rot(rx2_phase_rot),
    .o_corr_mag()
);

// ──────────────────────────────────────────────────────────────────────
// Test Infrastructure
// ──────────────────────────────────────────────────────────────────────
logic [7:0] tx_payload [0:PAYLOAD_BYTES-1];
logic [7:0] rx_payload [0:PAYLOAD_BYTES-1];
logic [7:0] rx2_payload [0:PAYLOAD_BYTES-1];
int         rx_byte_cnt;
int         rx2_byte_cnt;
int         test_pass_cnt;
int         test_fail_cnt;
int         test_num;
string      test_name;

// Capture RX output bytes
always @(posedge adc_clk) begin
    if (rst) begin
        rx_byte_cnt <= 0;
    end else if (rx_tvalid) begin
        if (rx_byte_cnt < PAYLOAD_BYTES) begin
            rx_payload[rx_byte_cnt] <= rx_tdata;
        end
        rx_byte_cnt <= rx_byte_cnt + 1;
    end
end

// Capture carrier-path RX output bytes
always @(posedge adc_clk) begin
    if (rst) begin
        rx2_byte_cnt <= 0;
    end else if (rx2_tvalid) begin
        if (rx2_byte_cnt < PAYLOAD_BYTES) begin
            rx2_payload[rx2_byte_cnt] <= rx2_tdata;
        end
        rx2_byte_cnt <= rx2_byte_cnt + 1;
    end
end

// ──────────────────────────────────────────────────────────────────────
// Tasks
// ──────────────────────────────────────────────────────────────────────

// Send a frame of payload data through the TX framer
task automatic send_frame(input logic [7:0] payload [0:PAYLOAD_BYTES-1]);
    int i;
    begin
        @(posedge dac_clk);
        for (i = 0; i < PAYLOAD_BYTES; i++) begin
            tx_tdata  <= payload[i];
            tx_tvalid <= 1'b1;
            tx_tlast  <= (i == PAYLOAD_BYTES - 1);
            @(posedge dac_clk);
            while (!tx_tready) @(posedge dac_clk);
        end
        tx_tvalid <= 1'b0;
        tx_tlast  <= 1'b0;
    end
endtask

// Wait for RX to output a full frame (or timeout)
task automatic wait_rx_frame(input int timeout_us, output bit success);
    int timeout_cycles;
    int waited;
    begin
        timeout_cycles = int'(timeout_us * 1000.0 / ADC_CLK_PERIOD_NS);
        waited = 0;
        success = 0;
        while (waited < timeout_cycles) begin
            @(posedge adc_clk);
            waited++;
            if (rx_frame_done) begin
                // Wait a few more cycles for output to complete
                repeat(PAYLOAD_BYTES + 10) @(posedge adc_clk);
                success = 1;
                return;
            end
        end
    end
endtask

// Compare TX and RX payloads
task automatic check_payload(output int errors);
    int i;
    begin
        errors = 0;
        for (i = 0; i < PAYLOAD_BYTES; i++) begin
            if (rx_payload[i] !== tx_payload[i]) begin
                if (errors < 8) begin
                    $display("    MISMATCH byte[%0d]: TX=0x%02X, RX=0x%02X",
                             i, tx_payload[i], rx_payload[i]);
                end
                errors++;
            end
        end
    end
endtask

// Carrier-path (TX mixer -> channel -> RX downmix) equivalents of the above
task automatic wait_rx2_frame(input int timeout_us, output bit success);
    int timeout_cycles;
    int waited;
    begin
        timeout_cycles = int'(timeout_us * 1000.0 / ADC_CLK_PERIOD_NS);
        waited = 0;
        success = 0;
        while (waited < timeout_cycles) begin
            @(posedge adc_clk);
            waited++;
            if (rx2_frame_done) begin
                repeat(PAYLOAD_BYTES + 10) @(posedge adc_clk);
                success = 1;
                return;
            end
        end
    end
endtask

task automatic check_payload2(output int errors);
    int i;
    begin
        errors = 0;
        for (i = 0; i < PAYLOAD_BYTES; i++) begin
            if (rx2_payload[i] !== tx_payload[i]) begin
                if (errors < 8) begin
                    $display("    MISMATCH byte[%0d]: TX=0x%02X, RX2=0x%02X",
                             i, tx_payload[i], rx2_payload[i]);
                end
                errors++;
            end
        end
    end
endtask

// Sweep carrier_phase_offset (0..CARRIER_PERIOD-1) for one payload, reporting
// pass/fail per offset. Since dac_clk/adc_clk are free-running/asynchronous
// in this testbench (unlike the shared-reference hardware clocks), this also
// exercises the fixed-phase-offset calibration concept end to end.
task automatic run_carrier_test(input logic [7:0] payload [0:PAYLOAD_BYTES-1]);
    bit rx_ok;
    int errs;
    int pass_count;
    begin
        pass_count = 0;
        for (int off = 0; off < 6; off++) begin
            test_num++;
            $display("\n[TEST %0d] Carrier path, phase_offset=%0d", test_num, off);
            carrier_phase_offset = off[2:0];
            for (int i = 0; i < PAYLOAD_BYTES; i++) tx_payload[i] = payload[i];
            @(posedge adc_clk);
            rx2_byte_cnt <= 0;
            repeat(100) @(posedge adc_clk);
            send_frame(payload);
            wait_rx2_frame(200, rx_ok);
            if (!rx_ok) begin
                $display("    FAIL: RX2 timeout - no frame detected");
                test_fail_cnt++;
            end else begin
                check_payload2(errs);
                if (errs == 0) begin
                    $display("    PASS: All %0d bytes match", PAYLOAD_BYTES);
                    test_pass_cnt++;
                    pass_count++;
                end else begin
                    $display("    FAIL: %0d/%0d byte errors", errs, PAYLOAD_BYTES);
                    test_fail_cnt++;
                end
            end
            repeat(500) @(posedge adc_clk);
        end
        $display("\n  Carrier-path summary: %0d/6 phase offsets passed", pass_count);
    end
endtask

logic [3:0] test_number;
// Run a single test case
task automatic run_test(
    input string name,
    input logic [1:0] phase,
    input logic [7:0] payload [0:PAYLOAD_BYTES-1],
    output logic [3:0] test_number
);
    bit rx_ok;
    int errs;
    begin
        test_num++;
        test_number = test_num;
        test_name = name;
        $display("\n[TEST %0d] %s (phase_rot=%0d)", test_num, name, phase);

        // Set channel conditions
        channel_phase_rot = phase;

        // Store TX payload for comparison
        for (int i = 0; i < PAYLOAD_BYTES; i++) tx_payload[i] = payload[i];

        // Reset RX byte counter
        @(posedge adc_clk);
        rx_byte_cnt <= 0;

        // Small settling time
        repeat(100) @(posedge adc_clk);

        // Send frame
        send_frame(payload);

        // Wait for RX
        wait_rx_frame(200, rx_ok);  // 200 us timeout

        if (!rx_ok) begin
            $display("    FAIL: RX timeout - no frame detected");
            test_fail_cnt++;
            return;
        end

        $display("    Frame detected! Phase rotation detected: %0d", rx_phase_rot);

        // Check data
        check_payload(errs);
        if (errs == 0) begin
            $display("    PASS: All %0d bytes match", PAYLOAD_BYTES);
            test_pass_cnt++;
        end else begin
            $display("    FAIL: %0d/%0d byte errors", errs, PAYLOAD_BYTES);
            test_fail_cnt++;
        end

        // Inter-frame gap
        repeat(500) @(posedge adc_clk);
    end
    test_number = test_num;
endtask

// ──────────────────────────────────────────────────────────────────────
// Main Test Sequence
// ──────────────────────────────────────────────────────────────────────
logic [7:0] payload_ramp [0:PAYLOAD_BYTES-1];
logic [7:0] payload_aa55 [0:PAYLOAD_BYTES-1];
logic [7:0] payload_rand [0:PAYLOAD_BYTES-1];
logic [7:0] payload_zero [0:PAYLOAD_BYTES-1];
logic [7:0] payload_ff   [0:PAYLOAD_BYTES-1];

initial begin
    // Generate test patterns
    for (int i = 0; i < PAYLOAD_BYTES; i++) begin
        payload_ramp[i] = i[7:0];
        payload_aa55[i] = (i % 2 == 0) ? 8'hAA : 8'h55;
        payload_rand[i] = $urandom_range(0, 255);
        payload_zero[i] = 8'h00;
        payload_ff[i]   = 8'hFF;
    end

    // Init signals
    tx_tdata  = 8'd0;
    tx_tvalid = 1'b0;
    tx_tlast  = 1'b0;
    test_pass_cnt = 0;
    test_fail_cnt = 0;
    test_num = 0;

    // Reset
    rst = 1'b1;
    repeat(50) @(posedge dac_clk);
    rst = 1'b0;
    repeat(100) @(posedge dac_clk);

    $display("═══════════════════════════════════════════════════════════");
    $display(" QPSK Packet Modem Loopback Testbench");
    $display(" DAC clock: %.2f MHz, ADC clock: %.2f MHz",
             1000.0/DAC_CLK_PERIOD_NS, 1000.0/ADC_CLK_PERIOD_NS);
    $display(" Symbol rate: %.3f Msym/s (%0d DAC clks/sym)",
             1000.0/(DAC_CLK_PERIOD_NS*CLKS_PER_SYMBOL), CLKS_PER_SYMBOL);
    $display(" Samples/symbol at RX: %0d", SAMPLES_PER_SYMBOL);
    $display(" Frame: %0d preamble + %0d data + %0d postamble = %0d symbols",
             PREAMBLE_LEN, PAYLOAD_BYTES*4, POSTAMBLE_LEN, TOTAL_SYMBOLS);
    $display("═══════════════════════════════════════════════════════════");

    // ──────────────────────────────────────────────────────────────
    // Test 1: Perfect channel, ramp data
    // ──────────────────────────────────────────────────────────────
    run_test("Perfect channel, ramp data", 2'd0, payload_ramp, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 2: Perfect channel, alternating 0xAA/0x55
    // ──────────────────────────────────────────────────────────────
    run_test("Perfect channel, AA/55 pattern", 2'd0, payload_aa55, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 3: 90-degree phase rotation
    // ──────────────────────────────────────────────────────────────
    run_test("90-degree phase rotation, ramp", 2'd1, payload_ramp, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 4: 180-degree phase rotation
    // ──────────────────────────────────────────────────────────────
    run_test("180-degree phase rotation, ramp", 2'd2, payload_ramp, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 5: 270-degree phase rotation
    // ──────────────────────────────────────────────────────────────
    run_test("270-degree phase rotation, ramp", 2'd3, payload_ramp, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 6: Random data, no rotation
    // ──────────────────────────────────────────────────────────────
    run_test("Random data, no rotation", 2'd0, payload_rand, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 7: All zeros
    // ──────────────────────────────────────────────────────────────
    run_test("All-zero payload", 2'd0, payload_zero, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 8: All ones
    // ──────────────────────────────────────────────────────────────
    run_test("All-ones payload", 2'd0, payload_ff, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 9: Random data with 90-degree rotation
    // ──────────────────────────────────────────────────────────────
    run_test("Random data, 90-degree rotation", 2'd1, payload_rand, test_number);

    // ──────────────────────────────────────────────────────────────
    // Test 10: Back-to-back frames (stress inter-frame gap)
    // ──────────────────────────────────────────────────────────────
    $display("\n[TEST %0d] Back-to-back frames (3 sequential)", test_num+1);
    test_num++;
    begin
        int total_errs;
        bit all_ok;
        total_errs = 0;
        all_ok = 1;
        channel_phase_rot = 2'd0;

        for (int frame = 0; frame < 3; frame++) begin
            bit rx_ok;
            int errs;
            logic [7:0] p [0:PAYLOAD_BYTES-1];

            for (int i = 0; i < PAYLOAD_BYTES; i++) p[i] = (frame*32 + i) & 8'hFF;
            for (int i = 0; i < PAYLOAD_BYTES; i++) tx_payload[i] = p[i];

            @(posedge adc_clk);
            rx_byte_cnt <= 0;
            repeat(50) @(posedge adc_clk);

            send_frame(p);
            wait_rx_frame(200, rx_ok);

            if (!rx_ok) begin
                $display("    Frame %0d: TIMEOUT", frame);
                all_ok = 0;
            end else begin
                check_payload(errs);
                total_errs += errs;
                if (errs > 0) begin
                    $display("    Frame %0d: %0d errors", frame, errs);
                    all_ok = 0;
                end else begin
                    $display("    Frame %0d: OK", frame);
                end
            end
            repeat(300) @(posedge adc_clk);
        end

        if (all_ok) begin
            $display("    PASS: All 3 back-to-back frames decoded correctly");
            test_pass_cnt++;
        end else begin
            $display("    FAIL: %0d total byte errors across frames", total_errs);
            test_fail_cnt++;
        end
    end

    // ──────────────────────────────────────────────────────────────
    // Test 11: Carrier path (qpsk_tx_carrier_mix -> channel -> qpsk_rx_downmix)
    // Sweeps calibration phase offset since dac_clk/adc_clk are free-running
    // in this testbench, mirroring the real fixed-but-unknown cable delay.
    // ──────────────────────────────────────────────────────────────
    channel_phase_rot = 2'd0;
    run_carrier_test(payload_ramp);

    // ──────────────────────────────────────────────────────────────
    // Summary
    // ──────────────────────────────────────────────────────────────
    $display("\n═══════════════════════════════════════════════════════════");
    $display(" RESULTS: %0d PASSED, %0d FAILED out of %0d tests",
             test_pass_cnt, test_fail_cnt, test_num);
    $display("═══════════════════════════════════════════════════════════");

    if (test_fail_cnt == 0)
        $display(" *** ALL TESTS PASSED ***");
    else
        $display(" *** SOME TESTS FAILED ***");

    $finish;
end

// ──────────────────────────────────────────────────────────────────────
// Waveform Dump
// ──────────────────────────────────────────────────────────────────────
initial begin
    $dumpfile("tb_qpsk_loopback.vcd");
    $dumpvars(0, tb_qpsk_loopback);
end

// ──────────────────────────────────────────────────────────────────────
// Timeout watchdog
// ──────────────────────────────────────────────────────────────────────
initial begin
    #(50_000_000);  // 50 ms absolute timeout
    $display("\nERROR: Global simulation timeout reached!");
    $finish;
end

endmodule

`default_nettype wire
