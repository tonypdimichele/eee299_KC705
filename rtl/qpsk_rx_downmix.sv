`timescale 1ns / 1ps
`default_nettype none
//
// qpsk_rx_downmix.sv — Coherent square-wave downconverter for QPSK RX
//
// Companion to the TX carrier mixer added in iq_codec_loop.sv. The FL9781
// DAC outputs are AC-coupled (transformer), so TX rides baseband symbols on
// a shared square-wave carrier at Fc = clk/6 (matches TX's clk/8 in the DAC
// domain — both equal ~20.8333 MHz in real time). This module regenerates
// that carrier locally in the ADC clock domain, coherently demodulates each
// channel (I and Q are independent AC-coupled links, so each just needs a
// sign-chop against the shared in-phase carrier — no quadrature mixing),
// and boxcar-integrates over one carrier period (6 samples) to null the
// 2x-carrier image before handing samples to the existing integrate-and-dump
// correlator in qpsk_rx_demod.
//
// Frequency is coherent by construction (DAC and ADC clocks derive from the
// same board reference), so only a fixed, unknown cable/pipeline PHASE
// offset needs correction — i_phase_offset is a runtime calibration value
// (0-5), analogous to the existing dac1_delay/dac2_delay LVDS calibration
// registers, tuned empirically rather than tracked with a Costas loop.
//
module qpsk_rx_downmix (
    input  wire              i_clk,      // ADC clock (~125 MHz)
    input  wire              i_rst,
    input  wire              i_enable,   // qpsk_mode, ADC clock domain

    input  wire [2:0]        i_phase_offset,  // calibration: 0-5, one carrier period

    input  wire signed [11:0] i_sample_i,  // post general (5-40 MHz passband) HPF
    input  wire signed [11:0] i_sample_q,

    output logic signed [11:0] o_sample_i,  // down-mixed, boxcar-filtered
    output logic signed [11:0] o_sample_q
);

localparam int CARRIER_PERIOD = 6;  // ADC_clk/6 ~= 20.8333 MHz, matches TX clk/8

logic [2:0] phase_counter;
logic [3:0] phase_sum;
logic [2:0] phase_index;
logic       carrier_pos;

logic signed [11:0] mixed_i;
logic signed [11:0] mixed_q;

logic signed [11:0] hist_i [0:CARRIER_PERIOD-1];
logic signed [11:0] hist_q [0:CARRIER_PERIOD-1];
logic [2:0]         hist_idx;
logic signed [14:0] acc_i;
logic signed [14:0] acc_q;

assign phase_sum   = {1'b0, phase_counter} + {1'b0, i_phase_offset};
assign phase_index = (phase_sum >= CARRIER_PERIOD) ? (phase_sum - CARRIER_PERIOD) : phase_sum[2:0];
assign carrier_pos  = (phase_index < 3);

assign mixed_i = carrier_pos ? i_sample_i : -i_sample_i;
assign mixed_q = carrier_pos ? i_sample_q : -i_sample_q;

integer k;
always_ff @(posedge i_clk) begin
    if (i_rst || !i_enable) begin
        phase_counter <= 3'd0;
        hist_idx      <= 3'd0;
        acc_i         <= 15'sd0;
        acc_q         <= 15'sd0;
        for (k = 0; k < CARRIER_PERIOD; k = k + 1) begin
            hist_i[k] <= 12'sd0;
            hist_q[k] <= 12'sd0;
        end
    end else begin
        phase_counter <= (phase_counter == CARRIER_PERIOD - 1) ? 3'd0 : phase_counter + 3'd1;

        acc_i <= acc_i - hist_i[hist_idx] + mixed_i;
        acc_q <= acc_q - hist_q[hist_idx] + mixed_q;
        hist_i[hist_idx] <= mixed_i;
        hist_q[hist_idx] <= mixed_q;
        hist_idx <= (hist_idx == CARRIER_PERIOD - 1) ? 3'd0 : hist_idx + 3'd1;
    end
end

// Boxcar sum of 6 samples (max magnitude ~6x) scaled back to 12-bit range (>>3).
assign o_sample_i = acc_i[14:3];
assign o_sample_q = acc_q[14:3];

endmodule

`default_nettype wire
