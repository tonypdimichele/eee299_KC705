`timescale 1ns / 1ps
`default_nettype wire

module qpsk_tx_modulator #(
    parameter int unsigned CLK_HZ = 166_666_667,
    parameter int unsigned BIT_RATE_BPS = 5_000_000,
    parameter int unsigned FIFO_DEPTH = 2048,
    parameter int unsigned PAYLOAD_BYTES_PER_PACKET = 500,
    parameter logic [63:0] START_SEQ_64 = 64'hD5_AA_96_C3_F0_0F_5A_3C,
    parameter logic [63:0] STOP_SEQ_64  = 64'h3C_5A_0F_F0_C3_96_AA_D5,
    parameter logic signed [13:0] SYMBOL_AMP = 14'sd4096,
    parameter bit ENABLE_SHAPING = 1'b0,
    parameter bit ENABLE_RRC = 1'b1,
    parameter int unsigned SHAPE_SHIFT = 6,
    parameter int unsigned SHAPE_FRAC_BITS = 6,
    parameter int unsigned RRC_OUT_SHIFT = 9
) (
    input  logic        i_clk,
    input  logic        i_rst,

    input  logic [15:0] i_word_data,
    input  logic        i_word_valid,
    output logic        o_word_ready,

    output logic        o_sample_valid,
    output logic signed [13:0] o_i,
    output logic signed [13:0] o_q,

    output logic        o_symbol_tick,
    output logic [1:0]  o_dbg_symbol_bits
);

