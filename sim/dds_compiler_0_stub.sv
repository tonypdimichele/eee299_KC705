`timescale 1ns / 1ps

// Minimal stub for dds_compiler_0 Xilinx IP.
// Outputs constant zeros — only needed so iq_codec_loop compiles.
// Tone-mode path does not use DDS output.
module dds_compiler_0 (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        s_axis_phase_tvalid,
    input  wire [15:0] s_axis_phase_tdata,
    output wire        m_axis_data_tvalid,
    output wire [31:0] m_axis_data_tdata,
    output wire        m_axis_phase_tvalid,
    output wire [15:0] m_axis_phase_tdata
);

    reg [15:0] phase_acc = 16'd0;
    wire [15:0] pinc = s_axis_phase_tvalid ? s_axis_phase_tdata : 16'd0;
    wire signed [15:0] i_s16;
    wire signed [15:0] q_s16;

    always @(posedge aclk) begin
        if (!aresetn) begin
            phase_acc <= 16'd0;
        end else begin
            phase_acc <= phase_acc + pinc;
        end
    end

    // Simple quadrature square-wave NCO for functional simulation only.
    assign i_s16 = phase_acc[15] ? -16'sd16384 : 16'sd16384;
    assign q_s16 = phase_acc[14] ? -16'sd16384 : 16'sd16384;

    assign m_axis_data_tvalid  = aresetn;
    assign m_axis_data_tdata   = {q_s16, i_s16};
    assign m_axis_phase_tvalid = aresetn;
    assign m_axis_phase_tdata  = phase_acc;

endmodule
