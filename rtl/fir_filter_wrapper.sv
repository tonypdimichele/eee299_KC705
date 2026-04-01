
module fir_filter_wrapper #() (
    (*mark_debug = "true"*)
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        i_valid,
    (*mark_debug = "true"*)
    input  wire [7:0]  I,
    (*mark_debug = "true"*)
    input  wire [7:0]  Q,
    (*mark_debug = "true"*)
    output wire [15:0] I_filtered,
    (*mark_debug = "true"*)
    output wire [15:0] Q_filtered,
    output wire       o_valid
);

//
// Wires for I-path FIR
//
wire s_tready_I;
wire m_tvalid_I;


//
// Wires for Q-path FIR
//
wire s_tready_Q;
wire m_tvalid_Q;

assign o_valid = m_tvalid_I & m_tvalid_Q;

////////////////////////////////////////////////////////////
// I CHANNEL RRC FIR
////////////////////////////////////////////////////////////
fir_compiler_0 I_data_RRC (
    .aresetn            (aresetn),
    .aclk               (aclk),
    .s_axis_data_tvalid (i_valid),
    .s_axis_data_tready (s_tready_I),
    .s_axis_data_tdata  (I),
    .m_axis_data_tvalid (m_tvalid_I),
    .m_axis_data_tdata  (I_filtered)
);

////////////////////////////////////////////////////////////
// Q CHANNEL RRC FIR
////////////////////////////////////////////////////////////
fir_compiler_0 Q_data_RRC (
    .aresetn            (aresetn),
    .aclk               (aclk),
    .s_axis_data_tvalid (i_valid),
    .s_axis_data_tready (s_tready_Q),
    .s_axis_data_tdata  (Q),
    .m_axis_data_tvalid (m_tvalid_Q),
    .m_axis_data_tdata  (Q_filtered)
);

endmodule
