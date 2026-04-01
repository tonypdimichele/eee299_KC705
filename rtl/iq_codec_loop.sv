module iq_codec_loop (
    input  wire       i_clk,
    input  wire       i_rst,
    input  wire       i_dac1_clk,
    input  wire       i_dac2_clk,
    input  wire       i_tone_mode,
    input  wire [31:0] i_tone_pinc,
(*mark_debug = "true"*)
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
    output wire [13:0] o_dac2_l
);

localparam logic [15:0] IQ_DDS_PINC = 16'h7AE1;
localparam logic signed [13:0] DAC_PARK_MIDSCALE = 14'sd0;

wire       dds_tvalid;
wire [31:0] dds_tdata;
wire       dds_phase_tvalid;
wire [15:0] dds_phase_tdata;
wire       tone_dds_tvalid;
(*mark_debug = "true"*)
wire [31:0] tone_dds_tdata;
reg         tone_mode_dac1_ff1;
reg         tone_mode_dac1_ff2;
// PINC FFs are posedge so they feed the posedge-sampled DDS s_axis_phase_tdata with full-cycle setup.
reg [31:0]  tone_pinc_dac1_ff1;
reg [31:0]  tone_pinc_dac1_ff2;
reg [15:0]  tone_pinc_dac1_stable;
// Reset synchronizer: bring i_rst (125 MHz domain) safely into i_dac1_clk (500 MHz) domain.
reg         dac1_rst_sync1;
reg         dac1_rst_sync2;
wire        tone_aresetn;
wire        tone_mode_dac1;
(*mark_debug = "true"*)
wire [15:0] eth_data_dac1;
(*mark_debug = "true"*)
wire eth_data_valid;
afifo_wrapper afifo_wrapper_data_iq (
    .i_r_clk(i_dac1_clk),
    .i_w_clk(i_clk),
    .i_w_rst(i_rst),
    .i_w_data(i_s_axis_tdata),
    .o_r_data(eth_data_dac1),
    .o_data_valid(eth_data_valid)
);
logic [7:0] I_unsigned;
logic [7:0] Q_unsigned;
logic signed [7:0] I_signed;
logic signed [7:0] Q_signed;
logic signed [15:0] I_filtered;
logic signed [15:0] Q_filtered;
logic signed [13:0] I_dac_s14;
logic signed [13:0] Q_dac_s14;
logic       iq_in_valid;
logic       iq_out_valid;
logic [15:0] iq_word_hold;
logic [6:0]  iq_bit_phase;
logic        iq_word_loaded;
logic [2:0]  iq_bit_idx;
logic        bpsk_i_bit;
logic        bpsk_q_bit;
localparam logic signed [7:0] BIT_LEVEL_POS = 8'sd127;
localparam logic signed [7:0] BIT_LEVEL_NEG = -8'sd128;
wire                       iq_symbol_strobe;
wire                       dds_iq_tvalid;
wire [31:0]                dds_iq_tdata;
wire signed [15:0]         dds_iq_i_s16;
wire signed [15:0]         dds_iq_q_s16;
wire signed [15:0]         bpsk_i_s16;
wire signed [15:0]         bpsk_q_s16;
wire signed [13:0]         bpsk_i_s14;
wire signed [13:0]         bpsk_q_s14;

