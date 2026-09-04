`timescale 1ns / 1ps
`default_nettype none
//
// qpsk_rx_demod.sv — QPSK Packet RX Demodulator
//
// Receives baseband I/Q samples from the ADC (after HPF), detects the
// preamble via correlation, aligns symbol timing, demodulates QPSK data
// symbols, and outputs 32 bytes per frame on an AXI-Stream interface.
//
// Architecture:
//   1. Sliding correlator matched to the 8-symbol frame-sync portion of preamble
//   2. Correlation peak → marks symbol boundary (timing reference)
//   3. Integrate-and-dump over SAMPLES_PER_SYMBOL for each subsequent symbol
//   4. Hard decision: sign(I_accum) → I_bit, sign(Q_accum) → Q_bit
//   5. Phase ambiguity resolved using the 4 phase-reference symbols
//   6. 128 data symbols → 32 bytes → AXI-Stream output
//
module qpsk_rx_demod #(
    parameter int SAMPLES_PER_SYMBOL = 24,      // ADC samples per QPSK symbol (~125 MHz / 5.2 Msym/s)
    parameter int PAYLOAD_BYTES      = 32,      // Expected data bytes per frame
    parameter int PREAMBLE_LEN       = 20,      // Total preamble symbols
    parameter int POSTAMBLE_LEN      = 20,      // Total postamble symbols
    parameter int CORR_THRESHOLD     = 300000    // Correlation magnitude threshold (scales with SAMPLES_PER_SYMBOL)
) (
    input  wire        i_clk,          // ADC clock (~125 MHz)
    input  wire        i_rst,

    // Baseband I/Q from ADC (signed, after HPF)
    input  wire signed [11:0] i_sample_i,
    input  wire signed [11:0] i_sample_q,
    input  wire               i_sample_valid,

    // Runtime-configurable correlation threshold (overrides parameter if non-zero)
    input  wire [23:0]        i_corr_threshold,

    // AXI-Stream output: demodulated payload bytes
    output logic [7:0]  o_m_axis_tdata,
    output logic        o_m_axis_tvalid,
    input  wire         i_m_axis_tready,
    output logic        o_m_axis_tlast,

    // Status
    output logic        o_frame_detected,   // pulses when preamble found
    output logic        o_frame_done,       // pulses when full frame demodulated
    (*mark_debug = "true"*)
    output logic [1:0]  o_phase_rot,        // detected phase rotation (0,1,2,3 × 90°)
    output wire  [23:0] o_corr_mag          // live correlator magnitude (for debug/ILA)
);

// ──────────────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────────────
localparam int DATA_SYMBOLS   = PAYLOAD_BYTES * 4;
localparam int TOTAL_SYMBOLS  = PREAMBLE_LEN + DATA_SYMBOLS + POSTAMBLE_LEN;
// We correlate against the 8-symbol frame-sync portion (preamble[8:15])
localparam int SYNC_LEN       = 8;
// After sync detection, skip remaining preamble symbols before data
localparam int SKIP_AFTER_SYNC = 4;  // phase-ref symbols (preamble[16:19])

// ──────────────────────────────────────────────────────────────────────
// Preamble sync ROM — same as TX (must match qpsk_tx_framer)
// Full preamble for reference:
//   [0:7]   Timing: 00,11,00,11,00,11,00,11
//   [8:15]  Sync:   00,10,11,01,10,00,01,11
//   [16:19] Phase:  00,10,11,01
// ──────────────────────────────────────────────────────────────────────
// Sync correlator reference: symbols [8:15]
// Each symbol maps to I_ref, Q_ref ∈ {+1, -1}
// bit[1]=0 → I=+1, bit[1]=1 → I=-1
// bit[0]=0 → Q=+1, bit[0]=1 → Q=-1
localparam logic signed [1:0] SYNC_I_REF [0:SYNC_LEN-1] = '{
     1,  // 00: I=+1
    -1,  // 10: I=-1
    -1,  // 11: I=-1
     1,  // 01: I=+1
    -1,  // 10: I=-1
     1,  // 00: I=+1
     1,  // 01: I=+1
    -1   // 11: I=-1
};