localparam int unsigned SYMBOL_RATE_SPS = BIT_RATE_BPS / 2;
localparam longint unsigned PHASE_INC = ((longint'(SYMBOL_RATE_SPS) << 32) + (CLK_HZ / 2)) / CLK_HZ;
localparam int unsigned FIFO_AW = $clog2(FIFO_DEPTH);

logic [31:0] symbol_phase;
logic [32:0] symbol_phase_next;

logic [7:0] fifo_mem [0:FIFO_DEPTH-1];
logic [FIFO_AW-1:0] wr_ptr;
logic [FIFO_AW-1:0] rd_ptr;
logic [FIFO_AW:0] fifo_count;

logic [7:0] active_byte;
logic [1:0] symbol_idx;
logic       active_byte_valid;
logic [1:0] symbol_bits;
logic signed [13:0] raw_i;
logic signed [13:0] raw_q;
logic       push_word;
logic [1:0] packet_mode;
logic [2:0] frame_byte_idx;
logic [$clog2(PAYLOAD_BYTES_PER_PACKET+1)-1:0] payload_byte_count;

localparam logic [1:0] PKT_MODE_START   = 2'd0;
localparam logic [1:0] PKT_MODE_PAYLOAD = 2'd1;
localparam logic [1:0] PKT_MODE_STOP    = 2'd2;
localparam int unsigned SHAPER_W = 14 + SHAPE_FRAC_BITS + 2;
logic signed [SHAPER_W-1:0] shaper_i;
logic signed [SHAPER_W-1:0] shaper_q;
logic signed [SHAPER_W-1:0] raw_i_ext;
logic signed [SHAPER_W-1:0] raw_q_ext;
logic signed [SHAPER_W-1:0] shaper_i_next;
logic signed [SHAPER_W-1:0] shaper_q_next;

localparam int unsigned RRC_TAPS = 17;
localparam logic signed [9:0] RRC_COEFFS [0:RRC_TAPS-1] = '{
    -10'sd3, 10'sd0, 10'sd8, 10'sd18, 10'sd30, 10'sd44, 10'sd56, 10'sd64, 10'sd67,
     10'sd64, 10'sd56, 10'sd44, 10'sd30, 10'sd18, 10'sd8, 10'sd0, -10'sd3
};

logic signed [13:0] rrc_i_hist [0:RRC_TAPS-1];
logic signed [13:0] rrc_q_hist [0:RRC_TAPS-1];
logic signed [31:0] rrc_acc_i;
logic signed [31:0] rrc_acc_q;
logic signed [13:0] rrc_i_out;
logic signed [13:0] rrc_q_out;

function automatic logic signed [13:0] sym_to_level(input logic bit_val);
    begin
        sym_to_level = bit_val ? SYMBOL_AMP : -SYMBOL_AMP;
    end
endfunction

function automatic logic [7:0] seq_byte(input logic [63:0] seq, input logic [2:0] idx);
    begin
        seq_byte = seq[63 - (idx*8) -: 8];
    end
endfunction

function automatic logic signed [13:0] sat_s32_to_s14(input logic signed [31:0] x);
    begin
        if (x > 32'sd8191) begin
            sat_s32_to_s14 = 14'sd8191;
        end else if (x < -32'sd8192) begin
            sat_s32_to_s14 = -14'sd8192;
        end else begin
            sat_s32_to_s14 = x[13:0];
        end
    end
endfunction

assign o_word_ready = (fifo_count <= (FIFO_DEPTH-2));
assign o_sample_valid = 1'b1;
assign o_symbol_tick = symbol_phase_next[32];
assign o_dbg_symbol_bits = symbol_bits;
assign push_word = i_word_valid && o_word_ready;

always_comb begin
    symbol_phase_next = {1'b0, symbol_phase} + {1'b0, PHASE_INC[31:0]};
end

always_comb begin
    raw_i_ext = $signed(raw_i) <<< SHAPE_FRAC_BITS;
    raw_q_ext = $signed(raw_q) <<< SHAPE_FRAC_BITS;
    shaper_i_next = shaper_i + ((raw_i_ext - shaper_i) >>> SHAPE_SHIFT);
    shaper_q_next = shaper_q + ((raw_q_ext - shaper_q) >>> SHAPE_SHIFT);
end

always_comb begin
    integer k;
    rrc_acc_i = 32'sd0;
    rrc_acc_q = 32'sd0;
    for (k = 0; k < RRC_TAPS; k = k + 1) begin
        rrc_acc_i = rrc_acc_i + (rrc_i_hist[k] * RRC_COEFFS[k]);
        rrc_acc_q = rrc_acc_q + (rrc_q_hist[k] * RRC_COEFFS[k]);
    end
    rrc_i_out = sat_s32_to_s14(rrc_acc_i >>> RRC_OUT_SHIFT);
    rrc_q_out = sat_s32_to_s14(rrc_acc_q >>> RRC_OUT_SHIFT);
end

always_ff @(posedge i_clk) begin
    logic [1:0] curr_bits;
    logic       bits_valid;
    logic [7:0] next_byte;
    logic       load_next_byte;
    logic       pop_payload;

    if (i_rst) begin
        wr_ptr <= '0;
        rd_ptr <= '0;
        fifo_count <= '0;
        symbol_phase <= 32'd0;
        active_byte <= 8'd0;
        symbol_idx <= 2'd0;
        active_byte_valid <= 1'b0;
        symbol_bits <= 2'b00;
        packet_mode <= PKT_MODE_START;
        frame_byte_idx <= 3'd0;
        payload_byte_count <= '0;
        raw_i <= 14'sd0;
        raw_q <= 14'sd0;
    end else begin
        symbol_phase <= symbol_phase_next[31:0];
        pop_payload = 1'b0;

        if (push_word) begin
            fifo_mem[wr_ptr] <= i_word_data[15:8];
            fifo_mem[wr_ptr + 1'b1] <= i_word_data[7:0];
            wr_ptr <= wr_ptr + 2'd2;
        end

        if (o_symbol_tick) begin
            curr_bits = symbol_bits;
            bits_valid = 1'b0;
            next_byte = 8'h00;
            load_next_byte = 1'b0;

            if (!active_byte_valid) begin
                case (packet_mode)
                    PKT_MODE_START: begin
                        load_next_byte = 1'b1;
                        next_byte = seq_byte(START_SEQ_64, frame_byte_idx);
                    end
                    PKT_MODE_PAYLOAD: begin
                        if (fifo_count != 0) begin
                            load_next_byte = 1'b1;
                            next_byte = fifo_mem[rd_ptr];
                            pop_payload = 1'b1;
                        end
                    end
                    default: begin
                        load_next_byte = 1'b1;
                        next_byte = seq_byte(STOP_SEQ_64, frame_byte_idx);
                    end
                endcase

                if (load_next_byte) begin
                    active_byte <= next_byte;
                    active_byte_valid <= 1'b1;
                    symbol_idx <= 2'd1;
                    curr_bits = next_byte[7:6];
                    bits_valid = 1'b1;

                    if (packet_mode == PKT_MODE_START) begin
                        if (frame_byte_idx == 3'd7) begin
                            frame_byte_idx <= 3'd0;
                            packet_mode <= PKT_MODE_PAYLOAD;
                        end else begin
                            frame_byte_idx <= frame_byte_idx + 1'b1;
                        end
                    end else if (packet_mode == PKT_MODE_PAYLOAD) begin
                        if (payload_byte_count == PAYLOAD_BYTES_PER_PACKET-1) begin
                            payload_byte_count <= '0;
                            packet_mode <= PKT_MODE_STOP;
                            frame_byte_idx <= 3'd0;
                        end else begin
                            payload_byte_count <= payload_byte_count + 1'b1;
                        end
                    end else begin
                        if (frame_byte_idx == 3'd7) begin
                            frame_byte_idx <= 3'd0;
                            packet_mode <= PKT_MODE_START;
                        end else begin
                            frame_byte_idx <= frame_byte_idx + 1'b1;
                        end
                    end
                end else begin
                    curr_bits = 2'b00;
                end
            end else if (active_byte_valid) begin
                case (symbol_idx)
                    2'd0: curr_bits = active_byte[7:6];
                    2'd1: curr_bits = active_byte[5:4];
                    2'd2: curr_bits = active_byte[3:2];
                    default: curr_bits = active_byte[1:0];
                endcase
                bits_valid = 1'b1;

                if (symbol_idx == 2'd3) begin
                    symbol_idx <= 2'd0;

                    case (packet_mode)
                        PKT_MODE_START: begin
                            load_next_byte = 1'b1;
                            next_byte = seq_byte(START_SEQ_64, frame_byte_idx);
                        end
                        PKT_MODE_PAYLOAD: begin
                            if (fifo_count != 0) begin
                                load_next_byte = 1'b1;
                                next_byte = fifo_mem[rd_ptr];
                                pop_payload = 1'b1;
                            end
                        end
                        default: begin
                            load_next_byte = 1'b1;
                            next_byte = seq_byte(STOP_SEQ_64, frame_byte_idx);
                        end
                    endcase

                    if (load_next_byte) begin
                        active_byte <= next_byte;
                        active_byte_valid <= 1'b1;

                        if (packet_mode == PKT_MODE_START) begin
                            if (frame_byte_idx == 3'd7) begin
                                frame_byte_idx <= 3'd0;
                                packet_mode <= PKT_MODE_PAYLOAD;
                            end else begin
                                frame_byte_idx <= frame_byte_idx + 1'b1;
                            end
                        end else if (packet_mode == PKT_MODE_PAYLOAD) begin
                            if (payload_byte_count == PAYLOAD_BYTES_PER_PACKET-1) begin
                                payload_byte_count <= '0;
                                packet_mode <= PKT_MODE_STOP;
                                frame_byte_idx <= 3'd0;
                            end else begin
                                payload_byte_count <= payload_byte_count + 1'b1;
                            end
                        end else begin
                            if (frame_byte_idx == 3'd7) begin
                                frame_byte_idx <= 3'd0;
                                packet_mode <= PKT_MODE_START;
                            end else begin
                                frame_byte_idx <= frame_byte_idx + 1'b1;
                            end
                        end
                    end else begin
                        active_byte_valid <= 1'b0;
                    end
                end else begin
                    symbol_idx <= symbol_idx + 1'b1;
                end 
            end else begin
                curr_bits = 2'b00;
            end

            symbol_bits <= curr_bits;

            if (bits_valid) begin
                case (curr_bits)
                    2'b00: begin
                        raw_i <= sym_to_level(1'b1);
                        raw_q <= sym_to_level(1'b1);
                    end
                    2'b01: begin
                        raw_i <= sym_to_level(1'b1);
                        raw_q <= sym_to_level(1'b0);
                    end
                    2'b11: begin
                        raw_i <= sym_to_level(1'b0);
                        raw_q <= sym_to_level(1'b0);
                    end
                    default: begin
                        raw_i <= sym_to_level(1'b0);
                        raw_q <= sym_to_level(1'b1);
                    end
                endcase
            end else begin
                raw_i <= 14'sd0;
                raw_q <= 14'sd0;
            end
        end

        if (pop_payload) begin
            rd_ptr <= rd_ptr + 1'b1;
        end

        case ({push_word, pop_payload})
            2'b10: fifo_count <= fifo_count + 2'd2;
            2'b01: fifo_count <= fifo_count - 1'b1;
            2'b11: fifo_count <= fifo_count + 1'b1;
            default: fifo_count <= fifo_count;
        endcase
    end
end

always_ff @(posedge i_clk) begin
    integer k;

    if (i_rst) begin
        for (k = 0; k < RRC_TAPS; k = k + 1) begin
            rrc_i_hist[k] <= 14'sd0;
            rrc_q_hist[k] <= 14'sd0;
        end
    end else begin
        for (k = RRC_TAPS-1; k > 0; k = k - 1) begin
            rrc_i_hist[k] <= rrc_i_hist[k-1];
            rrc_q_hist[k] <= rrc_q_hist[k-1];
        end
        rrc_i_hist[0] <= raw_i;
        rrc_q_hist[0] <= raw_q;
    end
end

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        shaper_i <= '0;
        shaper_q <= '0;
        o_i <= 14'sd0;
        o_q <= 14'sd0;
    end else if (ENABLE_RRC) begin
        shaper_i <= '0;
        shaper_q <= '0;
        o_i <= rrc_i_out;
        o_q <= rrc_q_out;
    end else if (ENABLE_SHAPING) begin
        shaper_i <= shaper_i_next;
        shaper_q <= shaper_q_next;
        o_i <= sat_s32_to_s14($signed(shaper_i_next >>> SHAPE_FRAC_BITS));
        o_q <= sat_s32_to_s14($signed(shaper_q_next >>> SHAPE_FRAC_BITS));
    end else begin
        shaper_i <= '0;
        shaper_q <= '0;
        o_i <= raw_i;
        o_q <= raw_q;
    end
end

endmodule

`default_nettype wire
