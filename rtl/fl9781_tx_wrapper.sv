`timescale 1ns / 1ps
`default_nettype none

module fl9781_tx_wrapper #(
    parameter logic signed [13:0] P_SYMBOL_AMPLITUDE = 14'sd8191
) (
    input  wire                   i_clk,
    input  wire                   i_rst,

    input  wire                   i_symbol_valid,
    input  wire                   i_symbol_i,
    input  wire                   i_symbol_q,

    output logic signed [13:0]    o_i_sample,
    output logic signed [13:0]    o_q_sample,

     output reg [13:0]            o_dac1_h,
     output reg [13:0]            o_dac1_l,
     output reg [13:0]            o_dac2_h,
     output reg [13:0]            o_dac2_l
//    output wire [13:0]            o_dac1_h,
//    output wire [13:0]            o_dac1_l,
//    output wire [13:0]            o_dac2_h,
//    output wire [13:0]            o_dac2_l
);

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        o_i_sample <= 14'sd0;
        o_q_sample <= 14'sd0;
    end else if (i_symbol_valid) begin
        o_i_sample <= i_symbol_i ? P_SYMBOL_AMPLITUDE : -P_SYMBOL_AMPLITUDE;
        o_q_sample <= i_symbol_q ? P_SYMBOL_AMPLITUDE : -P_SYMBOL_AMPLITUDE;
    end

     o_dac1_h <= o_i_sample;
     o_dac1_l <= o_i_sample;
     o_dac2_h <= o_q_sample;
     o_dac2_l <= o_q_sample;

end

//assign o_dac1_h = o_i_sample;
//assign o_dac1_l = o_i_sample;
//assign o_dac2_h = o_q_sample;
//assign o_dac2_l = o_q_sample;

endmodule

`default_nettype wire
