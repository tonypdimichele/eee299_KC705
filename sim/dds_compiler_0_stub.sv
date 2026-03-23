`timescale 1ns / 1ps

// Minimal stub for dds_compiler_0 Xilinx IP.
// Outputs constant zeros — only needed so iq_codec_loop compiles.
// Tone-mode path does not use DDS output.
module dds_compiler_0 (
    input  wire        aclk,
    input  wire        aresetn,
    output wire        m_axis_data_tvalid,
    output wire [31:0] m_axis_data_tdata,
    output wire        m_axis_phase_tvalid,
    output wire [15:0] m_axis_phase_tdata
);

    assign m_axis_data_tvalid  = aresetn;
    assign m_axis_data_tdata   = 32'd0;
    assign m_axis_phase_tvalid = aresetn;
    assign m_axis_phase_tdata  = 16'd0;

endmodule