localparam logic signed [1:0] SYNC_Q_REF [0:SYNC_LEN-1] = '{
     1,  // 00: Q=+1
     1,  // 10: Q=+1
    -1,  // 11: Q=-1
    -1,  // 01: Q=-1
     1,  // 10: Q=+1
     1,  // 00: Q=+1
    -1,  // 01: Q=-1
    -1   // 11: Q=-1
};

// Phase reference symbols [16:19]: 00, 10, 11, 01
// Expected I,Q signs after correct demod (no rotation):
//   00 → I=+1, Q=+1
//   10 → I=-1, Q=+1
//   11 → I=-1, Q=-1
//   01 → I=+1, Q=-1
localparam logic [1:0] PHASE_REF [0:3] = '{2'b00, 2'b10, 2'b11, 2'b01};

// ──────────────────────────────────────────────────────────────────────
// Sliding window integrator (integrate over SAMPLES_PER_SYMBOL)
// ──────────────────────────────────────────────────────────────────────
(*mark_debug = "true"*)
logic signed [17:0] i_accum;
(*mark_debug = "true"*)
logic signed [17:0] q_accum;
(*mark_debug = "true"*)
logic [$clog2(SAMPLES_PER_SYMBOL)-1:0] samp_cnt;
logic               symbol_strobe;  // one pulse per symbol boundary

// ──────────────────────────────────────────────────────────────────────
// Correlator shift register (SYNC_LEN symbols deep)
// ──────────────────────────────────────────────────────────────────────
logic signed [17:0] i_sym_sr [0:SYNC_LEN-1];
logic signed [17:0] q_sym_sr [0:SYNC_LEN-1];
logic               sr_valid;

// Correlation result (registered by pipeline)
(*mark_debug = "true"*)
logic        [23:0] corr_mag;  // |corr_i| + |corr_q| (Manhattan magnitude)

// ──────────────────────────────────────────────────────────────────────
// State machine
// ──────────────────────────────────────────────────────────────────────
typedef enum logic [2:0] {
    S_TIMING_ACQ,   // Acquiring sample-phase from the alternating timing preamble
    S_SEARCH,       // Looking for preamble
    S_PHASE_REF,    // Demodulating phase reference symbols
    S_DATA,         // Demodulating data symbols
    S_OUTPUT,       // Outputting bytes via AXI-Stream
    S_WAIT          // Inter-frame cooldown
} state_t;
(*mark_debug = "true"*)
state_t state;
logic [$clog2(TOTAL_SYMBOLS)-1:0] sym_cnt;
logic [$clog2(PAYLOAD_BYTES)-1:0] byte_cnt;
logic [7:0] byte_sr;  // shift register for assembling bytes
logic [1:0] bit_pair_cnt;  // counts symbol pairs within a byte (0-3)

// Phase rotation storage
logic [1:0] phase_rotation;  // 0=0°, 1=90°, 2=180°, 3=270°

// Demodulated symbol before rotation correction
(*mark_debug = "true"*)
logic i_hard;
(*mark_debug = "true"*)
logic q_hard;
// After rotation correction
(*mark_debug = "true"*)
logic i_corrected;
(*mark_debug = "true"*)
logic q_corrected;

// Output buffer
logic [7:0] out_buf [0:PAYLOAD_BYTES-1];
logic [$clog2(PAYLOAD_BYTES)-1:0] out_ptr;
logic output_pending;

// Timing re-sync: state machine asserts this to realign integrator on frame detect
logic sync_reset_timing;

// ──────────────────────────────────────────────────────────────────────
// Bit-timing recovery (early-late gate): the free-running integrator has no
// inherent phase relationship to the incoming symbol grid, so the sliding
// correlator alone only reliably locks if that phase happens to line up
// (worked for one payload in testing, silently mis-locked for others). The
// first 8 preamble symbols alternate every SAMPLES_PER_SYMBOL samples
// specifically so the receiver can find the true symbol boundary here,
// before the sync correlator ever engages.
// ──────────────────────────────────────────────────────────────────────
localparam int TIMING_LOCK_CONFIDENCE = 3;  // consecutive correctly-spaced transitions required

