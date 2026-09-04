/**
 * Dual-Channel Second-Order IIR High-Pass Filter
 *
 * Removes low-frequency content (DC + kHz-range LO products) from two
 * parallel ADC channels so that only the signal of interest (5-40 MHz)
 * remains for downstream phase comparison.
 *
 * Two cascaded first-order DC-block stages per channel provide
 * 40 dB/decade rolloff below cutoff (vs 20 dB/decade for single-order).
 *
 * Stage 1's output stays in full-precision scaled domain and feeds
 * directly into stage 2 — no intermediate truncation.  Only the final
 * output is shifted back to sample scale and saturated.
 *
 * H(z) = [(1-α)(1-z⁻¹) / (1-(1-α)z⁻¹)]²     α = 2^(-SHIFT)
 *
 * Per-stage cutoff ≈ f_s / (2π · 2^SHIFT).
 *
 * At 125 MS/s:
 *   SHIFT=4 → fc ≈ 1.24 MHz, rejection at  80 kHz ≈ 48 dB
 *   SHIFT=5 → fc ≈  621 kHz, rejection at  80 kHz ≈ 36 dB
 *   SHIFT=6 → fc ≈  311 kHz, rejection at  80 kHz ≈ 24 dB
 *
 * SHIFT=4 default: passband droop <1.1 dB at 5 MHz.
 */

`timescale 1ns / 1ps
`default_nettype none

module hpf_iir_duo #(
    parameter SAMPLE_W = 12,
    parameter SHIFT    = 4       // alpha = 2^(-SHIFT)
) (
    input  wire                       clk,
    input  wire                       rst,

    // Channel A input / output
    input  wire signed [SAMPLE_W-1:0] in_a,
    output wire signed [SAMPLE_W-1:0] out_a,

    // Channel B input / output
    input  wire signed [SAMPLE_W-1:0] in_b,
    output wire signed [SAMPLE_W-1:0] out_b
);

    // Guard bits: 2 for single stage, +1 for two-stage subtraction headroom.
    localparam INT_W = SAMPLE_W + 3;
    localparam ACC_W = INT_W + SHIFT;

    // ---- Channel A --------------------------------------------------------
    reg signed [ACC_W-1:0] dc_acc_a_s1, dc_acc_a_s2;

    // Stage 1: scale input up by SHIFT bits (fractional precision)
    wire signed [ACC_W-1:0] in_a_scaled = {{(INT_W-SAMPLE_W){in_a[SAMPLE_W-1]}}, in_a, {SHIFT{1'b0}}};

    // Stage 1 HP output — kept in full-precision scaled domain (no truncation)
    wire signed [ACC_W-1:0] hp_a_s1 = in_a_scaled - dc_acc_a_s1;

    // Stage 2: feed hp_a_s1 directly as already-scaled input
    wire signed [ACC_W-1:0] hp_a_s2  = hp_a_s1 - dc_acc_a_s2;
    wire signed [ACC_W-1:0] hp_a_out = hp_a_s2 >>> SHIFT;  // back to sample domain

    // Saturate to output width
    wire signed [SAMPLE_W-1:0] sat_a;
    assign sat_a = (hp_a_out > $signed({{(ACC_W-SAMPLE_W+1){1'b0}}, {(SAMPLE_W-1){1'b1}}}))
                   ? {{1'b0}, {(SAMPLE_W-1){1'b1}}} :
                   (hp_a_out < $signed({{(ACC_W-SAMPLE_W+1){1'b1}}, {(SAMPLE_W-1){1'b0}}}))
                   ? {{1'b1}, {(SAMPLE_W-1){1'b0}}} :
                   hp_a_out[SAMPLE_W-1:0];

    assign out_a = sat_a;

    // ---- Channel B --------------------------------------------------------
    reg signed [ACC_W-1:0] dc_acc_b_s1, dc_acc_b_s2;

    wire signed [ACC_W-1:0] in_b_scaled = {{(INT_W-SAMPLE_W){in_b[SAMPLE_W-1]}}, in_b, {SHIFT{1'b0}}};
    wire signed [ACC_W-1:0] hp_b_s1 = in_b_scaled - dc_acc_b_s1;
    wire signed [ACC_W-1:0] hp_b_s2  = hp_b_s1 - dc_acc_b_s2;
    wire signed [ACC_W-1:0] hp_b_out = hp_b_s2 >>> SHIFT;

    wire signed [SAMPLE_W-1:0] sat_b;
    assign sat_b = (hp_b_out > $signed({{(ACC_W-SAMPLE_W+1){1'b0}}, {(SAMPLE_W-1){1'b1}}}))
                   ? {{1'b0}, {(SAMPLE_W-1){1'b1}}} :
                   (hp_b_out < $signed({{(ACC_W-SAMPLE_W+1){1'b1}}, {(SAMPLE_W-1){1'b0}}}))
                   ? {{1'b1}, {(SAMPLE_W-1){1'b0}}} :
                   hp_b_out[SAMPLE_W-1:0];

    assign out_b = sat_b;

    // ---- Accumulator update (both stages) ---------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            dc_acc_a_s1 <= '0;
            dc_acc_b_s1 <= '0;
            dc_acc_a_s2 <= '0;
            dc_acc_b_s2 <= '0;
        end else begin
            // Stage 1: track DC of raw input
            dc_acc_a_s1 <= dc_acc_a_s1 + ((in_a_scaled - dc_acc_a_s1) >>> SHIFT);
            dc_acc_b_s1 <= dc_acc_b_s1 + ((in_b_scaled - dc_acc_b_s1) >>> SHIFT);
            // Stage 2: track residual DC of stage 1 output (full precision)
            dc_acc_a_s2 <= dc_acc_a_s2 + ((hp_a_s1 - dc_acc_a_s2) >>> SHIFT);
            dc_acc_b_s2 <= dc_acc_b_s2 + ((hp_b_s1 - dc_acc_b_s2) >>> SHIFT);
        end
    end

endmodule

`default_nettype wire
