module iq_codec_loop (
    input  wire       i_clk,
    input  wire       i_rst,

    input  wire [7:0] i_s_axis_tdata,
    input  wire       i_s_axis_tvalid,
    output wire       o_s_axis_tready,
    input  wire       i_s_axis_tlast,

    output wire [7:0] o_m_axis_tdata,
    output wire       o_m_axis_tvalid,
    input  wire       i_m_axis_tready,
    output wire       o_m_axis_tlast,

    output wire       o_dac_sample_valid,
    output wire [13:0] o_dac1_h,
    output wire [13:0] o_dac1_l,
    output wire [13:0] o_dac2_h,
    output wire [13:0] o_dac2_l,

    output wire o_DAC_out_I_p,
    output wire o_DAC_out_I_n,
    output wire o_DAC_out_Q_p,
    output wire o_DAC_out_Q_n,
    input  wire i_ADC_in_I_p,
    input  wire i_ADC_in_I_n,
    input  wire i_ADC_in_Q_p,
    input  wire i_ADC_in_Q_n
);

wire       dds_tvalid;
wire [31:0] dds_tdata;
wire       dds_phase_tvalid;
wire [15:0] dds_phase_tdata;

// DDS runs continuously and provides SIN/COS samples used as a reversible byte mask.
dds_compiler_0 dds_iq_core (
    .aclk(i_clk),
    .aresetn(~i_rst),
    .m_axis_data_tvalid(dds_tvalid), // output wire m_axis_data_tvalid
    .m_axis_data_tdata(dds_tdata), // output wire [31 : 0] m_axis_data_tdata
    .m_axis_phase_tvalid(dds_phase_tvalid), // output wire m_axis_phase_tvalid
    .m_axis_phase_tdata(dds_phase_tdata) // output wire [15 : 0] m_axis_phase_tdata
);

wire [7:0] iq_mask;
wire [7:0] encoded_byte;
wire [7:0] decoded_byte;

logic [7:0] tx_byte_reg;
logic [1:0] sym_idx_reg;
logic       mod_busy_reg;

logic [7:0] out_data_reg;
logic       out_last_reg;
logic       out_valid_reg;

wire       out_ready_for_new;
wire       axis_fire;
wire [1:0] symbol_bits;
wire       symbol_i;
wire       symbol_q;
wire       carrier_i;
wire       carrier_q;
wire       mod_i;
wire       mod_q;
wire       dac_i_bit;
wire       dac_q_bit;
wire       tx_symbol_valid;
wire [13:0] dac1_h;
wire [13:0] dac1_l;
wire [13:0] dac2_h;
wire [13:0] dac2_l;
wire signed [13:0] tx_i_sample;
wire signed [13:0] tx_q_sample;

assign iq_mask = dds_tdata[7:0] ^ dds_tdata[23:16];
assign encoded_byte = i_s_axis_tdata ^ iq_mask;
assign decoded_byte = encoded_byte ^ iq_mask;

assign out_ready_for_new = ~out_valid_reg || i_m_axis_tready;
assign o_s_axis_tready = out_ready_for_new && ~mod_busy_reg;
assign axis_fire = i_s_axis_tvalid && o_s_axis_tready;

assign symbol_bits = (sym_idx_reg == 2'd0) ? tx_byte_reg[7:6] :
                     (sym_idx_reg == 2'd1) ? tx_byte_reg[5:4] :
                     (sym_idx_reg == 2'd2) ? tx_byte_reg[3:2] :
                                             tx_byte_reg[1:0];

assign symbol_i = ~symbol_bits[1];
assign symbol_q = ~symbol_bits[0];

// Use DDS sign bits as a simple carrier for a first-pass digital modulation stage.
assign carrier_i = dds_tdata[15];
assign carrier_q = dds_tdata[31];
assign mod_i = symbol_i ^ carrier_i;
assign mod_q = symbol_q ^ carrier_q;
assign tx_symbol_valid = mod_busy_reg && dds_tvalid;

fl9781_tx_wrapper fl9781_tx_wrapper_inst (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_symbol_valid(tx_symbol_valid),
    .i_symbol_i(mod_i),
    .i_symbol_q(mod_q),
    .o_i_sample(tx_i_sample),
    .o_q_sample(tx_q_sample),
    .o_dac1_h(dac1_h),
    .o_dac1_l(dac1_l),
    .o_dac2_h(dac2_h),
    .o_dac2_l(dac2_l)
);

assign o_dac_sample_valid = tx_symbol_valid;
assign o_dac1_h = dac1_h;
assign o_dac1_l = dac1_l;
assign o_dac2_h = dac2_h;
assign o_dac2_l = dac2_l;

assign dac_i_bit = tx_symbol_valid ? ~tx_i_sample[13] : 1'b0;
assign dac_q_bit = tx_symbol_valid ? ~tx_q_sample[13] : 1'b0;

assign o_DAC_out_I_p = dac_i_bit;
assign o_DAC_out_I_n = ~dac_i_bit;
assign o_DAC_out_Q_p = dac_q_bit;
assign o_DAC_out_Q_n = ~dac_q_bit;

always @(posedge i_clk) begin
    if (i_rst) begin
        tx_byte_reg <= 8'd0;
        sym_idx_reg <= 2'd0;
        mod_busy_reg <= 1'b0;
        out_data_reg <= 8'd0;
        out_last_reg <= 1'b0;
        out_valid_reg <= 1'b0;
    end else begin
        if (out_valid_reg && i_m_axis_tready) begin
            out_valid_reg <= 1'b0;
        end

        if (axis_fire) begin
            tx_byte_reg <= encoded_byte;
            sym_idx_reg <= 2'd0;
            mod_busy_reg <= 1'b1;

            out_data_reg <= decoded_byte;
            out_last_reg <= i_s_axis_tlast;
            out_valid_reg <= 1'b1;
        end else if (mod_busy_reg) begin
            sym_idx_reg <= sym_idx_reg + 1'b1;
            if (sym_idx_reg == 2'd3) begin
                mod_busy_reg <= 1'b0;
            end
        end
    end
end

assign o_m_axis_tvalid = out_valid_reg;
assign o_m_axis_tlast  = out_last_reg;
assign o_m_axis_tdata  = out_data_reg;

endmodule