logic signed [11:0] timing_prev_sample;
logic                timing_prev_valid;
logic [$clog2(SAMPLES_PER_SYMBOL*2)-1:0] since_transition;
logic [1:0]           timing_confidence;
logic                 timing_lock_pulse;

always_ff @(posedge i_clk) begin
    logic transition;
    timing_lock_pulse <= 1'b0;
    if (i_rst) begin
        timing_prev_sample <= '0;
        timing_prev_valid  <= 1'b0;
        since_transition   <= '0;
        timing_confidence  <= '0;
    end else if (state != S_TIMING_ACQ) begin
        // Reset whenever not actively acquiring, so each new frame starts fresh.
        timing_prev_valid <= 1'b0;
        since_transition  <= '0;
        timing_confidence <= '0;
    end else if (i_sample_valid) begin
        transition = timing_prev_valid && (i_sample_i[11] != timing_prev_sample[11]);
        timing_prev_sample <= i_sample_i;
        timing_prev_valid  <= 1'b1;
        if (transition) begin
            // Alternating pattern -> transitions should land exactly every
            // SAMPLES_PER_SYMBOL samples; allow +/-1 sample of tolerance.
            if (since_transition >= (SAMPLES_PER_SYMBOL - 1) && since_transition <= (SAMPLES_PER_SYMBOL + 1)) begin
                if (timing_confidence == TIMING_LOCK_CONFIDENCE - 1) begin
                    timing_lock_pulse <= 1'b1;  // this sample = a true symbol boundary
                    timing_confidence <= '0;
                end else begin
                    timing_confidence <= timing_confidence + 1'b1;
                end
            end else begin
                timing_confidence <= '0;
            end
            since_transition <= '0;
        end else begin
            since_transition <= since_transition + 1'b1;
        end
    end
end

// ──────────────────────────────────────────────────────────────────────
// Phase reference accumulator
// ──────────────────────────────────────────────────────────────────────
logic [1:0] phase_ref_syms [0:3];
(*mark_debug = "true"*)
logic [1:0] phase_ref_cnt;

// ──────────────────────────────────────────────────────────────────────
// Integrate-and-dump + symbol strobe generation
// ──────────────────────────────────────────────────────────────────────
always_ff @(posedge i_clk) begin
    if (i_rst) begin
        i_accum      <= '0;
        q_accum      <= '0;
        samp_cnt     <= '0;
        symbol_strobe <= 1'b0;
    end else if (sync_reset_timing) begin
        // Re-align integrator to symbol boundary on frame detection.
        // Correlator pipeline adds ~3 cycles from the true boundary to detection,
        // placing us ~3-4 samples into the next symbol. Since this reset has priority
        // over sample integration, the current arriving sample is discarded; account
        // for this by seeding samp_cnt to 4 (one past the normally-seen sample).
        samp_cnt      <= 'd4;
        i_accum       <= '0;
        q_accum       <= '0;
        symbol_strobe <= 1'b0;
    end else if (timing_lock_pulse) begin
        // Bit-timing recovery found the true boundary: this sample is symbol 0.
        samp_cnt      <= '0;
        i_accum       <= i_sample_i;
        q_accum       <= i_sample_q;
        symbol_strobe <= 1'b0;
    end else if (i_sample_valid) begin
        symbol_strobe <= 1'b0;
        if (samp_cnt == SAMPLES_PER_SYMBOL - 1) begin
            samp_cnt      <= '0;
            symbol_strobe <= 1'b1;
            // Accumulator holds the final sum; will be captured by state machine
            i_accum       <= i_sample_i;  // start fresh accumulation
            q_accum       <= i_sample_q;
        end else begin
            samp_cnt <= samp_cnt + 1;
            if (samp_cnt == 0) begin
                i_accum <= i_sample_i;
                q_accum <= i_sample_q;
            end else begin
                i_accum <= i_accum + i_sample_i;
                q_accum <= q_accum + i_sample_q;
            end
        end
    end else begin
        symbol_strobe <= 1'b0;
    end
end