assign iq_bit_idx = iq_bit_phase[6:4];
assign iq_symbol_strobe = (iq_bit_phase[3:0] == 4'd0);

always_ff @(posedge i_dac1_clk) begin
    if (!tone_aresetn) begin
        iq_word_hold <= 16'd0;
        iq_bit_phase <= 7'd0;
        iq_word_loaded <= 1'b0;
        bpsk_i_bit <= 1'b0;
        bpsk_q_bit <= 1'b0;
        I_unsigned <= 8'd0;
        Q_unsigned <= 8'd0;
        I_signed <= 8'd0;
        Q_signed <= 8'd0;
        iq_in_valid <= 1'b0;
    end else if (eth_data_valid) begin
        iq_word_hold <= eth_data_dac1;
        iq_bit_phase <= 7'd0;
        iq_word_loaded <= 1'b1;
        bpsk_i_bit <= eth_data_dac1[7];
        bpsk_q_bit <= eth_data_dac1[15];
        I_unsigned <= {8{eth_data_dac1[7]}};
        Q_unsigned <= {8{eth_data_dac1[15]}};
        I_signed <= eth_data_dac1[7] ? BIT_LEVEL_POS : BIT_LEVEL_NEG;
        Q_signed <= eth_data_dac1[15] ? BIT_LEVEL_POS : BIT_LEVEL_NEG;
        iq_in_valid <= 1'b1;
    end else begin
        if (iq_word_loaded) begin
            iq_bit_phase <= iq_bit_phase + 1'b1;
            if (iq_bit_phase == 7'd127) begin
                iq_word_loaded <= 1'b0;
            end
            if (iq_symbol_strobe) begin
                bpsk_i_bit <= iq_word_hold[7 - iq_bit_idx];
                bpsk_q_bit <= iq_word_hold[15 - iq_bit_idx];
                I_unsigned <= {8{iq_word_hold[7 - iq_bit_idx]}};
                Q_unsigned <= {8{iq_word_hold[15 - iq_bit_idx]}};
                I_signed <= iq_word_hold[7 - iq_bit_idx] ? BIT_LEVEL_POS : BIT_LEVEL_NEG;
                Q_signed <= iq_word_hold[15 - iq_bit_idx] ? BIT_LEVEL_POS : BIT_LEVEL_NEG;
            end else begin
                I_unsigned <= 8'd0;
                Q_unsigned <= 8'd0;
                I_signed <= 8'sd0;
                Q_signed <= 8'sd0;
            end
            iq_in_valid <= 1'b1;
        end else begin
            I_unsigned <= 8'd0;
            Q_unsigned <= 8'd0;
            I_signed <= 8'sd0;
            Q_signed <= 8'sd0;
            iq_in_valid <= 1'b1;
        end
    end
end

// Dedicated DDS for tone mode, clocked in DAC domain to avoid LUT truncation artifacts.
dds_compiler_0 dds_iq_core (
    .aclk(i_dac1_clk), 
    .aresetn(tone_aresetn),
    .s_axis_phase_tvalid(tone_aresetn),
    .s_axis_phase_tdata(tone_pinc_dac1_stable),
    .m_axis_data_tvalid(dds_iq_tvalid),
    .m_axis_data_tdata(dds_iq_tdata),
    .m_axis_phase_tvalid(),  // unused
    .m_axis_phase_tdata()    // unused
);

function automatic logic signed [13:0] sat_s16_to_s14(input logic signed [15:0] x);
    begin
        if (x > 16'sd8191) begin
            sat_s16_to_s14 = 14'sd8191;
        end else if (x < -16'sd8192) begin
            sat_s16_to_s14 = -14'sd8192;
        end else begin
            sat_s16_to_s14 = x[13:0];
        end
    end
endfunction

assign I_dac_s14 = sat_s16_to_s14(I_filtered);
assign Q_dac_s14 = sat_s16_to_s14(Q_filtered);
assign dds_iq_q_s16 = dds_iq_tdata[31:16];
assign dds_iq_i_s16 = dds_iq_tdata[15:0];
assign bpsk_i_s16 = bpsk_i_bit ? dds_iq_i_s16 : -dds_iq_i_s16;
assign bpsk_q_s16 = bpsk_q_bit ? dds_iq_q_s16 : -dds_iq_q_s16;
assign bpsk_i_s14 = sat_s16_to_s14(bpsk_i_s16 >>> 2);
assign bpsk_q_s14 = sat_s16_to_s14(bpsk_q_s16 >>> 2);

// Reset synchronizer for dds_tone_core: i_rst is 125 MHz, dac1_clk is 500 MHz.
always @(posedge i_dac1_clk or posedge i_rst) begin
    if (i_rst) begin
        dac1_rst_sync1 <= 1'b0;
        dac1_rst_sync2 <= 1'b0;
    end else begin
        dac1_rst_sync1 <= 1'b1;
        dac1_rst_sync2 <= dac1_rst_sync1;
    end
end
assign tone_aresetn = dac1_rst_sync2;


logic [1:0] dac_counter;
logic dac_quarter_clock;
logic dac_quarter_clock_bufg;
always @(posedge i_dac1_clk) begin
    if (!tone_aresetn) begin
        tone_pinc_dac1_ff1 <= 32'h0000_13AF;
        tone_pinc_dac1_ff2 <= 32'h0000_13AF;
    end else begin
        tone_pinc_dac1_ff1 <= i_tone_pinc;
        tone_pinc_dac1_ff2 <= tone_pinc_dac1_ff1;
        dac_counter <= dac_counter + 1'b1;
    end

    if (dac_counter == 2'b0) begin
        dac_quarter_clock <= ~dac_quarter_clock;
    end
end

BUFG BUFG1_inst (
   .O(dac_quarter_clock_bufg), // 1-bit output: Clock output
   .I(dac_quarter_clock)  // 1-bit input: Clock input
);

// Dedicated DDS for tone mode, clocked in DAC domain to avoid LUT truncation artifacts.
dds_compiler_0 dds_tone_core (
    .aclk(i_dac1_clk), 
    .aresetn(tone_aresetn),
    .s_axis_phase_tvalid(tone_aresetn),
    .s_axis_phase_tdata(tone_pinc_dac1_stable),
    .m_axis_data_tvalid(tone_dds_tvalid),
    .m_axis_data_tdata(tone_dds_tdata),
    .m_axis_phase_tvalid(),  // unused
    .m_axis_phase_tdata()    // unused
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
wire       tx_symbol_valid;
wire [13:0] dac1_h;
wire [13:0] dac1_l;
wire [13:0] dac2_h;
wire [13:0] dac2_l;
(*mark_debug = "true"*)
wire [13:0] tone_dac1_h;
(*mark_debug = "true"*)
wire [13:0] tone_dac1_l;
wire [13:0] tone_dac2_h;
wire [13:0] tone_dac2_l;
wire signed [13:0] tx_i_sample;
wire signed [13:0] tx_q_sample;
wire signed [15:0] tone_dds_i_s16;
wire signed [15:0] tone_dds_q_s16;

// Two's complement: pass signed samples directly to the DAC (no offset conversion needed)

assign iq_mask = 8'b1001_0011;
assign encoded_byte = eth_data_dac1 ^ iq_mask;
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
assign carrier_i = 1'b0; // Unused: always 0, so carrier is effectively BPSK on Q.
assign carrier_q = 1'b1;
assign mod_i = symbol_i ^ carrier_i;
assign mod_q = symbol_q ^ carrier_q;
assign tx_symbol_valid = mod_busy_reg && dds_tvalid;

assign tone_mode_dac1 = tone_mode_dac1_ff2;
assign tone_dds_q_s16 = tone_dds_tdata[31:16];
assign tone_dds_i_s16 = tone_dds_tdata[15:0];
assign tone_dac1_h = tone_dds_i_s16[13:0];
assign tone_dac1_l = tone_dds_q_s16[13:0];
assign tone_dac2_h = tone_dds_q_s16[15:2];
assign tone_dac2_l = tone_dds_q_s16[15:2];


fl9781_tx_wrapper fl9781_tx_wrapper_inst (
    .i_clk(i_dac1_clk),
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

wire dac_sample_valid_mux;
wire [13:0] dac1_h_mux;
wire [13:0] dac1_l_mux;
wire [13:0] dac2_h_mux;
wire [13:0] dac2_l_mux;

assign dac_sample_valid_mux = tone_mode_dac1 ? tone_dds_tvalid : dds_iq_tvalid;
assign dac1_h_mux = tone_mode_dac1 ? tone_dac1_h : bpsk_i_s14;
assign dac1_l_mux = tone_mode_dac1 ? tone_dac1_l : bpsk_q_s14;
assign dac2_h_mux = DAC_PARK_MIDSCALE;
assign dac2_l_mux = DAC_PARK_MIDSCALE;

// Double-flop DAC outputs into the DAC clock domains before DDR launch.
reg [13:0] o_dac1_h_ff1;
reg [13:0] o_dac1_l_ff1;
reg [13:0] o_dac2_h_ff1;
reg [13:0] o_dac2_l_ff1;
reg        o_dac1_sample_valid_ff1;
// mark_debug removed: these are negedge DAC-domain FFs; ILA cannot be placed in that domain.
// Use the CDC-bridged dac1_h_dbg_250 probe in KC705_EEE299_top.v instead.
reg [13:0] o_dac1_h_ff2;
reg [13:0] o_dac1_l_ff2;
reg [13:0] o_dac1_h_ff2_prev;
reg [13:0] o_dac2_h_ff2;
reg [13:0] o_dac2_l_ff2;
reg        o_dac1_sample_valid_ff2;

// DAC1 pipeline FFs on negedge: feeds SAME_EDGE ODDR (which captures D1/D2 on posedge) with
// a full half-cycle of setup time and a full half-cycle of hold — correct for 500 MHz DDR.
always @(negedge i_dac1_clk) begin
    if (i_rst) begin
        tone_mode_dac1_ff1 <= 1'b0;
        tone_mode_dac1_ff2 <= 1'b0;
        tone_pinc_dac1_stable <= 32'h7AE147A;
    end else begin
        tone_mode_dac1_ff1 <= i_tone_mode;
        tone_mode_dac1_ff2 <= tone_mode_dac1_ff1;
        // Accept a new increment only after two consecutive DAC-domain samples agree.
        if (tone_pinc_dac1_ff1 == tone_pinc_dac1_ff2) begin
            tone_pinc_dac1_stable <= tone_pinc_dac1_ff2[15:0];
        end
    end

    o_dac1_h_ff1 <= dac1_h_mux;
    o_dac1_l_ff1 <= dac1_l_mux;
    o_dac1_sample_valid_ff1 <= dac_sample_valid_mux;
    o_dac1_h_ff2 <= o_dac1_h_ff1;
    o_dac1_l_ff2 <= o_dac1_l_ff1;
    o_dac1_h_ff2_prev <= o_dac1_h_ff2;
    o_dac1_sample_valid_ff2 <= o_dac1_sample_valid_ff1;
end

always @(negedge i_dac2_clk) begin
    o_dac2_h_ff1 <= dac2_h_mux;
    o_dac2_l_ff1 <= dac2_l_mux;
    o_dac2_h_ff2 <= o_dac2_h_ff1;
    o_dac2_l_ff2 <= o_dac2_l_ff1;
end

assign o_dac_sample_valid = o_dac1_sample_valid_ff2;
assign o_dac1_h = o_dac1_h_ff2;
assign o_dac1_l = o_dac1_l_ff2;
assign o_dac2_h = o_dac2_h_ff2;
assign o_dac2_l = o_dac2_l_ff2;

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

function automatic logic signed [13:0] sine_lut(input logic [9:0] idx);
    begin
        case (idx)
            10'd0: sine_lut = 14'h0000;
            10'd1: sine_lut = 14'h0019;
            10'd2: sine_lut = 14'h0032;
            10'd3: sine_lut = 14'h004B;
            10'd4: sine_lut = 14'h0064;
            10'd5: sine_lut = 14'h007E;
            10'd6: sine_lut = 14'h0097;
            10'd7: sine_lut = 14'h00B0;
            10'd8: sine_lut = 14'h00C9;
            10'd9: sine_lut = 14'h00E2;
            10'd10: sine_lut = 14'h00FB;
            10'd11: sine_lut = 14'h0114;
            10'd12: sine_lut = 14'h012D;
            10'd13: sine_lut = 14'h0146;
            10'd14: sine_lut = 14'h015F;
            10'd15: sine_lut = 14'h0178;
            10'd16: sine_lut = 14'h0191;
            10'd17: sine_lut = 14'h01AA;
            10'd18: sine_lut = 14'h01C3;
            10'd19: sine_lut = 14'h01DC;
            10'd20: sine_lut = 14'h01F5;
            10'd21: sine_lut = 14'h020E;
            10'd22: sine_lut = 14'h0227;
            10'd23: sine_lut = 14'h0240;
            10'd24: sine_lut = 14'h0259;
            10'd25: sine_lut = 14'h0272;
            10'd26: sine_lut = 14'h028B;
            10'd27: sine_lut = 14'h02A3;
            10'd28: sine_lut = 14'h02BC;
            10'd29: sine_lut = 14'h02D5;
            10'd30: sine_lut = 14'h02EE;
            10'd31: sine_lut = 14'h0306;
            10'd32: sine_lut = 14'h031F;
            10'd33: sine_lut = 14'h0338;
            10'd34: sine_lut = 14'h0350;
            10'd35: sine_lut = 14'h0369;
            10'd36: sine_lut = 14'h0381;
            10'd37: sine_lut = 14'h039A;
            10'd38: sine_lut = 14'h03B2;
            10'd39: sine_lut = 14'h03CB;
            10'd40: sine_lut = 14'h03E3;
            10'd41: sine_lut = 14'h03FB;
            10'd42: sine_lut = 14'h0414;
            10'd43: sine_lut = 14'h042C;
            10'd44: sine_lut = 14'h0444;
            10'd45: sine_lut = 14'h045C;
            10'd46: sine_lut = 14'h0475;
            10'd47: sine_lut = 14'h048D;
            10'd48: sine_lut = 14'h04A5;
            10'd49: sine_lut = 14'h04BD;
            10'd50: sine_lut = 14'h04D5;
            10'd51: sine_lut = 14'h04ED;
            10'd52: sine_lut = 14'h0505;
            10'd53: sine_lut = 14'h051C;
            10'd54: sine_lut = 14'h0534;
            10'd55: sine_lut = 14'h054C;
            10'd56: sine_lut = 14'h0564;
            10'd57: sine_lut = 14'h057B;
            10'd58: sine_lut = 14'h0593;
            10'd59: sine_lut = 14'h05AA;
            10'd60: sine_lut = 14'h05C2;
            10'd61: sine_lut = 14'h05D9;
            10'd62: sine_lut = 14'h05F1;
            10'd63: sine_lut = 14'h0608;
            10'd64: sine_lut = 14'h061F;
            10'd65: sine_lut = 14'h0636;
            10'd66: sine_lut = 14'h064D;
            10'd67: sine_lut = 14'h0664;
            10'd68: sine_lut = 14'h067B;
            10'd69: sine_lut = 14'h0692;
            10'd70: sine_lut = 14'h06A9;
            10'd71: sine_lut = 14'h06C0;
            10'd72: sine_lut = 14'h06D7;
            10'd73: sine_lut = 14'h06EE;
            10'd74: sine_lut = 14'h0704;
            10'd75: sine_lut = 14'h071B;
            10'd76: sine_lut = 14'h0731;
            10'd77: sine_lut = 14'h0748;
            10'd78: sine_lut = 14'h075E;
            10'd79: sine_lut = 14'h0774;
            10'd80: sine_lut = 14'h078A;
            10'd81: sine_lut = 14'h07A0;
            10'd82: sine_lut = 14'h07B7;
            10'd83: sine_lut = 14'h07CD;
            10'd84: sine_lut = 14'h07E2;
            10'd85: sine_lut = 14'h07F8;
            10'd86: sine_lut = 14'h080E;
            10'd87: sine_lut = 14'h0824;
            10'd88: sine_lut = 14'h0839;
            10'd89: sine_lut = 14'h084F;
            10'd90: sine_lut = 14'h0864;
            10'd91: sine_lut = 14'h087A;
            10'd92: sine_lut = 14'h088F;
            10'd93: sine_lut = 14'h08A4;
            10'd94: sine_lut = 14'h08B9;
            10'd95: sine_lut = 14'h08CE;
            10'd96: sine_lut = 14'h08E3;
            10'd97: sine_lut = 14'h08F8;
            10'd98: sine_lut = 14'h090D;
            10'd99: sine_lut = 14'h0921;
            10'd100: sine_lut = 14'h0936;
            10'd101: sine_lut = 14'h094A;
            10'd102: sine_lut = 14'h095F;
            10'd103: sine_lut = 14'h0973;
            10'd104: sine_lut = 14'h0987;
            10'd105: sine_lut = 14'h099C;
            10'd106: sine_lut = 14'h09B0;
            10'd107: sine_lut = 14'h09C4;
            10'd108: sine_lut = 14'h09D7;
            10'd109: sine_lut = 14'h09EB;
            10'd110: sine_lut = 14'h09FF;
            10'd111: sine_lut = 14'h0A12;
            10'd112: sine_lut = 14'h0A26;
            10'd113: sine_lut = 14'h0A39;
            10'd114: sine_lut = 14'h0A4C;
            10'd115: sine_lut = 14'h0A60;
            10'd116: sine_lut = 14'h0A73;
            10'd117: sine_lut = 14'h0A86;
            10'd118: sine_lut = 14'h0A99;
            10'd119: sine_lut = 14'h0AAB;
            10'd120: sine_lut = 14'h0ABE;
            10'd121: sine_lut = 14'h0AD1;
            10'd122: sine_lut = 14'h0AE3;
            10'd123: sine_lut = 14'h0AF5;
            10'd124: sine_lut = 14'h0B08;
            10'd125: sine_lut = 14'h0B1A;
            10'd126: sine_lut = 14'h0B2C;
            10'd127: sine_lut = 14'h0B3E;
            10'd128: sine_lut = 14'h0B50;
            10'd129: sine_lut = 14'h0B61;
            10'd130: sine_lut = 14'h0B73;
            10'd131: sine_lut = 14'h0B84;
            10'd132: sine_lut = 14'h0B96;
            10'd133: sine_lut = 14'h0BA7;
            10'd134: sine_lut = 14'h0BB8;
            10'd135: sine_lut = 14'h0BC9;
            10'd136: sine_lut = 14'h0BDA;
            10'd137: sine_lut = 14'h0BEB;
            10'd138: sine_lut = 14'h0BFC;
            10'd139: sine_lut = 14'h0C0C;
            10'd140: sine_lut = 14'h0C1D;
            10'd141: sine_lut = 14'h0C2D;
            10'd142: sine_lut = 14'h0C3D;
            10'd143: sine_lut = 14'h0C4D;
            10'd144: sine_lut = 14'h0C5D;
            10'd145: sine_lut = 14'h0C6D;
            10'd146: sine_lut = 14'h0C7D;
            10'd147: sine_lut = 14'h0C8D;
            10'd148: sine_lut = 14'h0C9C;
            10'd149: sine_lut = 14'h0CAC;
            10'd150: sine_lut = 14'h0CBB;
            10'd151: sine_lut = 14'h0CCA;
            10'd152: sine_lut = 14'h0CD9;
            10'd153: sine_lut = 14'h0CE8;
            10'd154: sine_lut = 14'h0CF7;
            10'd155: sine_lut = 14'h0D05;
            10'd156: sine_lut = 14'h0D14;
            10'd157: sine_lut = 14'h0D22;
            10'd158: sine_lut = 14'h0D31;
            10'd159: sine_lut = 14'h0D3F;
            10'd160: sine_lut = 14'h0D4D;
            10'd161: sine_lut = 14'h0D5B;
            10'd162: sine_lut = 14'h0D69;
            10'd163: sine_lut = 14'h0D76;
            10'd164: sine_lut = 14'h0D84;
            10'd165: sine_lut = 14'h0D91;
            10'd166: sine_lut = 14'h0D9E;
            10'd167: sine_lut = 14'h0DAB;
            10'd168: sine_lut = 14'h0DB8;
            10'd169: sine_lut = 14'h0DC5;
            10'd170: sine_lut = 14'h0DD2;
            10'd171: sine_lut = 14'h0DDF;
            10'd172: sine_lut = 14'h0DEB;
            10'd173: sine_lut = 14'h0DF7;
            10'd174: sine_lut = 14'h0E04;
            10'd175: sine_lut = 14'h0E10;
            10'd176: sine_lut = 14'h0E1B;
            10'd177: sine_lut = 14'h0E27;
            10'd178: sine_lut = 14'h0E33;
            10'd179: sine_lut = 14'h0E3E;
            10'd180: sine_lut = 14'h0E4A;
            10'd181: sine_lut = 14'h0E55;
            10'd182: sine_lut = 14'h0E60;
            10'd183: sine_lut = 14'h0E6B;
            10'd184: sine_lut = 14'h0E76;
            10'd185: sine_lut = 14'h0E81;
            10'd186: sine_lut = 14'h0E8B;
            10'd187: sine_lut = 14'h0E95;
            10'd188: sine_lut = 14'h0EA0;
            10'd189: sine_lut = 14'h0EAA;
            10'd190: sine_lut = 14'h0EB4;
            10'd191: sine_lut = 14'h0EBE;
            10'd192: sine_lut = 14'h0EC7;
            10'd193: sine_lut = 14'h0ED1;
            10'd194: sine_lut = 14'h0EDA;
            10'd195: sine_lut = 14'h0EE3;
            10'd196: sine_lut = 14'h0EED;
            10'd197: sine_lut = 14'h0EF6;
            10'd198: sine_lut = 14'h0EFE;
            10'd199: sine_lut = 14'h0F07;
            10'd200: sine_lut = 14'h0F10;
            10'd201: sine_lut = 14'h0F18;
            10'd202: sine_lut = 14'h0F20;
            10'd203: sine_lut = 14'h0F28;
            10'd204: sine_lut = 14'h0F30;
            10'd205: sine_lut = 14'h0F38;
            10'd206: sine_lut = 14'h0F40;
            10'd207: sine_lut = 14'h0F47;
            10'd208: sine_lut = 14'h0F4F;
            10'd209: sine_lut = 14'h0F56;
            10'd210: sine_lut = 14'h0F5D;
            10'd211: sine_lut = 14'h0F64;
            10'd212: sine_lut = 14'h0F6B;
            10'd213: sine_lut = 14'h0F71;
            10'd214: sine_lut = 14'h0F78;
            10'd215: sine_lut = 14'h0F7E;
            10'd216: sine_lut = 14'h0F84;
            10'd217: sine_lut = 14'h0F8A;
            10'd218: sine_lut = 14'h0F90;
            10'd219: sine_lut = 14'h0F96;
            10'd220: sine_lut = 14'h0F9C;
            10'd221: sine_lut = 14'h0FA1;
            10'd222: sine_lut = 14'h0FA6;
            10'd223: sine_lut = 14'h0FAB;
            10'd224: sine_lut = 14'h0FB0;
            10'd225: sine_lut = 14'h0FB5;
            10'd226: sine_lut = 14'h0FBA;
            10'd227: sine_lut = 14'h0FBE;
            10'd228: sine_lut = 14'h0FC3;
            10'd229: sine_lut = 14'h0FC7;
            10'd230: sine_lut = 14'h0FCB;
            10'd231: sine_lut = 14'h0FCF;
            10'd232: sine_lut = 14'h0FD3;
            10'd233: sine_lut = 14'h0FD6;
            10'd234: sine_lut = 14'h0FDA;
            10'd235: sine_lut = 14'h0FDD;
            10'd236: sine_lut = 14'h0FE0;
            10'd237: sine_lut = 14'h0FE3;
            10'd238: sine_lut = 14'h0FE6;
            10'd239: sine_lut = 14'h0FE9;
            10'd240: sine_lut = 14'h0FEB;
            10'd241: sine_lut = 14'h0FEE;
            10'd242: sine_lut = 14'h0FF0;
            10'd243: sine_lut = 14'h0FF2;
            10'd244: sine_lut = 14'h0FF4;
            10'd245: sine_lut = 14'h0FF6;
            10'd246: sine_lut = 14'h0FF7;
            10'd247: sine_lut = 14'h0FF9;
            10'd248: sine_lut = 14'h0FFA;
            10'd249: sine_lut = 14'h0FFB;
            10'd250: sine_lut = 14'h0FFC;
            10'd251: sine_lut = 14'h0FFD;
            10'd252: sine_lut = 14'h0FFE;
            10'd253: sine_lut = 14'h0FFE;
            10'd254: sine_lut = 14'h0FFF;
            10'd255: sine_lut = 14'h0FFF;
            10'd256: sine_lut = 14'h0FFF;
            10'd257: sine_lut = 14'h0FFF;
            10'd258: sine_lut = 14'h0FFF;
            10'd259: sine_lut = 14'h0FFE;
            10'd260: sine_lut = 14'h0FFE;
            10'd261: sine_lut = 14'h0FFD;
            10'd262: sine_lut = 14'h0FFC;
            10'd263: sine_lut = 14'h0FFB;
            10'd264: sine_lut = 14'h0FFA;
            10'd265: sine_lut = 14'h0FF9;
            10'd266: sine_lut = 14'h0FF7;
            10'd267: sine_lut = 14'h0FF6;
            10'd268: sine_lut = 14'h0FF4;
            10'd269: sine_lut = 14'h0FF2;
            10'd270: sine_lut = 14'h0FF0;
            10'd271: sine_lut = 14'h0FEE;
            10'd272: sine_lut = 14'h0FEB;
            10'd273: sine_lut = 14'h0FE9;
            10'd274: sine_lut = 14'h0FE6;
            10'd275: sine_lut = 14'h0FE3;
            10'd276: sine_lut = 14'h0FE0;
            10'd277: sine_lut = 14'h0FDD;
            10'd278: sine_lut = 14'h0FDA;
            10'd279: sine_lut = 14'h0FD6;
            10'd280: sine_lut = 14'h0FD3;
            10'd281: sine_lut = 14'h0FCF;
            10'd282: sine_lut = 14'h0FCB;
            10'd283: sine_lut = 14'h0FC7;
            10'd284: sine_lut = 14'h0FC3;
            10'd285: sine_lut = 14'h0FBE;
            10'd286: sine_lut = 14'h0FBA;
            10'd287: sine_lut = 14'h0FB5;
            10'd288: sine_lut = 14'h0FB0;
            10'd289: sine_lut = 14'h0FAB;
            10'd290: sine_lut = 14'h0FA6;
            10'd291: sine_lut = 14'h0FA1;
            10'd292: sine_lut = 14'h0F9C;
            10'd293: sine_lut = 14'h0F96;
            10'd294: sine_lut = 14'h0F90;
            10'd295: sine_lut = 14'h0F8A;
            10'd296: sine_lut = 14'h0F84;
            10'd297: sine_lut = 14'h0F7E;
            10'd298: sine_lut = 14'h0F78;
            10'd299: sine_lut = 14'h0F71;
            10'd300: sine_lut = 14'h0F6B;
            10'd301: sine_lut = 14'h0F64;
            10'd302: sine_lut = 14'h0F5D;
            10'd303: sine_lut = 14'h0F56;
            10'd304: sine_lut = 14'h0F4F;
            10'd305: sine_lut = 14'h0F47;
            10'd306: sine_lut = 14'h0F40;
            10'd307: sine_lut = 14'h0F38;
            10'd308: sine_lut = 14'h0F30;
            10'd309: sine_lut = 14'h0F28;
            10'd310: sine_lut = 14'h0F20;
            10'd311: sine_lut = 14'h0F18;
            10'd312: sine_lut = 14'h0F10;
            10'd313: sine_lut = 14'h0F07;
            10'd314: sine_lut = 14'h0EFE;
            10'd315: sine_lut = 14'h0EF6;
            10'd316: sine_lut = 14'h0EED;
            10'd317: sine_lut = 14'h0EE3;
            10'd318: sine_lut = 14'h0EDA;
            10'd319: sine_lut = 14'h0ED1;
            10'd320: sine_lut = 14'h0EC7;
            10'd321: sine_lut = 14'h0EBE;
            10'd322: sine_lut = 14'h0EB4;
            10'd323: sine_lut = 14'h0EAA;
            10'd324: sine_lut = 14'h0EA0;
            10'd325: sine_lut = 14'h0E95;
            10'd326: sine_lut = 14'h0E8B;
            10'd327: sine_lut = 14'h0E81;
            10'd328: sine_lut = 14'h0E76;
            10'd329: sine_lut = 14'h0E6B;
            10'd330: sine_lut = 14'h0E60;
            10'd331: sine_lut = 14'h0E55;
            10'd332: sine_lut = 14'h0E4A;
            10'd333: sine_lut = 14'h0E3E;
            10'd334: sine_lut = 14'h0E33;
            10'd335: sine_lut = 14'h0E27;
            10'd336: sine_lut = 14'h0E1B;
            10'd337: sine_lut = 14'h0E10;
            10'd338: sine_lut = 14'h0E04;
            10'd339: sine_lut = 14'h0DF7;
            10'd340: sine_lut = 14'h0DEB;
            10'd341: sine_lut = 14'h0DDF;
            10'd342: sine_lut = 14'h0DD2;
            10'd343: sine_lut = 14'h0DC5;
            10'd344: sine_lut = 14'h0DB8;
            10'd345: sine_lut = 14'h0DAB;
            10'd346: sine_lut = 14'h0D9E;
            10'd347: sine_lut = 14'h0D91;
            10'd348: sine_lut = 14'h0D84;
            10'd349: sine_lut = 14'h0D76;
            10'd350: sine_lut = 14'h0D69;
            10'd351: sine_lut = 14'h0D5B;
            10'd352: sine_lut = 14'h0D4D;
            10'd353: sine_lut = 14'h0D3F;
            10'd354: sine_lut = 14'h0D31;
            10'd355: sine_lut = 14'h0D22;
            10'd356: sine_lut = 14'h0D14;
            10'd357: sine_lut = 14'h0D05;
            10'd358: sine_lut = 14'h0CF7;
            10'd359: sine_lut = 14'h0CE8;
            10'd360: sine_lut = 14'h0CD9;
            10'd361: sine_lut = 14'h0CCA;
            10'd362: sine_lut = 14'h0CBB;
            10'd363: sine_lut = 14'h0CAC;
            10'd364: sine_lut = 14'h0C9C;
            10'd365: sine_lut = 14'h0C8D;
            10'd366: sine_lut = 14'h0C7D;
            10'd367: sine_lut = 14'h0C6D;
            10'd368: sine_lut = 14'h0C5D;
            10'd369: sine_lut = 14'h0C4D;
            10'd370: sine_lut = 14'h0C3D;
            10'd371: sine_lut = 14'h0C2D;
            10'd372: sine_lut = 14'h0C1D;
            10'd373: sine_lut = 14'h0C0C;
            10'd374: sine_lut = 14'h0BFC;
            10'd375: sine_lut = 14'h0BEB;
            10'd376: sine_lut = 14'h0BDA;
            10'd377: sine_lut = 14'h0BC9;
            10'd378: sine_lut = 14'h0BB8;
            10'd379: sine_lut = 14'h0BA7;
            10'd380: sine_lut = 14'h0B96;
            10'd381: sine_lut = 14'h0B84;
            10'd382: sine_lut = 14'h0B73;
            10'd383: sine_lut = 14'h0B61;
            10'd384: sine_lut = 14'h0B50;
            10'd385: sine_lut = 14'h0B3E;
            10'd386: sine_lut = 14'h0B2C;
            10'd387: sine_lut = 14'h0B1A;
            10'd388: sine_lut = 14'h0B08;
            10'd389: sine_lut = 14'h0AF5;
            10'd390: sine_lut = 14'h0AE3;
            10'd391: sine_lut = 14'h0AD1;
            10'd392: sine_lut = 14'h0ABE;
            10'd393: sine_lut = 14'h0AAB;
            10'd394: sine_lut = 14'h0A99;
            10'd395: sine_lut = 14'h0A86;
            10'd396: sine_lut = 14'h0A73;
            10'd397: sine_lut = 14'h0A60;
            10'd398: sine_lut = 14'h0A4C;
            10'd399: sine_lut = 14'h0A39;
            10'd400: sine_lut = 14'h0A26;
            10'd401: sine_lut = 14'h0A12;
            10'd402: sine_lut = 14'h09FF;
            10'd403: sine_lut = 14'h09EB;
            10'd404: sine_lut = 14'h09D7;
            10'd405: sine_lut = 14'h09C4;
            10'd406: sine_lut = 14'h09B0;
            10'd407: sine_lut = 14'h099C;
            10'd408: sine_lut = 14'h0987;
            10'd409: sine_lut = 14'h0973;
            10'd410: sine_lut = 14'h095F;
            10'd411: sine_lut = 14'h094A;
            10'd412: sine_lut = 14'h0936;
            10'd413: sine_lut = 14'h0921;
            10'd414: sine_lut = 14'h090D;
            10'd415: sine_lut = 14'h08F8;
            10'd416: sine_lut = 14'h08E3;
            10'd417: sine_lut = 14'h08CE;
            10'd418: sine_lut = 14'h08B9;
            10'd419: sine_lut = 14'h08A4;
            10'd420: sine_lut = 14'h088F;
            10'd421: sine_lut = 14'h087A;
            10'd422: sine_lut = 14'h0864;
            10'd423: sine_lut = 14'h084F;
            10'd424: sine_lut = 14'h0839;
            10'd425: sine_lut = 14'h0824;
            10'd426: sine_lut = 14'h080E;
            10'd427: sine_lut = 14'h07F8;
            10'd428: sine_lut = 14'h07E2;
            10'd429: sine_lut = 14'h07CD;
            10'd430: sine_lut = 14'h07B7;
            10'd431: sine_lut = 14'h07A0;
            10'd432: sine_lut = 14'h078A;
            10'd433: sine_lut = 14'h0774;
            10'd434: sine_lut = 14'h075E;
            10'd435: sine_lut = 14'h0748;
            10'd436: sine_lut = 14'h0731;
            10'd437: sine_lut = 14'h071B;
            10'd438: sine_lut = 14'h0704;
            10'd439: sine_lut = 14'h06EE;
            10'd440: sine_lut = 14'h06D7;
            10'd441: sine_lut = 14'h06C0;
            10'd442: sine_lut = 14'h06A9;
            10'd443: sine_lut = 14'h0692;
            10'd444: sine_lut = 14'h067B;
            10'd445: sine_lut = 14'h0664;
            10'd446: sine_lut = 14'h064D;
            10'd447: sine_lut = 14'h0636;
            10'd448: sine_lut = 14'h061F;
            10'd449: sine_lut = 14'h0608;
            10'd450: sine_lut = 14'h05F1;
            10'd451: sine_lut = 14'h05D9;
            10'd452: sine_lut = 14'h05C2;
            10'd453: sine_lut = 14'h05AA;
            10'd454: sine_lut = 14'h0593;
            10'd455: sine_lut = 14'h057B;
            10'd456: sine_lut = 14'h0564;
            10'd457: sine_lut = 14'h054C;
            10'd458: sine_lut = 14'h0534;
            10'd459: sine_lut = 14'h051C;
            10'd460: sine_lut = 14'h0505;
            10'd461: sine_lut = 14'h04ED;
            10'd462: sine_lut = 14'h04D5;
            10'd463: sine_lut = 14'h04BD;
            10'd464: sine_lut = 14'h04A5;
            10'd465: sine_lut = 14'h048D;
            10'd466: sine_lut = 14'h0475;
            10'd467: sine_lut = 14'h045C;
            10'd468: sine_lut = 14'h0444;
            10'd469: sine_lut = 14'h042C;
            10'd470: sine_lut = 14'h0414;
            10'd471: sine_lut = 14'h03FB;
            10'd472: sine_lut = 14'h03E3;
            10'd473: sine_lut = 14'h03CB;
            10'd474: sine_lut = 14'h03B2;
            10'd475: sine_lut = 14'h039A;
            10'd476: sine_lut = 14'h0381;
            10'd477: sine_lut = 14'h0369;
            10'd478: sine_lut = 14'h0350;
            10'd479: sine_lut = 14'h0338;
            10'd480: sine_lut = 14'h031F;
            10'd481: sine_lut = 14'h0306;
            10'd482: sine_lut = 14'h02EE;
            10'd483: sine_lut = 14'h02D5;
            10'd484: sine_lut = 14'h02BC;
            10'd485: sine_lut = 14'h02A3;
            10'd486: sine_lut = 14'h028B;
            10'd487: sine_lut = 14'h0272;
            10'd488: sine_lut = 14'h0259;
            10'd489: sine_lut = 14'h0240;
            10'd490: sine_lut = 14'h0227;
            10'd491: sine_lut = 14'h020E;
            10'd492: sine_lut = 14'h01F5;
            10'd493: sine_lut = 14'h01DC;
            10'd494: sine_lut = 14'h01C3;
            10'd495: sine_lut = 14'h01AA;
            10'd496: sine_lut = 14'h0191;
            10'd497: sine_lut = 14'h0178;
            10'd498: sine_lut = 14'h015F;
            10'd499: sine_lut = 14'h0146;
            10'd500: sine_lut = 14'h012D;
            10'd501: sine_lut = 14'h0114;
            10'd502: sine_lut = 14'h00FB;
            10'd503: sine_lut = 14'h00E2;
            10'd504: sine_lut = 14'h00C9;
            10'd505: sine_lut = 14'h00B0;
            10'd506: sine_lut = 14'h0097;
            10'd507: sine_lut = 14'h007E;
            10'd508: sine_lut = 14'h0064;
            10'd509: sine_lut = 14'h004B;
            10'd510: sine_lut = 14'h0032;
            10'd511: sine_lut = 14'h0019;
            10'd512: sine_lut = 14'h0000;
            10'd513: sine_lut = 14'h3FE7;
            10'd514: sine_lut = 14'h3FCE;
            10'd515: sine_lut = 14'h3FB5;
            10'd516: sine_lut = 14'h3F9C;
            10'd517: sine_lut = 14'h3F82;
            10'd518: sine_lut = 14'h3F69;
            10'd519: sine_lut = 14'h3F50;
            10'd520: sine_lut = 14'h3F37;
            10'd521: sine_lut = 14'h3F1E;
            10'd522: sine_lut = 14'h3F05;
            10'd523: sine_lut = 14'h3EEC;
            10'd524: sine_lut = 14'h3ED3;
            10'd525: sine_lut = 14'h3EBA;
            10'd526: sine_lut = 14'h3EA1;
            10'd527: sine_lut = 14'h3E88;
            10'd528: sine_lut = 14'h3E6F;
            10'd529: sine_lut = 14'h3E56;
            10'd530: sine_lut = 14'h3E3D;
            10'd531: sine_lut = 14'h3E24;
            10'd532: sine_lut = 14'h3E0B;
            10'd533: sine_lut = 14'h3DF2;
            10'd534: sine_lut = 14'h3DD9;
            10'd535: sine_lut = 14'h3DC0;
            10'd536: sine_lut = 14'h3DA7;
            10'd537: sine_lut = 14'h3D8E;
            10'd538: sine_lut = 14'h3D75;
            10'd539: sine_lut = 14'h3D5D;
            10'd540: sine_lut = 14'h3D44;
            10'd541: sine_lut = 14'h3D2B;
            10'd542: sine_lut = 14'h3D12;
            10'd543: sine_lut = 14'h3CFA;
            10'd544: sine_lut = 14'h3CE1;
            10'd545: sine_lut = 14'h3CC8;
            10'd546: sine_lut = 14'h3CB0;
            10'd547: sine_lut = 14'h3C97;
            10'd548: sine_lut = 14'h3C7F;
            10'd549: sine_lut = 14'h3C66;
            10'd550: sine_lut = 14'h3C4E;
            10'd551: sine_lut = 14'h3C35;
            10'd552: sine_lut = 14'h3C1D;
            10'd553: sine_lut = 14'h3C05;
            10'd554: sine_lut = 14'h3BEC;
            10'd555: sine_lut = 14'h3BD4;
            10'd556: sine_lut = 14'h3BBC;
            10'd557: sine_lut = 14'h3BA4;
            10'd558: sine_lut = 14'h3B8B;
            10'd559: sine_lut = 14'h3B73;
            10'd560: sine_lut = 14'h3B5B;
            10'd561: sine_lut = 14'h3B43;
            10'd562: sine_lut = 14'h3B2B;
            10'd563: sine_lut = 14'h3B13;
            10'd564: sine_lut = 14'h3AFB;
            10'd565: sine_lut = 14'h3AE4;
            10'd566: sine_lut = 14'h3ACC;
            10'd567: sine_lut = 14'h3AB4;
            10'd568: sine_lut = 14'h3A9C;
            10'd569: sine_lut = 14'h3A85;
            10'd570: sine_lut = 14'h3A6D;
            10'd571: sine_lut = 14'h3A56;
            10'd572: sine_lut = 14'h3A3E;
            10'd573: sine_lut = 14'h3A27;
            10'd574: sine_lut = 14'h3A0F;
            10'd575: sine_lut = 14'h39F8;
            10'd576: sine_lut = 14'h39E1;
            10'd577: sine_lut = 14'h39CA;
            10'd578: sine_lut = 14'h39B3;
            10'd579: sine_lut = 14'h399C;
            10'd580: sine_lut = 14'h3985;
            10'd581: sine_lut = 14'h396E;
            10'd582: sine_lut = 14'h3957;
            10'd583: sine_lut = 14'h3940;
            10'd584: sine_lut = 14'h3929;
            10'd585: sine_lut = 14'h3912;
            10'd586: sine_lut = 14'h38FC;
            10'd587: sine_lut = 14'h38E5;
            10'd588: sine_lut = 14'h38CF;
            10'd589: sine_lut = 14'h38B8;
            10'd590: sine_lut = 14'h38A2;
            10'd591: sine_lut = 14'h388C;
            10'd592: sine_lut = 14'h3876;
            10'd593: sine_lut = 14'h3860;
            10'd594: sine_lut = 14'h3849;
            10'd595: sine_lut = 14'h3833;
            10'd596: sine_lut = 14'h381E;
            10'd597: sine_lut = 14'h3808;
            10'd598: sine_lut = 14'h37F2;
            10'd599: sine_lut = 14'h37DC;
            10'd600: sine_lut = 14'h37C7;
            10'd601: sine_lut = 14'h37B1;
            10'd602: sine_lut = 14'h379C;
            10'd603: sine_lut = 14'h3786;
            10'd604: sine_lut = 14'h3771;
            10'd605: sine_lut = 14'h375C;
            10'd606: sine_lut = 14'h3747;
            10'd607: sine_lut = 14'h3732;
            10'd608: sine_lut = 14'h371D;
            10'd609: sine_lut = 14'h3708;
            10'd610: sine_lut = 14'h36F3;
            10'd611: sine_lut = 14'h36DF;
            10'd612: sine_lut = 14'h36CA;
            10'd613: sine_lut = 14'h36B6;
            10'd614: sine_lut = 14'h36A1;
            10'd615: sine_lut = 14'h368D;
            10'd616: sine_lut = 14'h3679;
            10'd617: sine_lut = 14'h3664;
            10'd618: sine_lut = 14'h3650;
            10'd619: sine_lut = 14'h363C;
            10'd620: sine_lut = 14'h3629;
            10'd621: sine_lut = 14'h3615;
            10'd622: sine_lut = 14'h3601;
            10'd623: sine_lut = 14'h35EE;
            10'd624: sine_lut = 14'h35DA;
            10'd625: sine_lut = 14'h35C7;
            10'd626: sine_lut = 14'h35B4;
            10'd627: sine_lut = 14'h35A0;
            10'd628: sine_lut = 14'h358D;
            10'd629: sine_lut = 14'h357A;
            10'd630: sine_lut = 14'h3567;
            10'd631: sine_lut = 14'h3555;
            10'd632: sine_lut = 14'h3542;
            10'd633: sine_lut = 14'h352F;
            10'd634: sine_lut = 14'h351D;
            10'd635: sine_lut = 14'h350B;
            10'd636: sine_lut = 14'h34F8;
            10'd637: sine_lut = 14'h34E6;
            10'd638: sine_lut = 14'h34D4;
            10'd639: sine_lut = 14'h34C2;
            10'd640: sine_lut = 14'h34B0;
            10'd641: sine_lut = 14'h349F;
            10'd642: sine_lut = 14'h348D;
            10'd643: sine_lut = 14'h347C;
            10'd644: sine_lut = 14'h346A;
            10'd645: sine_lut = 14'h3459;
            10'd646: sine_lut = 14'h3448;
            10'd647: sine_lut = 14'h3437;
            10'd648: sine_lut = 14'h3426;
            10'd649: sine_lut = 14'h3415;
            10'd650: sine_lut = 14'h3404;
            10'd651: sine_lut = 14'h33F4;
            10'd652: sine_lut = 14'h33E3;
            10'd653: sine_lut = 14'h33D3;
            10'd654: sine_lut = 14'h33C3;
            10'd655: sine_lut = 14'h33B3;
            10'd656: sine_lut = 14'h33A3;
            10'd657: sine_lut = 14'h3393;
            10'd658: sine_lut = 14'h3383;
            10'd659: sine_lut = 14'h3373;
            10'd660: sine_lut = 14'h3364;
            10'd661: sine_lut = 14'h3354;
            10'd662: sine_lut = 14'h3345;
            10'd663: sine_lut = 14'h3336;
            10'd664: sine_lut = 14'h3327;
            10'd665: sine_lut = 14'h3318;
            10'd666: sine_lut = 14'h3309;
            10'd667: sine_lut = 14'h32FB;
            10'd668: sine_lut = 14'h32EC;
            10'd669: sine_lut = 14'h32DE;
            10'd670: sine_lut = 14'h32CF;
            10'd671: sine_lut = 14'h32C1;
            10'd672: sine_lut = 14'h32B3;
            10'd673: sine_lut = 14'h32A5;
            10'd674: sine_lut = 14'h3297;
            10'd675: sine_lut = 14'h328A;
            10'd676: sine_lut = 14'h327C;
            10'd677: sine_lut = 14'h326F;
            10'd678: sine_lut = 14'h3262;
            10'd679: sine_lut = 14'h3255;
            10'd680: sine_lut = 14'h3248;
            10'd681: sine_lut = 14'h323B;
            10'd682: sine_lut = 14'h322E;
            10'd683: sine_lut = 14'h3221;
            10'd684: sine_lut = 14'h3215;
            10'd685: sine_lut = 14'h3209;
            10'd686: sine_lut = 14'h31FC;
            10'd687: sine_lut = 14'h31F0;
            10'd688: sine_lut = 14'h31E5;
            10'd689: sine_lut = 14'h31D9;
            10'd690: sine_lut = 14'h31CD;
            10'd691: sine_lut = 14'h31C2;
            10'd692: sine_lut = 14'h31B6;
            10'd693: sine_lut = 14'h31AB;
            10'd694: sine_lut = 14'h31A0;
            10'd695: sine_lut = 14'h3195;
            10'd696: sine_lut = 14'h318A;
            10'd697: sine_lut = 14'h317F;
            10'd698: sine_lut = 14'h3175;
            10'd699: sine_lut = 14'h316B;
            10'd700: sine_lut = 14'h3160;
            10'd701: sine_lut = 14'h3156;
            10'd702: sine_lut = 14'h314C;
            10'd703: sine_lut = 14'h3142;
            10'd704: sine_lut = 14'h3139;
            10'd705: sine_lut = 14'h312F;
            10'd706: sine_lut = 14'h3126;
            10'd707: sine_lut = 14'h311D;
            10'd708: sine_lut = 14'h3113;
            10'd709: sine_lut = 14'h310A;
            10'd710: sine_lut = 14'h3102;
            10'd711: sine_lut = 14'h30F9;
            10'd712: sine_lut = 14'h30F0;
            10'd713: sine_lut = 14'h30E8;
            10'd714: sine_lut = 14'h30E0;
            10'd715: sine_lut = 14'h30D8;
            10'd716: sine_lut = 14'h30D0;
            10'd717: sine_lut = 14'h30C8;
            10'd718: sine_lut = 14'h30C0;
            10'd719: sine_lut = 14'h30B9;
            10'd720: sine_lut = 14'h30B1;
            10'd721: sine_lut = 14'h30AA;
            10'd722: sine_lut = 14'h30A3;
            10'd723: sine_lut = 14'h309C;
            10'd724: sine_lut = 14'h3095;
            10'd725: sine_lut = 14'h308F;
            10'd726: sine_lut = 14'h3088;
            10'd727: sine_lut = 14'h3082;
            10'd728: sine_lut = 14'h307C;
            10'd729: sine_lut = 14'h3076;
            10'd730: sine_lut = 14'h3070;
            10'd731: sine_lut = 14'h306A;
            10'd732: sine_lut = 14'h3064;
            10'd733: sine_lut = 14'h305F;
            10'd734: sine_lut = 14'h305A;
            10'd735: sine_lut = 14'h3055;
            10'd736: sine_lut = 14'h3050;
            10'd737: sine_lut = 14'h304B;
            10'd738: sine_lut = 14'h3046;
            10'd739: sine_lut = 14'h3042;
            10'd740: sine_lut = 14'h303D;
            10'd741: sine_lut = 14'h3039;
            10'd742: sine_lut = 14'h3035;
            10'd743: sine_lut = 14'h3031;
            10'd744: sine_lut = 14'h302D;
            10'd745: sine_lut = 14'h302A;
            10'd746: sine_lut = 14'h3026;
            10'd747: sine_lut = 14'h3023;
            10'd748: sine_lut = 14'h3020;
            10'd749: sine_lut = 14'h301D;
            10'd750: sine_lut = 14'h301A;
            10'd751: sine_lut = 14'h3017;
            10'd752: sine_lut = 14'h3015;
            10'd753: sine_lut = 14'h3012;
            10'd754: sine_lut = 14'h3010;
            10'd755: sine_lut = 14'h300E;
            10'd756: sine_lut = 14'h300C;
            10'd757: sine_lut = 14'h300A;
            10'd758: sine_lut = 14'h3009;
            10'd759: sine_lut = 14'h3007;
            10'd760: sine_lut = 14'h3006;
            10'd761: sine_lut = 14'h3005;
            10'd762: sine_lut = 14'h3004;
            10'd763: sine_lut = 14'h3003;
            10'd764: sine_lut = 14'h3002;
            10'd765: sine_lut = 14'h3002;
            10'd766: sine_lut = 14'h3001;
            10'd767: sine_lut = 14'h3001;
            10'd768: sine_lut = 14'h3001;
            10'd769: sine_lut = 14'h3001;
            10'd770: sine_lut = 14'h3001;
            10'd771: sine_lut = 14'h3002;
            10'd772: sine_lut = 14'h3002;
            10'd773: sine_lut = 14'h3003;
            10'd774: sine_lut = 14'h3004;
            10'd775: sine_lut = 14'h3005;
            10'd776: sine_lut = 14'h3006;
            10'd777: sine_lut = 14'h3007;
            10'd778: sine_lut = 14'h3009;
            10'd779: sine_lut = 14'h300A;
            10'd780: sine_lut = 14'h300C;
            10'd781: sine_lut = 14'h300E;
            10'd782: sine_lut = 14'h3010;
            10'd783: sine_lut = 14'h3012;
            10'd784: sine_lut = 14'h3015;
            10'd785: sine_lut = 14'h3017;
            10'd786: sine_lut = 14'h301A;
            10'd787: sine_lut = 14'h301D;
            10'd788: sine_lut = 14'h3020;
            10'd789: sine_lut = 14'h3023;
            10'd790: sine_lut = 14'h3026;
            10'd791: sine_lut = 14'h302A;
            10'd792: sine_lut = 14'h302D;
            10'd793: sine_lut = 14'h3031;
            10'd794: sine_lut = 14'h3035;
            10'd795: sine_lut = 14'h3039;
            10'd796: sine_lut = 14'h303D;
            10'd797: sine_lut = 14'h3042;
            10'd798: sine_lut = 14'h3046;
            10'd799: sine_lut = 14'h304B;
            10'd800: sine_lut = 14'h3050;
            10'd801: sine_lut = 14'h3055;
            10'd802: sine_lut = 14'h305A;
            10'd803: sine_lut = 14'h305F;
            10'd804: sine_lut = 14'h3064;
            10'd805: sine_lut = 14'h306A;
            10'd806: sine_lut = 14'h3070;
            10'd807: sine_lut = 14'h3076;
            10'd808: sine_lut = 14'h307C;
            10'd809: sine_lut = 14'h3082;
            10'd810: sine_lut = 14'h3088;
            10'd811: sine_lut = 14'h308F;
            10'd812: sine_lut = 14'h3095;
            10'd813: sine_lut = 14'h309C;
            10'd814: sine_lut = 14'h30A3;
            10'd815: sine_lut = 14'h30AA;
            10'd816: sine_lut = 14'h30B1;
            10'd817: sine_lut = 14'h30B9;
            10'd818: sine_lut = 14'h30C0;
            10'd819: sine_lut = 14'h30C8;
            10'd820: sine_lut = 14'h30D0;
            10'd821: sine_lut = 14'h30D8;
            10'd822: sine_lut = 14'h30E0;
            10'd823: sine_lut = 14'h30E8;
            10'd824: sine_lut = 14'h30F0;
            10'd825: sine_lut = 14'h30F9;
            10'd826: sine_lut = 14'h3102;
            10'd827: sine_lut = 14'h310A;
            10'd828: sine_lut = 14'h3113;
            10'd829: sine_lut = 14'h311D;
            10'd830: sine_lut = 14'h3126;
            10'd831: sine_lut = 14'h312F;
            10'd832: sine_lut = 14'h3139;
            10'd833: sine_lut = 14'h3142;
            10'd834: sine_lut = 14'h314C;
            10'd835: sine_lut = 14'h3156;
            10'd836: sine_lut = 14'h3160;
            10'd837: sine_lut = 14'h316B;
            10'd838: sine_lut = 14'h3175;
            10'd839: sine_lut = 14'h317F;
            10'd840: sine_lut = 14'h318A;
            10'd841: sine_lut = 14'h3195;
            10'd842: sine_lut = 14'h31A0;
            10'd843: sine_lut = 14'h31AB;
            10'd844: sine_lut = 14'h31B6;
            10'd845: sine_lut = 14'h31C2;
            10'd846: sine_lut = 14'h31CD;
            10'd847: sine_lut = 14'h31D9;
            10'd848: sine_lut = 14'h31E5;
            10'd849: sine_lut = 14'h31F0;
            10'd850: sine_lut = 14'h31FC;
            10'd851: sine_lut = 14'h3209;
            10'd852: sine_lut = 14'h3215;
            10'd853: sine_lut = 14'h3221;
            10'd854: sine_lut = 14'h322E;
            10'd855: sine_lut = 14'h323B;
            10'd856: sine_lut = 14'h3248;
            10'd857: sine_lut = 14'h3255;
            10'd858: sine_lut = 14'h3262;
            10'd859: sine_lut = 14'h326F;
            10'd860: sine_lut = 14'h327C;
            10'd861: sine_lut = 14'h328A;
            10'd862: sine_lut = 14'h3297;
            10'd863: sine_lut = 14'h32A5;
            10'd864: sine_lut = 14'h32B3;
            10'd865: sine_lut = 14'h32C1;
            10'd866: sine_lut = 14'h32CF;
            10'd867: sine_lut = 14'h32DE;
            10'd868: sine_lut = 14'h32EC;
            10'd869: sine_lut = 14'h32FB;
            10'd870: sine_lut = 14'h3309;
            10'd871: sine_lut = 14'h3318;
            10'd872: sine_lut = 14'h3327;
            10'd873: sine_lut = 14'h3336;
            10'd874: sine_lut = 14'h3345;
            10'd875: sine_lut = 14'h3354;
            10'd876: sine_lut = 14'h3364;
            10'd877: sine_lut = 14'h3373;
            10'd878: sine_lut = 14'h3383;
            10'd879: sine_lut = 14'h3393;
            10'd880: sine_lut = 14'h33A3;
            10'd881: sine_lut = 14'h33B3;
            10'd882: sine_lut = 14'h33C3;
            10'd883: sine_lut = 14'h33D3;
            10'd884: sine_lut = 14'h33E3;
            10'd885: sine_lut = 14'h33F4;
            10'd886: sine_lut = 14'h3404;
            10'd887: sine_lut = 14'h3415;
            10'd888: sine_lut = 14'h3426;
            10'd889: sine_lut = 14'h3437;
            10'd890: sine_lut = 14'h3448;
            10'd891: sine_lut = 14'h3459;
            10'd892: sine_lut = 14'h346A;
            10'd893: sine_lut = 14'h347C;
            10'd894: sine_lut = 14'h348D;
            10'd895: sine_lut = 14'h349F;
            10'd896: sine_lut = 14'h34B0;
            10'd897: sine_lut = 14'h34C2;
            10'd898: sine_lut = 14'h34D4;
            10'd899: sine_lut = 14'h34E6;
            10'd900: sine_lut = 14'h34F8;
            10'd901: sine_lut = 14'h350B;
            10'd902: sine_lut = 14'h351D;
            10'd903: sine_lut = 14'h352F;
            10'd904: sine_lut = 14'h3542;
            10'd905: sine_lut = 14'h3555;
            10'd906: sine_lut = 14'h3567;
            10'd907: sine_lut = 14'h357A;
            10'd908: sine_lut = 14'h358D;
            10'd909: sine_lut = 14'h35A0;
            10'd910: sine_lut = 14'h35B4;
            10'd911: sine_lut = 14'h35C7;
            10'd912: sine_lut = 14'h35DA;
            10'd913: sine_lut = 14'h35EE;
            10'd914: sine_lut = 14'h3601;
            10'd915: sine_lut = 14'h3615;
            10'd916: sine_lut = 14'h3629;
            10'd917: sine_lut = 14'h363C;
            10'd918: sine_lut = 14'h3650;
            10'd919: sine_lut = 14'h3664;
            10'd920: sine_lut = 14'h3679;
            10'd921: sine_lut = 14'h368D;
            10'd922: sine_lut = 14'h36A1;
            10'd923: sine_lut = 14'h36B6;
            10'd924: sine_lut = 14'h36CA;
            10'd925: sine_lut = 14'h36DF;
            10'd926: sine_lut = 14'h36F3;
            10'd927: sine_lut = 14'h3708;
            10'd928: sine_lut = 14'h371D;
            10'd929: sine_lut = 14'h3732;
            10'd930: sine_lut = 14'h3747;
            10'd931: sine_lut = 14'h375C;
            10'd932: sine_lut = 14'h3771;
            10'd933: sine_lut = 14'h3786;
            10'd934: sine_lut = 14'h379C;
            10'd935: sine_lut = 14'h37B1;
            10'd936: sine_lut = 14'h37C7;
            10'd937: sine_lut = 14'h37DC;
            10'd938: sine_lut = 14'h37F2;
            10'd939: sine_lut = 14'h3808;
            10'd940: sine_lut = 14'h381E;
            10'd941: sine_lut = 14'h3833;
            10'd942: sine_lut = 14'h3849;
            10'd943: sine_lut = 14'h3860;
            10'd944: sine_lut = 14'h3876;
            10'd945: sine_lut = 14'h388C;
            10'd946: sine_lut = 14'h38A2;
            10'd947: sine_lut = 14'h38B8;
            10'd948: sine_lut = 14'h38CF;
            10'd949: sine_lut = 14'h38E5;
            10'd950: sine_lut = 14'h38FC;
            10'd951: sine_lut = 14'h3912;
            10'd952: sine_lut = 14'h3929;
            10'd953: sine_lut = 14'h3940;
            10'd954: sine_lut = 14'h3957;
            10'd955: sine_lut = 14'h396E;
            10'd956: sine_lut = 14'h3985;
            10'd957: sine_lut = 14'h399C;
            10'd958: sine_lut = 14'h39B3;
            10'd959: sine_lut = 14'h39CA;
            10'd960: sine_lut = 14'h39E1;
            10'd961: sine_lut = 14'h39F8;
            10'd962: sine_lut = 14'h3A0F;
            10'd963: sine_lut = 14'h3A27;
            10'd964: sine_lut = 14'h3A3E;
            10'd965: sine_lut = 14'h3A56;
            10'd966: sine_lut = 14'h3A6D;
            10'd967: sine_lut = 14'h3A85;
            10'd968: sine_lut = 14'h3A9C;
            10'd969: sine_lut = 14'h3AB4;
            10'd970: sine_lut = 14'h3ACC;
            10'd971: sine_lut = 14'h3AE4;
            10'd972: sine_lut = 14'h3AFB;
            10'd973: sine_lut = 14'h3B13;
            10'd974: sine_lut = 14'h3B2B;
            10'd975: sine_lut = 14'h3B43;
            10'd976: sine_lut = 14'h3B5B;
            10'd977: sine_lut = 14'h3B73;
            10'd978: sine_lut = 14'h3B8B;
            10'd979: sine_lut = 14'h3BA4;
            10'd980: sine_lut = 14'h3BBC;
            10'd981: sine_lut = 14'h3BD4;
            10'd982: sine_lut = 14'h3BEC;
            10'd983: sine_lut = 14'h3C05;
            10'd984: sine_lut = 14'h3C1D;
            10'd985: sine_lut = 14'h3C35;
            10'd986: sine_lut = 14'h3C4E;
            10'd987: sine_lut = 14'h3C66;
            10'd988: sine_lut = 14'h3C7F;
            10'd989: sine_lut = 14'h3C97;
            10'd990: sine_lut = 14'h3CB0;
            10'd991: sine_lut = 14'h3CC8;
            10'd992: sine_lut = 14'h3CE1;
            10'd993: sine_lut = 14'h3CFA;
            10'd994: sine_lut = 14'h3D12;
            10'd995: sine_lut = 14'h3D2B;
            10'd996: sine_lut = 14'h3D44;
            10'd997: sine_lut = 14'h3D5D;
            10'd998: sine_lut = 14'h3D75;
            10'd999: sine_lut = 14'h3D8E;
            10'd1000: sine_lut = 14'h3DA7;
            10'd1001: sine_lut = 14'h3DC0;
            10'd1002: sine_lut = 14'h3DD9;
            10'd1003: sine_lut = 14'h3DF2;
            10'd1004: sine_lut = 14'h3E0B;
            10'd1005: sine_lut = 14'h3E24;
            10'd1006: sine_lut = 14'h3E3D;
            10'd1007: sine_lut = 14'h3E56;
            10'd1008: sine_lut = 14'h3E6F;
            10'd1009: sine_lut = 14'h3E88;
            10'd1010: sine_lut = 14'h3EA1;
            10'd1011: sine_lut = 14'h3EBA;
            10'd1012: sine_lut = 14'h3ED3;
            10'd1013: sine_lut = 14'h3EEC;
            10'd1014: sine_lut = 14'h3F05;
            10'd1015: sine_lut = 14'h3F1E;
            10'd1016: sine_lut = 14'h3F37;
            10'd1017: sine_lut = 14'h3F50;
            10'd1018: sine_lut = 14'h3F69;
            10'd1019: sine_lut = 14'h3F82;
            10'd1020: sine_lut = 14'h3F9C;
            10'd1021: sine_lut = 14'h3FB5;
            10'd1022: sine_lut = 14'h3FCE;
            10'd1023: sine_lut = 14'h3FE7;
            default: sine_lut = 14'h0000;
        endcase
    end
endfunction

endmodule
