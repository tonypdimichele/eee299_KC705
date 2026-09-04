`timescale 1ns / 1ps
`default_nettype none
//
// qpsk_tx_carrier_mix.sv — TX-side companion to qpsk_rx_downmix.sv
//
// Upconverts held baseband QPSK symbols onto a shared square-wave carrier so
// they survive the FL9781's AC-coupled (transformer) DAC outputs. I and Q are
// independent AC-coupled links, so each gets the same in-phase carrier
// (BPSK-style chopper modulation per channel), not a combined IQ/RF mix.
//
module qpsk_tx_carrier_mix #(
    parameter int CARRIER_PERIOD = 8,  // clk/8 => Fc ~= 20.8333 MHz at 166.667 MHz clk
    parameter logic signed [13:0] CARRIER_AMP = 14'sd8000
) (
    input  wire        i_clk,
    input  wire         i_rst,
    input  wire         i_frame_active,   // gate: carrier only rides during an active frame

    input  wire signed [13:0] i_sample,   // held baseband symbol (+-SYMBOL_AMP)

    output logic signed [13:0] o_carrier_sample
);

localparam int PHASE_W = $clog2(CARRIER_PERIOD);

logic [PHASE_W-1:0] carrier_phase;
logic signed [13:0] carrier_level;

// Square-wave carrier (chopper-style): +A for half the period, -A for the other half.
always_ff @(posedge i_clk) begin
    if (i_rst) begin
        carrier_phase <= '0;
    end else begin
        carrier_phase <= (carrier_phase == CARRIER_PERIOD - 1) ? '0 : carrier_phase + 1'b1;
    end
    carrier_level <= (carrier_phase < CARRIER_PERIOD/2) ? CARRIER_AMP : -CARRIER_AMP;
end

assign o_carrier_sample = i_frame_active ?
                          (i_sample[13] ? -carrier_level : carrier_level) :
                          14'sd0;

endmodule

`default_nettype wire