// Latched symbol-rate I/Q (captured at symbol_strobe)
(*mark_debug = "true"*)
logic signed [17:0] sym_i_latched;
(*mark_debug = "true"*)
logic signed [17:0] sym_q_latched;

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        sym_i_latched <= '0;
        sym_q_latched <= '0;
    end else if (i_sample_valid && samp_cnt == SAMPLES_PER_SYMBOL - 1) begin
        // Latch the completed accumulator value
        sym_i_latched <= i_accum + i_sample_i;
        sym_q_latched <= q_accum + i_sample_q;
    end
end

// ──────────────────────────────────────────────────────────────────────
// Correlator shift register
// ──────────────────────────────────────────────────────────────────────
always_ff @(posedge i_clk) begin
    if (i_rst) begin
        for (int k = 0; k < SYNC_LEN; k++) begin
            i_sym_sr[k] <= '0;
            q_sym_sr[k] <= '0;
        end
        sr_valid <= 1'b0;
    end else if (symbol_strobe) begin
        // Shift in new symbol
        i_sym_sr[0] <= sym_i_latched;
        q_sym_sr[0] <= sym_q_latched;
        for (int k = 1; k < SYNC_LEN; k++) begin
            i_sym_sr[k] <= i_sym_sr[k-1];
            q_sym_sr[k] <= q_sym_sr[k-1];
        end
        sr_valid <= 1'b1;
    end else begin
        sr_valid <= 1'b0;
    end
end

// ──────────────────────────────────────────────────────────────────────
// Pipelined correlation computation (2 stages, triggered by sr_valid)
// Complex correlation: C = sum (received * conj(reference))
//   corr_i = sum (I_rx * I_ref + Q_rx * Q_ref)
//   corr_q = sum (Q_rx * I_ref - I_rx * Q_ref)
// Note: shift register is newest-first (sr[0]=newest, sr[N-1]=oldest)
// Reference arrays are in transmit order (index 0 = first transmitted = oldest)
// So we correlate SYNC_REF[k] against sr[SYNC_LEN-1-k]
// ──────────────────────────────────────────────────────────────────────

// Stage 1: Compute correlation sums (registered)
logic signed [23:0] corr_i_reg, corr_q_reg;
logic               corr_pipe1_valid;

// Intermediate wires for sign-flipped terms (synthesis will optimize)
logic signed [23:0] ci_term [0:SYNC_LEN-1];
logic signed [23:0] cq_term [0:SYNC_LEN-1];

always_comb begin
    for (int k = 0; k < SYNC_LEN; k++) begin
        ci_term[k] = (SYNC_I_REF[k] == 1 ?  24'(signed'(i_sym_sr[SYNC_LEN-1-k])) : -24'(signed'(i_sym_sr[SYNC_LEN-1-k])))
                   + (SYNC_Q_REF[k] == 1 ?  24'(signed'(q_sym_sr[SYNC_LEN-1-k])) : -24'(signed'(q_sym_sr[SYNC_LEN-1-k])));
        cq_term[k] = (SYNC_I_REF[k] == 1 ?  24'(signed'(q_sym_sr[SYNC_LEN-1-k])) : -24'(signed'(q_sym_sr[SYNC_LEN-1-k])))
                   - (SYNC_Q_REF[k] == 1 ?  24'(signed'(i_sym_sr[SYNC_LEN-1-k])) : -24'(signed'(i_sym_sr[SYNC_LEN-1-k])));
    end
end

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        corr_i_reg      <= '0;
        corr_q_reg      <= '0;
        corr_pipe1_valid <= 1'b0;
    end else begin
        corr_pipe1_valid <= sr_valid;
        if (sr_valid) begin
            corr_i_reg <= ci_term[0] + ci_term[1] + ci_term[2] + ci_term[3]
                        + ci_term[4] + ci_term[5] + ci_term[6] + ci_term[7];
            corr_q_reg <= cq_term[0] + cq_term[1] + cq_term[2] + cq_term[3]
                        + cq_term[4] + cq_term[5] + cq_term[6] + cq_term[7];
        end
    end
end

