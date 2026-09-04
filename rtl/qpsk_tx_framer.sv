`timescale 1ns / 1ps
`default_nettype none
//
// qpsk_tx_framer.sv — QPSK Packet TX Framer
//
// Accepts 32 bytes of payload via AXI-Stream, frames them with a known
// preamble (20 symbols) and postamble (20 symbols), and outputs QPSK
// symbols at a configurable rate (CLKS_PER_SYMBOL DAC clocks per symbol).
//
// Symbol mapping (Gray-coded):
//   bits[1:0] = {I_bit, Q_bit}
//   00 → I=+1, Q=+1  (45°)
//   01 → I=+1, Q=-1  (315°)
//   10 → I=-1, Q=+1  (135°)
//   11 → I=-1, Q=-1  (225°)
//
// Frame: [PREAMBLE 20 sym] [DATA 128 sym (32 bytes × 4 sym/byte)] [POSTAMBLE 20 sym]
//        Total = 168 symbols per frame
//
module qpsk_tx_framer #(
    parameter int CLKS_PER_SYMBOL   = 32,       // DAC clocks per symbol (166.67 MHz / 32 ≈ 5.2 Msym/s)
    parameter int PAYLOAD_BYTES     = 32,       // Bytes of data per frame
    parameter int PREAMBLE_LEN      = 20,       // Symbols in preamble
    parameter int POSTAMBLE_LEN     = 20,       // Symbols in postamble
    parameter logic signed [13:0] SYMBOL_AMP = 14'sd6000  // Output amplitude (< 8191 for headroom)
) (
    input  wire        i_clk,          // DAC clock (500 MHz)
    input  wire        i_rst,

    // AXI-Stream input: payload bytes (in system clock domain — must be CDC'd externally)
    input  wire [7:0]  i_s_axis_tdata,
    input  wire        i_s_axis_tvalid,
    output logic       o_s_axis_tready,
    input  wire        i_s_axis_tlast,  // ignored; framer uses fixed payload length

    // QPSK DAC output
    output logic signed [13:0] o_i_sample,
    output logic signed [13:0] o_q_sample,
    output logic               o_symbol_valid,  // pulses once per new symbol
    output logic               o_frame_active   // high during entire frame
);

// ──────────────────────────────────────────────────────────────────────
// Preamble & Postamble ROMs (each entry: {I_bit, Q_bit})
// ──────────────────────────────────────────────────────────────────────
// Preamble structure:
//   [0:7]   Timing acquisition: alternating +/- for fast clock recovery
//   [8:15]  Frame sync: Barker-like QPSK sequence (good autocorrelation)
//   [16:19] Phase reference: known constellation points for ambiguity resolve
//
localparam logic [1:0] PREAMBLE_ROM [0:PREAMBLE_LEN-1] = '{
    // Timing acquisition (alternating)
    2'b00, 2'b11, 2'b00, 2'b11, 2'b00, 2'b11, 2'b00, 2'b11,
    // Frame sync (PN-like, good cross-correlation properties)
    2'b00, 2'b10, 2'b11, 2'b01, 2'b10, 2'b00, 2'b01, 2'b11,
    // Phase reference (known points: 45°, 135°, 225°, 315°)
    2'b00, 2'b10, 2'b11, 2'b01
};

localparam logic [1:0] POSTAMBLE_ROM [0:POSTAMBLE_LEN-1] = '{
    // Mirror of preamble (allows tail-end correlation for bidirectional search)
    2'b01, 2'b11, 2'b10, 2'b00,
    2'b11, 2'b01, 2'b00, 2'b10, 2'b01, 2'b11, 2'b00, 2'b10,
    2'b11, 2'b00, 2'b11, 2'b00, 2'b11, 2'b00, 2'b11, 2'b00
};

