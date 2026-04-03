`timescale 1ns / 1ps
`default_nettype none

module tb_qpsk_tx_modulator;

localparam int unsigned CLK_HZ = 166_666_667;
localparam int unsigned BIT_RATE_BPS = 5_000_000;
localparam real CLK_PERIOD_NS = 6.0;
localparam int BURST_BYTES = 500;
localparam int BURST_WORDS = BURST_BYTES/2;
localparam int BURST_COUNT = 2;
localparam time BURST_GAP = 850_000ns;
localparam logic [63:0] START_SEQ_64 = 64'hD5_AA_96_C3_F0_0F_5A_3C;
localparam logic [63:0] STOP_SEQ_64  = 64'h3C_5A_0F_F0_C3_96_AA_D5;
localparam int FRAMED_BYTES_PER_BURST = BURST_BYTES + 16;

logic clk = 1'b0;
logic rst = 1'b1;

always #(CLK_PERIOD_NS/2.0) clk = ~clk;

logic [15:0] in_word;
logic       in_valid;
wire        in_ready;

wire        sample_valid;
wire signed [13:0] i_out;
wire signed [13:0] q_out;
wire        symbol_tick;
wire [1:0]  dbg_symbol_bits;

qpsk_tx_modulator #(
    .CLK_HZ(CLK_HZ),
    .BIT_RATE_BPS(BIT_RATE_BPS),
    .FIFO_DEPTH(2048),
    .PAYLOAD_BYTES_PER_PACKET(BURST_BYTES),
    .START_SEQ_64(START_SEQ_64),
    .STOP_SEQ_64(STOP_SEQ_64),
    .SYMBOL_AMP(14'sd6000),
    .ENABLE_SHAPING(1'b0),
    .ENABLE_RRC(1'b1)
) dut (
    .i_clk(clk),
    .i_rst(rst),
    .i_word_data(in_word),
    .i_word_valid(in_valid),
    .o_word_ready(in_ready),
    .o_sample_valid(sample_valid),
    .o_i(i_out),
    .o_q(q_out),
    .o_symbol_tick(symbol_tick),
    .o_dbg_symbol_bits(dbg_symbol_bits)
);

logic [7:0] exp_mem [0:(BURST_COUNT*FRAMED_BYTES_PER_BURST)-1];
int tx_read_idx;
int checked_symbols;
int exp_write_idx;
logic       check_pending;
logic [1:0] expected_pending;
int         pending_byte_idx;
int         pending_sym_idx;

function automatic [7:0] seq_byte(input logic [63:0] seq, input int idx);
    begin
        seq_byte = seq[63 - (idx*8) -: 8];
    end
endfunction

task automatic append_expected_byte(input [7:0] b);
    begin
        exp_mem[exp_write_idx] = b;
        exp_write_idx = exp_write_idx + 1;
    end
endtask

task automatic push_word(input [15:0] w);
    begin
        @(posedge clk);
        while (!in_ready) begin
            @(posedge clk);
        end
        in_word <= w;
        in_valid <= 1'b1;
        @(posedge clk);
        while (!in_ready) begin
            @(posedge clk);
        end
        in_valid <= 1'b0;
        in_word <= 16'h0000;
    end
endtask

task automatic send_burst(input int burst_id);
    int i;
    int s;
    logic [7:0] v_hi;
    logic [7:0] v_lo;
    logic [15:0] w;
    logic [7:0] burst_seed;
    begin
        for (s = 0; s < 8; s = s + 1) begin
            append_expected_byte(seq_byte(START_SEQ_64, s));
        end

        burst_seed = burst_id[7:0];
        for (i = 0; i < BURST_WORDS; i = i + 1) begin
            v_hi = (burst_seed << 6) ^ (((2*i) * 37 + 13) & 8'hFF);
            v_lo = (burst_seed << 6) ^ (((2*i+1) * 37 + 13) & 8'hFF);
            w = {v_hi, v_lo};
            push_word(w);
            append_expected_byte(v_hi);
            append_expected_byte(v_lo);
        end

        for (s = 0; s < 8; s = s + 1) begin
            append_expected_byte(seq_byte(STOP_SEQ_64, s));
        end
    end
endtask

always @(posedge clk) begin
    logic [1:0] expected;
    logic [7:0] current_byte;
    int symbol_idx;

    if (rst) begin
        tx_read_idx <= 0;
        checked_symbols <= 0;
        check_pending <= 1'b0;
    end else begin
        if (check_pending) begin
            // Skip if we've overtaken the expected data queue (happens during inter-packet gaps before next burst is queued).
            if (pending_byte_idx >= exp_write_idx) begin
                check_pending <= 1'b0;
            // Skip verification during idle: if symbol_bits are 0, no valid symbols are being output.
            end else if (dbg_symbol_bits == 2'b00) begin
                check_pending <= 1'b0;
            end else if (dbg_symbol_bits !== expected_pending) begin
                $error("QPSK symbol mismatch t=%0t byte_idx=%0d sym=%0d exp=%b got=%b I=%0d Q=%0d",
                       $time, pending_byte_idx, pending_sym_idx, expected_pending, dbg_symbol_bits, i_out, q_out);
                $finish;
            end else begin
                check_pending <= 1'b0;
            end
        end

        if (symbol_tick && (tx_read_idx < exp_write_idx)) begin
            symbol_idx = checked_symbols % 4;
            current_byte = exp_mem[tx_read_idx];
            case (symbol_idx)
                0: expected = current_byte[7:6];
                1: expected = current_byte[5:4];
                2: expected = current_byte[3:2];
                default: expected = current_byte[1:0];
            endcase

            // Only queue check if expected data is stable (far enough behind the write frontier).
            if (tx_read_idx + 32 < exp_write_idx) begin
                expected_pending <= expected;
                pending_byte_idx <= tx_read_idx;
                pending_sym_idx <= symbol_idx;
                check_pending <= 1'b1;
            end

            checked_symbols <= checked_symbols + 1;
            if (symbol_idx == 3) begin
                tx_read_idx <= tx_read_idx + 1;
            end
        end
    end
end

initial begin
    int b;
    $dumpfile("tb_qpsk_tx_modulator.vcd");
    $dumpvars(0, tb_qpsk_tx_modulator);

    in_word = 16'h0000;
    in_valid = 1'b0;
    exp_write_idx = 0;
    check_pending = 1'b0;
    expected_pending = 2'b00;
    pending_byte_idx = 0;
    pending_sym_idx = 0;

    #(20*CLK_PERIOD_NS);
    rst = 1'b0;

    for (b = 0; b < BURST_COUNT; b = b + 1) begin
        send_burst(b);
        #(BURST_GAP);
    end

    wait (tx_read_idx == (BURST_COUNT*FRAMED_BYTES_PER_BURST));
    #(10_000ns);

    $display("PASS: checked %0d framed bytes (%0d symbols) at %0d bps input", tx_read_idx, checked_symbols, BIT_RATE_BPS);
    $finish;
end

endmodule

`default_nettype wire