// Stage 2: Magnitude computation (registered)
logic               corr_pipe2_valid;
wire [23:0] abs_corr_i = corr_i_reg[23] ? -corr_i_reg : corr_i_reg;
wire [23:0] abs_corr_q = corr_q_reg[23] ? -corr_q_reg : corr_q_reg;

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        corr_mag         <= '0;
        corr_pipe2_valid <= 1'b0;
    end else begin
        corr_pipe2_valid <= corr_pipe1_valid;
        if (corr_pipe1_valid) begin
            corr_mag <= abs_corr_i + abs_corr_q;
        end
    end
end

assign o_corr_mag = corr_mag;

// ──────────────────────────────────────────────────────────────────────
// Hard decision & phase rotation
// ──────────────────────────────────────────────────────────────────────
assign i_hard = sym_i_latched[17];   // sign bit = data bit (0=positive=+amp, 1=negative=-amp)
assign q_hard = sym_q_latched[17];

// Apply inverse rotation to correct phase ambiguity
// Channel rotations and their effect on received {i_hard, q_hard}:
//   rot=0 (no rot):     i_hard=i_bit, q_hard=q_bit         -> no correction
//   rot=1 (I'=Q,-I):    i_hard=q_bit, q_hard=~i_bit        -> i_corr=~q_hard, q_corr=i_hard
//   rot=2 (I'=-I,-Q):   i_hard=~i_bit, q_hard=~q_bit       -> i_corr=~i_hard, q_corr=~q_hard
//   rot=3 (I'=-Q,I):    i_hard=~q_bit, q_hard=i_bit        -> i_corr=q_hard, q_corr=~i_hard
always_comb begin
    case (phase_rotation)
        2'd0: begin i_corrected = i_hard;   q_corrected = q_hard;   end
        2'd1: begin i_corrected = ~q_hard;  q_corrected = i_hard;   end
        2'd2: begin i_corrected = ~i_hard;  q_corrected = ~q_hard;  end
        2'd3: begin i_corrected = q_hard;   q_corrected = ~i_hard;  end
    endcase
end

// ──────────────────────────────────────────────────────────────────────
// Phase rotation detection from reference symbols
// Compare received 4-symbol pattern to expected pattern at each rotation
// ──────────────────────────────────────────────────────────────────────
function automatic logic [1:0] detect_rotation(input logic [1:0] syms [0:3]);
    // Phase ref symbols TX'd as: 00, 10, 11, 01
    // After channel rotation, received {i_hard, q_hard} patterns:
    //   rot=0 (no rot):   00, 10, 11, 01
    //   rot=1 (I'=Q,-I):  01, 00, 10, 11
    //   rot=2 (I'=-I,-Q): 11, 01, 00, 10
    //   rot=3 (I'=-Q,I):  10, 11, 01, 00
    if (syms[0]==2'b00 && syms[1]==2'b10 && syms[2]==2'b11 && syms[3]==2'b01) return 2'd0;
    if (syms[0]==2'b01 && syms[1]==2'b00 && syms[2]==2'b10 && syms[3]==2'b11) return 2'd1;
    if (syms[0]==2'b11 && syms[1]==2'b01 && syms[2]==2'b00 && syms[3]==2'b10) return 2'd2;
    if (syms[0]==2'b10 && syms[1]==2'b11 && syms[2]==2'b01 && syms[3]==2'b00) return 2'd3;
    return 2'd0;  // default: no rotation (best effort)
endfunction

