/**
 * Zero-Crossing Phase Estimator (standalone)
 *
 * For resource comparison with phase_costas.sv.
 *
 * Measures phase as the time delay from each I-channel positive-going
 * zero crossing to the next Q-channel positive-going zero crossing,
 * accumulated over an externally-controlled N-crossing window.
 *
 * Interface mirrors phase_costas: window_start resets accumulators,
 * window_done latches and outputs the result.
 *
 * Output: delay_sum (32-bit unsigned, total clocks of I-to-Q delay
 * summed over the window). Host computes phase = 360 * delay_sum / clk_count.
 */

`timescale 1ns / 1ps
`default_nettype none

module phase_zc #(
    parameter SAMPLE_W             = 12,
    parameter FREQ_MIN_PERIOD_CLKS = 2
) (
    input  wire        clk,
    input  wire        rst,

    input  wire signed [SAMPLE_W-1:0] sample_i,   // I channel (signed)
    input  wire signed [SAMPLE_W-1:0] sample_q,   // Q channel (signed)

    input  wire        window_start,   // pulse: reset accumulators (abort)
    input  wire        window_done,    // pulse: latch output

    output reg  [31:0] delay_sum_out,  // accumulated I-to-Q delay (clocks)
    output reg         xy_valid        // single-cycle pulse: output ready
);

    // ---- Constants --------------------------------------------------------
    localparam signed [SAMPLE_W-1:0] ZC_HYST = 16;

    // ---- I-channel zero-crossing detection --------------------------------
    reg signed [SAMPLE_W-1:0] prev_sample_i;
    reg [15:0]        zc_period_counter;
    reg               zc_armed;

    // ---- Q-channel zero-crossing detection --------------------------------
    reg signed [SAMPLE_W-1:0] prev_sample_q;
    reg               q_zc_armed;

    // ---- I-to-Q delay measurement -----------------------------------------
    reg [15:0]        iq_delay_counter;
    reg               iq_delay_captured;
    reg [31:0]        iq_delay_accum;

    // =======================================================================
    always @(posedge clk) begin
        if (rst) begin
            prev_sample_i     <= '0;
            prev_sample_q     <= '0;
            zc_period_counter <= 16'd1;
            zc_armed          <= 1'b0;
            q_zc_armed        <= 1'b0;
            iq_delay_counter  <= 16'd0;
            iq_delay_captured <= 1'b1;
            iq_delay_accum    <= 32'd0;
            delay_sum_out     <= 32'd0;
            xy_valid          <= 1'b0;
        end else begin

            xy_valid <= 1'b0;   // default: single-cycle pulse

            prev_sample_i <= sample_i;
            prev_sample_q <= sample_q;

            // ---- Window control ------------------------------------------
            if (window_start) begin
                // Abort / reset accumulators
                iq_delay_accum    <= 32'd0;
                iq_delay_counter  <= 16'd0;
                iq_delay_captured <= 1'b1;
            end

            if (window_done) begin
                // Latch accumulated delay and signal output valid
                delay_sum_out  <= iq_delay_accum;
                xy_valid       <= 1'b1;
                iq_delay_accum <= 32'd0;
            end

            // ---- I-to-Q delay counter: always incrementing ---------------
            if (iq_delay_counter < 16'hFFFF)
                iq_delay_counter <= iq_delay_counter + 1;

            // ---- Q zero-crossing detection (independent of I ZC) ---------
            if (sample_q < -ZC_HYST)
                q_zc_armed <= 1'b1;

            if (q_zc_armed && prev_sample_q < ZC_HYST && sample_q >= ZC_HYST) begin
                if (!iq_delay_captured) begin
                    iq_delay_accum    <= iq_delay_accum + {16'd0, iq_delay_counter};
                    iq_delay_captured <= 1'b1;
                end
                q_zc_armed <= 1'b0;
            end

            // ---- I zero-crossing detection -------------------------------
            if (sample_i < -ZC_HYST)
                zc_armed <= 1'b1;

            // Positive-going zero-crossing with hysteresis & min-period
            if (zc_armed && prev_sample_i < ZC_HYST && sample_i >= ZC_HYST) begin
                if (zc_period_counter >= FREQ_MIN_PERIOD_CLKS) begin
                    // Valid I ZC: reset delay counter for next I-to-Q measurement
                    iq_delay_counter  <= 16'd0;
                    iq_delay_captured <= 1'b0;
                    zc_period_counter <= 16'd1;
                    zc_armed          <= 1'b0;
                end else begin
                    if (zc_period_counter < 16'hFFFF)
                        zc_period_counter <= zc_period_counter + 1;
                end
            end else begin
                if (zc_period_counter < 16'hFFFF)
                    zc_period_counter <= zc_period_counter + 1;
            end

        end
    end

endmodule

`default_nettype wire
