/**
 * Costas Correlation Phase Estimator (pipelined, Hilbert FIR)
 *
 * Measures relative phase between two same-frequency sinusoids (I, Q)
 * using correlation + CORDIC atan2.
 *
 * Method:
 *   X = Σ( I_delayed[n] * Q[n] )       — in-phase correlation
 *   Y = Σ( Hilbert(I)[n] * Q[n] )      — quadrature correlation
 *   φ = atan2(Y, X)
 *
 * Where Hilbert(I) is a broadband 90° phase shift of I using a 15-tap
 * Type III FIR Hilbert transform. This gives frequency-independent 90°
 * shift across the passband, unlike the old quarter-period delay line.
 *
 * The FIR group delay is 7 samples. Q is delayed by the same amount
 * so that I_delayed and Hilbert(I) are time-aligned with Q_delayed.
 *
 * Pipeline structure (fixes timing at 125 MHz):
 *   Stage 0: Shift register (15 taps) + Q delay line (7 deep)
 *   Stage 1: Hilbert FIR — antisymmetric differences + registered multiply
 *   Stage 2: Hilbert FIR — sum of products + output registration
 *   Stage 3: Correlation multiply (DSP48)
 *   Stage 4: Accumulate
 *   Stage 5: Snapshot accumulators (on window_done)
 *   Stage 6: Normalization (abs + leading-one)
 *   Stage 7: Apply shift + CORDIC input presentation
 *
 * 15-tap Hilbert FIR coefficients (scaled ×2048):
 *   h[0]=-186  h[2]=-261  h[4]=-435  h[6]=-1304
 *   h[7]=0 (center)
 *   h[8]=+1304  h[10]=+435  h[12]=+261  h[14]=+186
 *   (all even-offset taps are zero; antisymmetric: h[n] = -h[N-1-n])
 */

`timescale 1ns / 1ps
`default_nettype none