// ──────────────────────────────────────────────────────────────────────
// Main state machine
// ──────────────────────────────────────────────────────────────────────
always_ff @(posedge i_clk) begin
    if (i_rst) begin
        state           <= S_TIMING_ACQ;
        sym_cnt         <= '0;
        byte_cnt        <= '0;
        byte_sr         <= '0;
        bit_pair_cnt    <= '0;
        phase_rotation  <= '0;
        phase_ref_cnt   <= '0;
        out_ptr         <= '0;
        output_pending  <= 1'b0;
        o_frame_detected <= 1'b0;
        o_frame_done    <= 1'b0;
        o_phase_rot     <= '0;
        o_m_axis_tdata  <= '0;
        o_m_axis_tvalid <= 1'b0;
        o_m_axis_tlast  <= 1'b0;
        sync_reset_timing <= 1'b0;
    end else begin
        o_frame_detected <= 1'b0;
        sync_reset_timing <= 1'b0;
        o_frame_done     <= 1'b0;

        case (state)
        // ─────────────────────────────────────────────
        S_TIMING_ACQ: begin
            if (timing_lock_pulse) begin
                state <= S_SEARCH;
            end
        end
        // ──────────────────────────────────────────────────
        S_SEARCH: begin
            // Wait for pipelined correlator magnitude to exceed threshold
            if (corr_pipe2_valid && corr_mag > i_corr_threshold) begin
                o_frame_detected  <= 1'b1;
                sync_reset_timing <= 1'b1;  // re-align integrator to symbol boundary
                state             <= S_PHASE_REF;
                phase_ref_cnt     <= '0;
                sym_cnt           <= '0;
                // Reset integrator alignment: the correlation peak tells us
                // we're at the boundary of the sync section, so next symbol
                // boundary is SAMPLES_PER_SYMBOL clocks away
            end
        end

        // ──────────────────────────────────────────────────
        S_PHASE_REF: begin
            // Demodulate the 4 phase-reference symbols
            if (symbol_strobe) begin
                phase_ref_syms[phase_ref_cnt] <= {i_hard, q_hard};
                if (phase_ref_cnt == 2'd3) begin
                    // All 4 phase ref symbols received - use live value for [3]
                    // (non-blocking write to phase_ref_syms[3] not visible yet)
                    phase_rotation <= detect_rotation(
                        '{phase_ref_syms[0], phase_ref_syms[1], phase_ref_syms[2], {i_hard, q_hard}});
                    o_phase_rot    <= detect_rotation(
                        '{phase_ref_syms[0], phase_ref_syms[1], phase_ref_syms[2], {i_hard, q_hard}});
                    state          <= S_DATA;
                    sym_cnt        <= '0;
                    byte_sr        <= '0;
                    bit_pair_cnt   <= '0;
                    byte_cnt       <= '0;
                end else begin
                    phase_ref_cnt <= phase_ref_cnt + 1;
                end
            end
        end

        // ──────────────────────────────────────────────────
        S_DATA: begin
            if (symbol_strobe) begin
                // Shift corrected bits into byte shift register
                byte_sr <= {byte_sr[5:0], i_corrected, q_corrected};
                bit_pair_cnt <= bit_pair_cnt + 1;

                if (bit_pair_cnt == 2'd3) begin
                    // Full byte assembled
                    out_buf[byte_cnt] <= {byte_sr[5:0], i_corrected, q_corrected};
                    bit_pair_cnt <= '0;
                    if (byte_cnt == PAYLOAD_BYTES - 1) begin
                        // All data received
                        state <= S_OUTPUT;
                        out_ptr <= '0;
                        output_pending <= 1'b1;
                        o_frame_done <= 1'b1;
                    end else begin
                        byte_cnt <= byte_cnt + 1;
                    end
                end
                sym_cnt <= sym_cnt + 1;
            end
        end

        // ──────────────────────────────────────────────────
        S_OUTPUT: begin
            if (output_pending) begin
                o_m_axis_tdata  <= out_buf[out_ptr];
                o_m_axis_tvalid <= 1'b1;
                o_m_axis_tlast  <= (out_ptr == PAYLOAD_BYTES - 1);
                if (i_m_axis_tready) begin
                    if (out_ptr == PAYLOAD_BYTES - 1) begin
                        output_pending  <= 1'b0;
                        state           <= S_WAIT;
                        sym_cnt         <= '0;
                    end else begin
                        out_ptr <= out_ptr + 1;
                    end
                end
            end else begin
                o_m_axis_tvalid <= 1'b0;
                o_m_axis_tlast  <= 1'b0;
            end
        end

        // ──────────────────────────────────────────────────
        S_WAIT: begin
            // Brief cooldown to avoid re-triggering on postamble
            o_m_axis_tvalid <= 1'b0;
            if (symbol_strobe) begin
                if (sym_cnt >= POSTAMBLE_LEN) begin
                    state <= S_TIMING_ACQ;
                end else begin
                    sym_cnt <= sym_cnt + 1;
                end
            end
        end

        default: state <= S_TIMING_ACQ;
        endcase
    end
end

endmodule

`default_nettype wire
