/**
 * Costas Correlation Phase Estimator (pipelined, Hilbert FIR)
 *
 * Measures relative phase between two same-frequency sinusoids (I, Q)
 * using correlation. Outputs normalized X/Y pair for host-side atan2.
 *
 * Method:
 *   Build analytic pairs using matched Hilbert FIRs:
 *     I_a = I_delayed + j*Hilbert(I)
 *     Q_a = Q_delayed + j*Hilbert(Q)
 *
 *   Cross-correlation (Q relative to I):
 *     X = Σ( I_delayed*Q_delayed + Hilbert(I)*Hilbert(Q) )
 *     Y = Σ( Hilbert(I)*Q_delayed - I_delayed*Hilbert(Q) )
 *   φ = atan2(Y, X)  [computed in Python on the host]
 *
 * Where Hilbert(I) is a broadband 90° phase shift of I using a 15-tap
 * Type III FIR Hilbert transform. This gives frequency-independent 90°
 * shift across the passband, unlike a quarter-period delay line.
 *
 * The FIR group delay is 7 samples. I/Q delayed and Hilbert arms are
 * all aligned to that delay before correlation.
 *
 * Pipeline structure (meets timing at 125 MHz):
 *   Stage 0: Shift registers (15 taps each for I and Q)
 *   Stage 1: Hilbert FIR - antisymmetric differences + registered multiply
 *   Stage 2: Hilbert FIRs - sum of products + output registration
 *   Stage 3: Correlation multiplies (DSP48)
 *   Stage 4: Accumulate + snapshot on window_done
 *   Stage 5: Normalization (abs + leading-one shift)
 *   Stage 6: Saturate to 12-bit, output X/Y
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
    parameter ACC_W           = 40,
    parameter DC_BLOCK_SHIFT  = 8,
    parameter INPUT_SCALE_SHIFT = 0
) (
    input  wire                       clk,
    input  wire                       rst,

    input  wire signed [SAMPLE_W-1:0] sample_i,
    input  wire signed [SAMPLE_W-1:0] sample_q,

    input  wire                       window_start,   // pulse: reset accumulators (abort)
    input  wire                       window_done,    // pulse: end window, output X/Y

    // Normalized X/Y correlation pair (12-bit signed each)
    // Host computes: phase = atan2(xy_y_out, xy_x_out)
    output reg  signed [11:0]         xy_x_out,
    output reg  signed [11:0]         xy_y_out,
    output reg                        xy_valid
);

    localparam PROD_W = 2 * SAMPLE_W;  // 24 bits for 12-bit inputs
    localparam DC_INT_W = SAMPLE_W + 2;
    localparam DC_ACC_W = DC_INT_W + DC_BLOCK_SHIFT;

    // Hilbert FIR coefficients (×2048 scale, 15-tap Type III antisymmetric)
    localparam signed [11:0] H1 =  12'sd186;   // |h[0]|=|h[14]|
    localparam signed [11:0] H3 =  12'sd261;   // |h[2]|=|h[12]|
    localparam signed [11:0] H5 =  12'sd435;   // |h[4]|=|h[10]|
    localparam signed [11:0] H7 = 12'sd1304;   // |h[6]|=|h[8]|
    localparam HILBERT_SHIFT = 11;
    localparam GRP_DELAY = 7;

    // ========================================================================
    // Stage 0: DC-block I/Q, then 15-sample shift registers
    // ========================================================================
    reg signed [SAMPLE_W-1:0] sr_i [0:14];
    reg signed [SAMPLE_W-1:0] sr_q [0:14];
    reg signed [DC_ACC_W-1:0] dc_i_acc;
    reg signed [DC_ACC_W-1:0] dc_q_acc;
    integer k;

    wire signed [DC_ACC_W-1:0] sample_i_q =
        {{(DC_INT_W-SAMPLE_W){sample_i[SAMPLE_W-1]}}, sample_i, {DC_BLOCK_SHIFT{1'b0}}};
    wire signed [DC_ACC_W-1:0] sample_q_q =
        {{(DC_INT_W-SAMPLE_W){sample_q[SAMPLE_W-1]}}, sample_q, {DC_BLOCK_SHIFT{1'b0}}};
    wire signed [DC_ACC_W-1:0] hp_i_q = sample_i_q - dc_i_acc;
    wire signed [DC_ACC_W-1:0] hp_q_q = sample_q_q - dc_q_acc;
    wire signed [DC_ACC_W-1:0] hp_i = hp_i_q >>> DC_BLOCK_SHIFT;
    wire signed [DC_ACC_W-1:0] hp_q = hp_q_q >>> DC_BLOCK_SHIFT;

    wire signed [SAMPLE_W-1:0] sample_i_hp =
        (hp_i > $signed({{(DC_ACC_W-SAMPLE_W+1){1'b0}}, {(SAMPLE_W-1){1'b1}}}))
            ? {1'b0, {(SAMPLE_W-1){1'b1}}} :
        (hp_i < $signed({{(DC_ACC_W-SAMPLE_W+1){1'b1}}, {(SAMPLE_W-1){1'b0}}}))
            ? {1'b1, {(SAMPLE_W-1){1'b0}}} :
        hp_i[SAMPLE_W-1:0];

    wire signed [SAMPLE_W-1:0] sample_q_hp =
        (hp_q > $signed({{(DC_ACC_W-SAMPLE_W+1){1'b0}}, {(SAMPLE_W-1){1'b1}}}))
            ? {1'b0, {(SAMPLE_W-1){1'b1}}} :
        (hp_q < $signed({{(DC_ACC_W-SAMPLE_W+1){1'b1}}, {(SAMPLE_W-1){1'b0}}}))
            ? {1'b1, {(SAMPLE_W-1){1'b0}}} :
        hp_q[SAMPLE_W-1:0];

    wire signed [SAMPLE_W-1:0] sample_i_proc = sample_i_hp >>> INPUT_SCALE_SHIFT;
    wire signed [SAMPLE_W-1:0] sample_q_proc = sample_q_hp >>> INPUT_SCALE_SHIFT;

    // Pipeline window controls through Hilbert + multiply latency (5 stages)
    localparam PIPE_TOTAL = 5;
    reg [PIPE_TOTAL-1:0] window_done_pipe;
    reg [PIPE_TOTAL-1:0] window_start_pipe;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (k = 0; k < 15; k = k + 1) begin
                sr_i[k] <= '0;
                sr_q[k] <= '0;
            end
            dc_i_acc <= '0;
            dc_q_acc <= '0;
            window_done_pipe  <= '0;
            window_start_pipe <= '0;
        end else begin
            dc_i_acc <= dc_i_acc + ((sample_i_q - dc_i_acc) >>> DC_BLOCK_SHIFT);
            dc_q_acc <= dc_q_acc + ((sample_q_q - dc_q_acc) >>> DC_BLOCK_SHIFT);

            sr_i[0] <= sample_i_proc;
            sr_q[0] <= sample_q_proc;
            for (k = 1; k < 15; k = k + 1) begin
                sr_i[k] <= sr_i[k-1];
                sr_q[k] <= sr_q[k-1];
            end

            window_done_pipe  <= {window_done_pipe[PIPE_TOTAL-2:0], window_done};
            window_start_pipe <= {window_start_pipe[PIPE_TOTAL-2:0], window_start};
        end
    end

    // ========================================================================
    // Stage 1: Hilbert FIR - antisymmetric pre-add + registered multiply
    // ========================================================================
    reg signed [SAMPLE_W:0]   diffi1, diffi3, diffi5, diffi7;
    reg signed [SAMPLE_W:0]   diffq1, diffq3, diffq5, diffq7;
    localparam HPROD_W = SAMPLE_W + 1 + 12; // 25 bits
    reg signed [HPROD_W-1:0] hprodi1, hprodi3, hprodi5, hprodi7;
    reg signed [HPROD_W-1:0] hprodq1, hprodq3, hprodq5, hprodq7;

    reg signed [SAMPLE_W-1:0] i_delayed_s1a;
    reg signed [SAMPLE_W-1:0] q_delayed_s1a;
    reg signed [SAMPLE_W-1:0] i_delayed_s1b;
    reg signed [SAMPLE_W-1:0] q_delayed_s1b;

    always_ff @(posedge clk) begin
        if (rst) begin
            diffi1 <= '0; diffi3 <= '0; diffi5 <= '0; diffi7 <= '0;
            diffq1 <= '0; diffq3 <= '0; diffq5 <= '0; diffq7 <= '0;
            hprodi1 <= '0; hprodi3 <= '0; hprodi5 <= '0; hprodi7 <= '0;
            hprodq1 <= '0; hprodq3 <= '0; hprodq5 <= '0; hprodq7 <= '0;
            i_delayed_s1a <= '0; q_delayed_s1a <= '0;
            i_delayed_s1b <= '0; q_delayed_s1b <= '0;
        end else begin
            // Stage 1a: Pre-add
            diffi1 <= {sr_i[14][SAMPLE_W-1], sr_i[14]} - {sr_i[0][SAMPLE_W-1], sr_i[0]};
            diffi3 <= {sr_i[12][SAMPLE_W-1], sr_i[12]} - {sr_i[2][SAMPLE_W-1], sr_i[2]};
            diffi5 <= {sr_i[10][SAMPLE_W-1], sr_i[10]} - {sr_i[4][SAMPLE_W-1], sr_i[4]};
            diffi7 <= {sr_i[8][SAMPLE_W-1],  sr_i[8]}  - {sr_i[6][SAMPLE_W-1], sr_i[6]};

            diffq1 <= {sr_q[14][SAMPLE_W-1], sr_q[14]} - {sr_q[0][SAMPLE_W-1], sr_q[0]};
            diffq3 <= {sr_q[12][SAMPLE_W-1], sr_q[12]} - {sr_q[2][SAMPLE_W-1], sr_q[2]};
            diffq5 <= {sr_q[10][SAMPLE_W-1], sr_q[10]} - {sr_q[4][SAMPLE_W-1], sr_q[4]};
            diffq7 <= {sr_q[8][SAMPLE_W-1],  sr_q[8]}  - {sr_q[6][SAMPLE_W-1], sr_q[6]};

            i_delayed_s1a <= sr_i[GRP_DELAY];
            q_delayed_s1a <= sr_q[GRP_DELAY];

            // Stage 1b: Multiply
            hprodi1 <= diffi1 * H1;
            hprodi3 <= diffi3 * H3;
            hprodi5 <= diffi5 * H5;
            hprodi7 <= diffi7 * H7;

            hprodq1 <= diffq1 * H1;
            hprodq3 <= diffq3 * H3;
            hprodq5 <= diffq5 * H5;
            hprodq7 <= diffq7 * H7;

            i_delayed_s1b <= i_delayed_s1a;
            q_delayed_s1b <= q_delayed_s1a;
        end
    end

    // ========================================================================
    // Stage 2: Hilbert FIR - sum of products, scale, saturate
    // ========================================================================
    localparam HSUM_W = HPROD_W + 2; // 27 bits
    reg signed [SAMPLE_W-1:0] sample_i90;
    reg signed [SAMPLE_W-1:0] sample_q90;
    reg signed [SAMPLE_W-1:0] i_delayed_s2;
    reg signed [SAMPLE_W-1:0] q_delayed_s2;

    wire signed [HSUM_W-1:0] hilbert_i_sum = {{(HSUM_W-HPROD_W){hprodi1[HPROD_W-1]}}, hprodi1}
                                            + {{(HSUM_W-HPROD_W){hprodi3[HPROD_W-1]}}, hprodi3}
                                            + {{(HSUM_W-HPROD_W){hprodi5[HPROD_W-1]}}, hprodi5}
                                            + {{(HSUM_W-HPROD_W){hprodi7[HPROD_W-1]}}, hprodi7};

    wire signed [HSUM_W-1:0] hilbert_q_sum = {{(HSUM_W-HPROD_W){hprodq1[HPROD_W-1]}}, hprodq1}
                                            + {{(HSUM_W-HPROD_W){hprodq3[HPROD_W-1]}}, hprodq3}
                                            + {{(HSUM_W-HPROD_W){hprodq5[HPROD_W-1]}}, hprodq5}
                                            + {{(HSUM_W-HPROD_W){hprodq7[HPROD_W-1]}}, hprodq7};

    wire signed [HSUM_W-1:0] hilbert_i_scaled = hilbert_i_sum >>> HILBERT_SHIFT;
    wire signed [HSUM_W-1:0] hilbert_q_scaled = hilbert_q_sum >>> HILBERT_SHIFT;

    wire signed [SAMPLE_W-1:0] hilbert_i_sat =
        (hilbert_i_scaled > $signed({{(HSUM_W-SAMPLE_W+1){1'b0}}, {(SAMPLE_W-1){1'b1}}}))
            ? {1'b0, {(SAMPLE_W-1){1'b1}}} :
        (hilbert_i_scaled < $signed({{(HSUM_W-SAMPLE_W+1){1'b1}}, {(SAMPLE_W-1){1'b0}}}))
            ? {1'b1, {(SAMPLE_W-1){1'b0}}} :
        hilbert_i_scaled[SAMPLE_W-1:0];

    wire signed [SAMPLE_W-1:0] hilbert_q_sat =
        (hilbert_q_scaled > $signed({{(HSUM_W-SAMPLE_W+1){1'b0}}, {(SAMPLE_W-1){1'b1}}}))
            ? {1'b0, {(SAMPLE_W-1){1'b1}}} :
        (hilbert_q_scaled < $signed({{(HSUM_W-SAMPLE_W+1){1'b1}}, {(SAMPLE_W-1){1'b0}}}))
            ? {1'b1, {(SAMPLE_W-1){1'b0}}} :
        hilbert_q_scaled[SAMPLE_W-1:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_i90   <= '0;
            sample_q90   <= '0;
            i_delayed_s2 <= '0;
            q_delayed_s2 <= '0;
        end else begin
            sample_i90   <= hilbert_i_sat;
            sample_q90   <= hilbert_q_sat;
            i_delayed_s2 <= i_delayed_s1b;
            q_delayed_s2 <= q_delayed_s1b;
        end
    end

    // ========================================================================
    // Stage 3: Correlation multiply (DSP48 inference)
    // ========================================================================
    reg signed [PROD_W-1:0] prod_iq_r;
    reg signed [PROD_W-1:0] prod_i90q_r;
    reg signed [PROD_W-1:0] prod_i90q90_r;
    reg signed [PROD_W-1:0] prod_iq90_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            prod_iq_r     <= '0;
            prod_i90q_r   <= '0;
            prod_i90q90_r <= '0;
            prod_iq90_r   <= '0;
        end else begin
            prod_iq_r     <= i_delayed_s2 * q_delayed_s2;
            prod_i90q_r   <= sample_i90   * q_delayed_s2;
            prod_i90q90_r <= sample_i90   * sample_q90;
            prod_iq90_r   <= i_delayed_s2 * sample_q90;
        end
    end

    // ========================================================================
    // Stage 4: Accumulate + snapshot
    // ========================================================================
    reg signed [ACC_W-1:0] acc_x;  // Σ(I·Q + I90·Q90)
    reg signed [ACC_W-1:0] acc_y;  // Σ(I90·Q - I·Q90)

    localparam CORR_W = PROD_W + 1;
    wire signed [CORR_W-1:0] corr_x_term = {{1{prod_iq_r[PROD_W-1]}}, prod_iq_r}
                                          + {{1{prod_i90q90_r[PROD_W-1]}}, prod_i90q90_r};
    wire signed [CORR_W-1:0] corr_y_term = {{1{prod_i90q_r[PROD_W-1]}}, prod_i90q_r}
                                          - {{1{prod_iq90_r[PROD_W-1]}}, prod_iq90_r};

    wire window_done_acc  = window_done_pipe[PIPE_TOTAL-1];
    wire window_start_acc = window_start_pipe[PIPE_TOTAL-1];

    reg signed [ACC_W-1:0] snap_x;
    reg signed [ACC_W-1:0] snap_y;
    reg                    snap_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            acc_x      <= '0;
            acc_y      <= '0;
            snap_x     <= '0;
            snap_y     <= '0;
            snap_valid <= 1'b0;
        end else begin
            snap_valid <= 1'b0;

            if (window_done_acc) begin
                snap_x     <= acc_x + {{(ACC_W-CORR_W){corr_x_term[CORR_W-1]}}, corr_x_term};
                snap_y     <= acc_y + {{(ACC_W-CORR_W){corr_y_term[CORR_W-1]}}, corr_y_term};
                snap_valid <= 1'b1;
                acc_x <= '0;
                acc_y <= '0;
            end else if (window_start_acc) begin
                acc_x <= '0;
                acc_y <= '0;
            end else begin
                acc_x <= acc_x + {{(ACC_W-CORR_W){corr_x_term[CORR_W-1]}}, corr_x_term};
                acc_y <= acc_y + {{(ACC_W-CORR_W){corr_y_term[CORR_W-1]}}, corr_y_term};
            end
        end
    end

    // ========================================================================
    // Stage 5: Normalization - absolute value + leading-one detect
    // ========================================================================

    // Stage 5a: Absolute values and max
    reg [ACC_W-1:0] norm_max_abs_r;
    reg signed [ACC_W-1:0] norm_snap_x_r;
    reg signed [ACC_W-1:0] norm_snap_y_r;
    reg             norm_stage5a_valid;

    wire [ACC_W-1:0] snap_x_abs_w = snap_x[ACC_W-1] ? $unsigned(-snap_x) : $unsigned(snap_x);
    wire [ACC_W-1:0] snap_y_abs_w = snap_y[ACC_W-1] ? $unsigned(-snap_y) : $unsigned(snap_y);

    always_ff @(posedge clk) begin
        if (rst) begin
            norm_max_abs_r     <= '0;
            norm_snap_x_r      <= '0;
            norm_snap_y_r      <= '0;
            norm_stage5a_valid <= 1'b0;
        end else begin
            norm_stage5a_valid <= snap_valid;
            if (snap_valid) begin
                norm_max_abs_r <= (snap_x_abs_w >= snap_y_abs_w) ? snap_x_abs_w : snap_y_abs_w;
                norm_snap_x_r  <= snap_x;
                norm_snap_y_r  <= snap_y;
            end
        end
    end

    // Stage 5b: Leading-one priority encode
    reg [5:0]              norm_shift_r;
    reg signed [ACC_W-1:0] norm_x_r;
    reg signed [ACC_W-1:0] norm_y_r;
    reg                    norm_stage5b_valid;

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
            norm_stage5b_valid <= 1'b0;
        end else begin
            norm_stage5b_valid <= norm_stage5a_valid;
            if (norm_stage5a_valid) begin
                norm_shift_r <= leading_one;
                norm_x_r     <= norm_snap_x_r;
                norm_y_r     <= norm_snap_y_r;
            end
        end
    end

    // ========================================================================
    // Stage 6: Apply shift, saturate to 12-bit, output X/Y
    // ========================================================================
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
            xy_x_out <= 12'sd0;
            xy_y_out <= 12'sd0;
            xy_valid <= 1'b0;
        end else begin
            xy_valid <= 1'b0;
            if (norm_stage5b_valid) begin
                xy_x_out <= sat_x;
                xy_y_out <= sat_y;
                xy_valid <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