module phase_costas #(
    parameter SAMPLE_W        = 12,
    parameter ACC_W           = 40
) (
    input  wire                       clk,
    input  wire                       rst,

    input  wire signed [SAMPLE_W-1:0] sample_i,
    input  wire signed [SAMPLE_W-1:0] sample_q,

    input  wire                       window_start,   // pulse: reset accumulators (abort)
    input  wire                       window_done,    // pulse: end window, trigger CORDIC

    output reg  signed [31:0]         phase_out,
    output reg                        phase_valid
);

    localparam PROD_W = 2 * SAMPLE_W;  // 24 bits for 12-bit inputs

    // Hilbert FIR coefficients (×2048 scale, 15-tap Type III antisymmetric)
    // Only 4 unique magnitudes due to h[n] = -h[N-1-n] and zero even-offsets.
    localparam signed [11:0] H1 =  12'sd186;   // |h[0]|=|h[14]|
    localparam signed [11:0] H3 =  12'sd261;   // |h[2]|=|h[12]|
    localparam signed [11:0] H5 =  12'sd435;   // |h[4]|=|h[10]|
    localparam signed [11:0] H7 = 12'sd1304;   // |h[6]|=|h[8]|
    // FIR output is divided by 2048 (right-shift 11) to normalize.
    localparam HILBERT_SHIFT = 11;
    // FIR group delay = (15-1)/2 = 7 samples
    localparam GRP_DELAY = 7;

    // ========================================================================
    // Stage 0: 15-sample shift register for I, 7-sample delay for Q
    // ========================================================================
    reg signed [SAMPLE_W-1:0] sr [0:14];   // I shift register
    reg signed [SAMPLE_W-1:0] q_del [0:GRP_DELAY-1]; // Q delay line (indices 0..6)
    integer k;

    // Pipeline window controls through Hilbert + multiply latency
    // Latency from input to accumulator:
    //   Stage 0: shift register load (1 clk)
    //   Stage 1a: pre-add register (1 clk)
    //   Stage 1b: multiply register (1 clk)
    //   Stage 2: Hilbert sum + saturation register (1 clk)
    //   Stage 3: correlation multiply register (1 clk)
    // Total: 5 pipeline stages from input to accumulator
    localparam PIPE_TOTAL = 5;
    reg [PIPE_TOTAL-1:0] window_done_pipe;
    reg [PIPE_TOTAL-1:0] window_start_pipe;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (k = 0; k < 15; k = k + 1) sr[k] <= '0;
            for (k = 0; k < GRP_DELAY; k = k + 1) q_del[k] <= '0;
            window_done_pipe  <= '0;
            window_start_pipe <= '0;
        end else begin
            // Shift register: sr[0] is newest, sr[14] is oldest
            sr[0] <= sample_i;
            for (k = 1; k < 15; k = k + 1) sr[k] <= sr[k-1];

            // Q delay line: q_del[0] is newest, q_del[6] is oldest = Q aligned
            q_del[0] <= sample_q;
            for (k = 1; k < GRP_DELAY; k = k + 1) q_del[k] <= q_del[k-1];

            // Pipeline window controls
            window_done_pipe  <= {window_done_pipe[PIPE_TOTAL-2:0], window_done};
            window_start_pipe <= {window_start_pipe[PIPE_TOTAL-2:0], window_start};
        end
    end

    // I at group delay = sr[7] (center tap, delayed by 7)
    // Q at group delay = q_del[6] (delayed by 7: enters q_del[0], exits q_del[6])
    // But these are available 1 clock after the shift, so we pipeline below.

    // ========================================================================
    // Stage 1: Hilbert FIR — antisymmetric pre-add + registered multiply
    // ========================================================================
    // Exploit h[n] = -h[14-n]: compute differences of symmetric tap pairs.
    //   d1 = sr[14] - sr[0]   → multiply by H1 (=186)
    //   d3 = sr[12] - sr[2]   → multiply by H3 (=261)
    //   d5 = sr[10] - sr[4]   → multiply by H5 (=435)
    //   d7 = sr[8]  - sr[6]   → multiply by H7 (=1304)
    // (signs: h[0]=-186 means sr[0]*(-186)+sr[14]*(+186) = 186*(sr[14]-sr[0]))

    reg signed [SAMPLE_W:0]   diff1, diff3, diff5, diff7; // 13-bit differences
    // Registered multiplies (13-bit × 12-bit = 25-bit)
    localparam HPROD_W = SAMPLE_W + 1 + 12; // 25 bits
    reg signed [HPROD_W-1:0] hprod1, hprod3, hprod5, hprod7;

    // I_delayed and Q_delayed pipeline to align with Hilbert output.
    // Pre-add stage (1a):
    reg signed [SAMPLE_W-1:0] i_delayed_s1a;
    reg signed [SAMPLE_W-1:0] q_delayed_s1a;
    // Multiply stage (1b):
    reg signed [SAMPLE_W-1:0] i_delayed_s1b;
    reg signed [SAMPLE_W-1:0] q_delayed_s1b;

    always_ff @(posedge clk) begin
        if (rst) begin
            diff1 <= '0; diff3 <= '0; diff5 <= '0; diff7 <= '0;
            hprod1 <= '0; hprod3 <= '0; hprod5 <= '0; hprod7 <= '0;
            i_delayed_s1a <= '0; q_delayed_s1a <= '0;
            i_delayed_s1b <= '0; q_delayed_s1b <= '0;
        end else begin
            // Stage 1a: Pre-add (registered for timing)
            diff1 <= {sr[14][SAMPLE_W-1], sr[14]} - {sr[0][SAMPLE_W-1], sr[0]};
            diff3 <= {sr[12][SAMPLE_W-1], sr[12]} - {sr[2][SAMPLE_W-1], sr[2]};
            diff5 <= {sr[10][SAMPLE_W-1], sr[10]} - {sr[4][SAMPLE_W-1], sr[4]};
            diff7 <= {sr[8][SAMPLE_W-1],  sr[8]}  - {sr[6][SAMPLE_W-1], sr[6]};
            i_delayed_s1a <= sr[7];
            q_delayed_s1a <= q_del[GRP_DELAY-1];

            // Stage 1b: Registered multiply (uses previous clock's diffs)
            hprod1 <= diff1 * H1;
            hprod3 <= diff3 * H3;
            hprod5 <= diff5 * H5;
            hprod7 <= diff7 * H7;
            i_delayed_s1b <= i_delayed_s1a;
            q_delayed_s1b <= q_delayed_s1a;
        end
    end

    // ========================================================================
    // Stage 2: Hilbert FIR — sum of products, scale, and register outputs
    // ========================================================================
    localparam HSUM_W = HPROD_W + 2; // 27 bits (sum of 4 products)
    reg signed [SAMPLE_W-1:0] sample_i90;    // Hilbert-filtered I (90° shifted)
    reg signed [SAMPLE_W-1:0] i_delayed_s2;  // I at group delay
    reg signed [SAMPLE_W-1:0] q_delayed_s2;  // Q at group delay

    wire signed [HSUM_W-1:0] hilbert_sum = {{(HSUM_W-HPROD_W){hprod1[HPROD_W-1]}}, hprod1}
                                          + {{(HSUM_W-HPROD_W){hprod3[HPROD_W-1]}}, hprod3}
                                          + {{(HSUM_W-HPROD_W){hprod5[HPROD_W-1]}}, hprod5}
                                          + {{(HSUM_W-HPROD_W){hprod7[HPROD_W-1]}}, hprod7};

    // Scale back by 2048 (shift right 11) and saturate to SAMPLE_W bits
    wire signed [HSUM_W-1:0] hilbert_scaled = hilbert_sum >>> HILBERT_SHIFT;
    wire signed [SAMPLE_W-1:0] hilbert_sat =
        (hilbert_scaled > $signed({{(HSUM_W-SAMPLE_W+1){1'b0}}, {(SAMPLE_W-1){1'b1}}}))
            ? {1'b0, {(SAMPLE_W-1){1'b1}}} :  // +2047
        (hilbert_scaled < $signed({{(HSUM_W-SAMPLE_W+1){1'b1}}, {(SAMPLE_W-1){1'b0}}}))
            ? {1'b1, {(SAMPLE_W-1){1'b0}}} :  // -2048
        hilbert_scaled[SAMPLE_W-1:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_i90   <= '0;
            i_delayed_s2 <= '0;
            q_delayed_s2 <= '0;
        end else begin
            sample_i90   <= hilbert_sat;
            i_delayed_s2 <= i_delayed_s1b;
            q_delayed_s2 <= q_delayed_s1b;
        end
    end

    // ========================================================================
    // Stage 3: Correlation multiply (DSP48 inference)
    // ========================================================================
    //   prod_iq   = I_delayed * Q_delayed   (in-phase correlation arm)
    //   prod_i90q = Hilbert(I) * Q_delayed   (quadrature correlation arm)
    reg signed [PROD_W-1:0] prod_iq_r;
    reg signed [PROD_W-1:0] prod_i90q_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            prod_iq_r   <= '0;
            prod_i90q_r <= '0;
        end else begin
            prod_iq_r   <= i_delayed_s2 * q_delayed_s2;
            prod_i90q_r <= sample_i90   * q_delayed_s2;
        end
    end

    // ========================================================================
    // Stage 4: Accumulate
    // ========================================================================
    reg signed [ACC_W-1:0] acc_x;  // Σ(I · Q)
    reg signed [ACC_W-1:0] acc_y;  // Σ(I90 · Q)

    // Window control signals aligned to accumulator input
    wire window_done_acc  = window_done_pipe[PIPE_TOTAL-1];
    wire window_start_acc = window_start_pipe[PIPE_TOTAL-1];

    // Snapshot registers (Stage 5)
    reg signed [ACC_W-1:0] snap_x;
    reg signed [ACC_W-1:0] snap_y;
    reg                    snap_valid;
    reg                    cordic_pending;

    always_ff @(posedge clk) begin
        if (rst) begin
            acc_x          <= '0;
            acc_y          <= '0;
            snap_x         <= '0;
            snap_y         <= '0;
            snap_valid     <= 1'b0;
            cordic_pending <= 1'b0;
        end else begin
            snap_valid <= 1'b0;

            if (window_done_acc) begin
                // Snapshot: include this clock's products in the final sum
                snap_x         <= acc_x + {{(ACC_W-PROD_W){prod_iq_r[PROD_W-1]}}, prod_iq_r};
                snap_y         <= acc_y + {{(ACC_W-PROD_W){prod_i90q_r[PROD_W-1]}}, prod_i90q_r};
                snap_valid     <= 1'b1;
                cordic_pending <= 1'b1;
                // Reset for next window
                acc_x <= '0;
                acc_y <= '0;
            end else if (window_start_acc) begin
                // Abort: reset without CORDIC solve
                acc_x <= '0;
                acc_y <= '0;
            end else begin
                // Normal accumulation
                acc_x <= acc_x + {{(ACC_W-PROD_W){prod_iq_r[PROD_W-1]}}, prod_iq_r};
                acc_y <= acc_y + {{(ACC_W-PROD_W){prod_i90q_r[PROD_W-1]}}, prod_i90q_r};
            end

            // Clear pending on CORDIC output (handled below, but reset here)
            if (cordic_out_tvalid && cordic_pending)
                cordic_pending <= 1'b0;
        end
    end

    // ========================================================================
    // Stage 4: Normalization pipeline — absolute value + leading-one detect
    // ========================================================================
    // Split into two registered stages to avoid long combinational path.

    // Stage 4a: Compute absolute values and find the maximum
    reg [ACC_W-1:0] norm_max_abs_r;
    reg signed [ACC_W-1:0] norm_snap_x_r;
    reg signed [ACC_W-1:0] norm_snap_y_r;
    reg             norm_stage4a_valid;

    wire [ACC_W-1:0] snap_x_abs_w = snap_x[ACC_W-1] ? $unsigned(-snap_x) : $unsigned(snap_x);
    wire [ACC_W-1:0] snap_y_abs_w = snap_y[ACC_W-1] ? $unsigned(-snap_y) : $unsigned(snap_y);

    always_ff @(posedge clk) begin
        if (rst) begin
            norm_max_abs_r     <= '0;
            norm_snap_x_r      <= '0;
            norm_snap_y_r      <= '0;
            norm_stage4a_valid <= 1'b0;
        end else begin
            norm_stage4a_valid <= snap_valid;
            if (snap_valid) begin
                norm_max_abs_r <= (snap_x_abs_w >= snap_y_abs_w) ? snap_x_abs_w : snap_y_abs_w;
                norm_snap_x_r  <= snap_x;
                norm_snap_y_r  <= snap_y;
            end
        end
    end

    // Stage 4b: Leading-one detection (priority encode) — registered
    // Finds how many bits to shift right to fit into 12-bit signed range.
    reg [5:0]              norm_shift_r;
    reg signed [ACC_W-1:0] norm_x_r;
    reg signed [ACC_W-1:0] norm_y_r;
    reg                    norm_stage4b_valid;

    // Combinational leading-one on the registered max_abs
    wire [5:0] leading_one;
    assign leading_one = (norm_max_abs_r[39]) ? 6'd29 :
                         (norm_max_abs_r[38]) ? 6'd28 :
                         (norm_max_abs_r[37]) ? 6'd27 :
                         (norm_max_abs_r[36]) ? 6'd26 :
                         (norm_max_abs_r[35]) ? 6'd25 :
                         (norm_max_abs_r[34]) ? 6'd24 :
                         (norm_max_abs_r[33]) ? 6'd23 :
                         (norm_max_abs_r[32]) ? 6'd22 :
                         (norm_max_abs_r[31]) ? 6'd21 :
                         (norm_max_abs_r[30]) ? 6'd20 :
                         (norm_max_abs_r[29]) ? 6'd19 :
                         (norm_max_abs_r[28]) ? 6'd18 :
                         (norm_max_abs_r[27]) ? 6'd17 :
                         (norm_max_abs_r[26]) ? 6'd16 :
                         (norm_max_abs_r[25]) ? 6'd15 :
                         (norm_max_abs_r[24]) ? 6'd14 :
                         (norm_max_abs_r[23]) ? 6'd13 :
                         (norm_max_abs_r[22]) ? 6'd12 :
                         (norm_max_abs_r[21]) ? 6'd11 :
                         (norm_max_abs_r[20]) ? 6'd10 :
                         (norm_max_abs_r[19]) ? 6'd9  :
                         (norm_max_abs_r[18]) ? 6'd8  :
                         (norm_max_abs_r[17]) ? 6'd7  :
                         (norm_max_abs_r[16]) ? 6'd6  :
                         (norm_max_abs_r[15]) ? 6'd5  :
                         (norm_max_abs_r[14]) ? 6'd4  :
                         (norm_max_abs_r[13]) ? 6'd3  :
                         (norm_max_abs_r[12]) ? 6'd2  :
                         (norm_max_abs_r[11]) ? 6'd1  :
                         6'd0;

    always_ff @(posedge clk) begin
        if (rst) begin
            norm_shift_r       <= '0;
            norm_x_r           <= '0;
            norm_y_r           <= '0;
            norm_stage4b_valid <= 1'b0;
        end else begin
            norm_stage4b_valid <= norm_stage4a_valid;
            if (norm_stage4a_valid) begin
                norm_shift_r <= leading_one;
                norm_x_r     <= norm_snap_x_r;
                norm_y_r     <= norm_snap_y_r;
            end
        end
    end

    // ========================================================================
    // Stage 5: Apply shift, saturate, present to CORDIC
    // ========================================================================
    reg         cordic_in_tvalid;
    reg  [31:0] cordic_in_tdata;
    wire        cordic_out_tvalid;
    wire [15:0] cordic_out_tdata;

    // Shift and saturate to 12-bit signed
    wire signed [ACC_W-1:0] shifted_x = norm_x_r >>> norm_shift_r;
    wire signed [ACC_W-1:0] shifted_y = norm_y_r >>> norm_shift_r;

    wire signed [11:0] sat_x = (shifted_x > $signed(40'sd2047))  ? 12'sd2047 :
                               (shifted_x < $signed(-40'sd2048)) ? -12'sd2048 :
                               shifted_x[11:0];
    wire signed [11:0] sat_y = (shifted_y > $signed(40'sd2047))  ? 12'sd2047 :
                               (shifted_y < $signed(-40'sd2048)) ? -12'sd2048 :
                               shifted_y[11:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            cordic_in_tvalid <= 1'b0;
            cordic_in_tdata  <= 32'd0;
        end else begin
            cordic_in_tvalid <= 1'b0;
            if (norm_stage4b_valid) begin
                cordic_in_tvalid <= 1'b1;
                // CORDIC format: [31:16]=Y(imag), [15:0]=X(real)
                // Y = acc_y = Σ(I90·Q), X = acc_x = Σ(I·Q)
                cordic_in_tdata  <= {{4{sat_y[11]}}, sat_y,
                                     {4{sat_x[11]}}, sat_x};
            end
        end
    end

    // ========================================================================
    // CORDIC instance (same cordic_0 IP)
    // ========================================================================
    cordic_0 u_cordic (
        .aclk                    (clk),
        .s_axis_cartesian_tvalid (cordic_in_tvalid),
        .s_axis_cartesian_tdata  (cordic_in_tdata),
        .m_axis_dout_tvalid      (cordic_out_tvalid),
        .m_axis_dout_tdata       (cordic_out_tdata)
    );

    // ========================================================================
    // Output latch
    // ========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            phase_out   <= 32'sd0;
            phase_valid <= 1'b0;
        end else begin
            phase_valid <= 1'b0;
            if (cordic_out_tvalid && cordic_pending) begin
                phase_out   <= {{16{cordic_out_tdata[15]}}, cordic_out_tdata};
                phase_valid <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