// ──────────────────────────────────────────────────────────────────────
// Payload buffer
// ──────────────────────────────────────────────────────────────────────
localparam int DATA_SYMBOLS = PAYLOAD_BYTES * 4;  // 4 QPSK symbols per byte
localparam int TOTAL_SYMBOLS = PREAMBLE_LEN + DATA_SYMBOLS + POSTAMBLE_LEN;

logic [7:0] payload_buf [0:PAYLOAD_BYTES-1];
logic [$clog2(PAYLOAD_BYTES)-1:0] wr_ptr;
logic payload_ready;

// ──────────────────────────────────────────────────────────────────────
// State machine
// ──────────────────────────────────────────────────────────────────────
typedef enum logic [2:0] {
    S_IDLE,
    S_LOAD,
    S_PREAMBLE,
    S_DATA,
    S_POSTAMBLE
} state_t;

state_t state;
logic [$clog2(CLKS_PER_SYMBOL)-1:0] clk_cnt;   // counts DAC clocks within one symbol
logic [$clog2(TOTAL_SYMBOLS)-1:0]   sym_cnt;    // counts symbols within current section
logic [1:0] current_symbol;                      // {I_bit, Q_bit} for current symbol

// Data symbol extraction: 4 symbols per byte, MSB first
// Byte bits [7:6] -> sym0, [5:4] -> sym1, [3:2] -> sym2, [1:0] -> sym3
wire [$clog2(PAYLOAD_BYTES)-1:0] data_byte_idx = sym_cnt[$clog2(DATA_SYMBOLS)-1:2];
wire [1:0] data_sym_idx = sym_cnt[1:0];
wire [7:0] data_byte = payload_buf[data_byte_idx];
wire [1:0] data_symbol = (data_sym_idx == 2'd0) ? data_byte[7:6] :
                          (data_sym_idx == 2'd1) ? data_byte[5:4] :
                          (data_sym_idx == 2'd2) ? data_byte[3:2] :
                                                   data_byte[1:0];

// Next data symbol (for sym_cnt + 1) - used when advancing
wire [$clog2(DATA_SYMBOLS)-1:0] next_data_idx = sym_cnt + 1;
wire [$clog2(PAYLOAD_BYTES)-1:0] next_data_byte_idx = next_data_idx[$clog2(DATA_SYMBOLS)-1:2];
wire [1:0] next_data_sym_idx = next_data_idx[1:0];
wire [7:0] next_data_byte = payload_buf[next_data_byte_idx];
wire [1:0] next_data_symbol = (next_data_sym_idx == 2'd0) ? next_data_byte[7:6] :
                               (next_data_sym_idx == 2'd1) ? next_data_byte[5:4] :
                               (next_data_sym_idx == 2'd2) ? next_data_byte[3:2] :
                                                              next_data_byte[1:0];

// First data symbol (index 0) - used at preamble->data transition
wire [1:0] first_data_symbol = payload_buf[0][7:6];

// ──────────────────────────────────────────────────────────────────────
// Main logic
// ──────────────────────────────────────────────────────────────────────
always_ff @(posedge i_clk) begin
    if (i_rst) begin
        state          <= S_IDLE;
        clk_cnt        <= '0;
        sym_cnt        <= '0;
        wr_ptr         <= '0;
        payload_ready  <= 1'b0;
        o_s_axis_tready <= 1'b0;
        o_i_sample     <= 14'sd0;
        o_q_sample     <= 14'sd0;
        o_symbol_valid <= 1'b0;
        o_frame_active <= 1'b0;
        current_symbol <= 2'b00;
    end else begin
        o_symbol_valid <= 1'b0;  // default: pulse

        case (state)
        // ──────────────────────────────────────────────────
        S_IDLE: begin
            o_frame_active  <= 1'b0;
            o_s_axis_tready <= 1'b1;
            o_i_sample      <= 14'sd0;
            o_q_sample      <= 14'sd0;
            if (i_s_axis_tvalid && o_s_axis_tready) begin
                payload_buf[0] <= i_s_axis_tdata;
                wr_ptr         <= 1;
                state          <= S_LOAD;
            end
        end

        // ──────────────────────────────────────────────────
        S_LOAD: begin
            o_s_axis_tready <= 1'b1;
            if (i_s_axis_tvalid) begin
                payload_buf[wr_ptr] <= i_s_axis_tdata;
                if (wr_ptr == PAYLOAD_BYTES - 1) begin
                    o_s_axis_tready <= 1'b0;
                    state           <= S_PREAMBLE;
                    sym_cnt         <= '0;
                    clk_cnt         <= '0;
                    o_frame_active  <= 1'b1;
                    current_symbol  <= PREAMBLE_ROM[0];
                    o_symbol_valid  <= 1'b1;
                    // Drive first preamble symbol immediately
                    o_i_sample <= PREAMBLE_ROM[0][1] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_q_sample <= PREAMBLE_ROM[0][0] ? -SYMBOL_AMP : SYMBOL_AMP;
                end else begin
                    wr_ptr <= wr_ptr + 1;
                end
            end
        end

        // ──────────────────────────────────────────────────
        S_PREAMBLE: begin
            o_s_axis_tready <= 1'b0;
            if (clk_cnt == CLKS_PER_SYMBOL - 1) begin
                clk_cnt <= '0;
                if (sym_cnt == PREAMBLE_LEN - 1) begin
                    // Transition to DATA - use explicit first symbol
                    state          <= S_DATA;
                    sym_cnt        <= '0;
                    current_symbol <= first_data_symbol;
                    o_i_sample     <= first_data_symbol[1] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_q_sample     <= first_data_symbol[0] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_symbol_valid <= 1'b1;
                end else begin
                    sym_cnt        <= sym_cnt + 1;
                    current_symbol <= PREAMBLE_ROM[sym_cnt + 1];
                    o_i_sample     <= PREAMBLE_ROM[sym_cnt + 1][1] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_q_sample     <= PREAMBLE_ROM[sym_cnt + 1][0] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_symbol_valid <= 1'b1;
                end
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end

        // ──────────────────────────────────────────────────
        S_DATA: begin
            if (clk_cnt == CLKS_PER_SYMBOL - 1) begin
                clk_cnt <= '0;
                if (sym_cnt == DATA_SYMBOLS - 1) begin
                    // Transition to POSTAMBLE
                    state          <= S_POSTAMBLE;
                    sym_cnt        <= '0;
                    current_symbol <= POSTAMBLE_ROM[0];
                    o_i_sample     <= POSTAMBLE_ROM[0][1] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_q_sample     <= POSTAMBLE_ROM[0][0] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_symbol_valid <= 1'b1;
                end else begin
                    sym_cnt        <= sym_cnt + 1;
                    current_symbol <= next_data_symbol;
                    o_i_sample     <= next_data_symbol[1] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_q_sample     <= next_data_symbol[0] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_symbol_valid <= 1'b1;
                end
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end

        // ──────────────────────────────────────────────────
        S_POSTAMBLE: begin
            if (clk_cnt == CLKS_PER_SYMBOL - 1) begin
                clk_cnt <= '0;
                if (sym_cnt == POSTAMBLE_LEN - 1) begin
                    // Frame complete
                    state          <= S_IDLE;
                    o_frame_active <= 1'b0;
                    o_i_sample     <= 14'sd0;
                    o_q_sample     <= 14'sd0;
                    wr_ptr         <= '0;
                end else begin
                    sym_cnt        <= sym_cnt + 1;
                    current_symbol <= POSTAMBLE_ROM[sym_cnt + 1];
                    o_i_sample     <= POSTAMBLE_ROM[sym_cnt + 1][1] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_q_sample     <= POSTAMBLE_ROM[sym_cnt + 1][0] ? -SYMBOL_AMP : SYMBOL_AMP;
                    o_symbol_valid <= 1'b1;
                end
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end

        default: state <= S_IDLE;
        endcase
    end
end

endmodule

`default_nettype wire
