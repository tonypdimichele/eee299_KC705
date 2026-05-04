/**
 * ADC Statistics Module
 *
 * Computes peak positive/negative, phase, and frequency from IQ ADC
 * data using adaptive-N zero-crossing measurement.
 *
 * All measurements are aligned to positive-going I-channel zero
 * crossings, so peaks and phase always span exact whole cycles.
 *
 * Frequency: accumulates clock cycles over N crossings. N adapts via
 * power-of-2 shifts (no dividers) to keep total_clks in a target
 * range. Host computes freq = sample_rate * N / total_clks.
 *
 * Peaks: running max/min of I channel, latched at N-crossing boundary.
 *
 * Phase: measured as the time delay from each I-channel positive-going
 * zero crossing to the next Q-channel positive-going zero crossing.
 * The 32-bit accumulated delay (in clocks) over N cycles is sent in
 * the packet. Host computes phase = 360 * delay_sum / total_clks.
 * Purely time-domain — no amplitude dependence or sinc correction.
 *
 * Packet format (16 bytes):
 *   [0]    sync byte (0xA7)
 *   [1]    peak_pos[11:4]
 *   [2]    peak_pos[3:0] || peak_neg[11:8]
 *   [3]    peak_neg[7:0]
 *   [4:7]  iq_delay_sum (unsigned 32-bit, clocks from I ZC to Q ZC, summed over N)
 *   [8:9]  total_clk_count (16-bit)
 *   [10:11] n_cycles (16-bit)
 *   [12:15] cordic_phase (signed 32-bit, atan2(sum_Q, sum_I) over N-cycle window)
 */

`timescale 1ns / 1ps
`default_nettype none

module adc_stats #(
    parameter SAMPLE_CLK_HZ        = 125_000_000,
    parameter FREQ_N_INIT           = 4000,
    parameter FREQ_N_MIN            = 32,
    parameter FREQ_N_MAX            = 16384,
    parameter FREQ_CLK_TARGET_HI    = 50000,
    parameter FREQ_CLK_TARGET_LO    = 8000,
    parameter FREQ_ACCUM_ABORT      = 500_000,
    parameter FREQ_MIN_PERIOD_CLKS  = 2,
    parameter EXPERIMENTAL_MODE     = 0,
    parameter FREQ_N_EXPERIMENTAL   = 32
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [11:0] adc1_data_a_d0,   // I channel (cosine)
    input  wire [11:0] adc1_data_b_d0,   // Q channel (sine)

    (* mark_debug = "true" *)
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready
);

    // ---- Constants --------------------------------------------------------
    localparam signed [11:0] ZC_HYST = 12'sd4;

    // ---- Offset-binary <-> signed (MSB flip) ------------------------------
    wire signed [11:0] sample_i = {~adc1_data_a_d0[11], adc1_data_a_d0[10:0]};
    wire signed [11:0] sample_q = {~adc1_data_b_d0[11], adc1_data_b_d0[10:0]};

    function automatic [11:0] to_offset(input signed [11:0] val);
        to_offset = {~val[11], val[10:0]};
    endfunction

    // ---- Output packet ----------------------------------------------------
    localparam [7:0] SYNC_BYTE = 8'hA7;
    reg [7:0] packet_buf [0:15];
    reg [4:0] packet_byte_idx;
    reg       packet_valid;
    reg       measurement_ready;           // pulse: new measurement to pack

    // ---- Adaptive-N zero-crossing frequency measurement (free-running) -------
    reg signed [11:0] prev_sample_i;
    reg [15:0]        zc_period_counter;     // clocks since last crossing
    reg [15:0]        measured_clk_count;    // total clocks over N crossings (latched)
    reg [15:0]        measured_cycles_count; // N used for latest measurement (latched)
    reg [15:0]        freq_n_target;         // current adaptive N
    reg [15:0]        freq_cycle_count;      // crossings counted so far
    reg [31:0]        freq_clk_accum;        // clock accumulator (32-bit internal)
    reg [31:0]        freq_accum_next;       // combinational: accum + current period
    reg               zc_armed;
    //reg [5:0]         N_experimental = 6'd32; // for 299 experiment we want averaging to be done in python
    wire [15:0]        freq_choice = (EXPERIMENTAL_MODE) ? FREQ_N_EXPERIMENTAL : freq_n_target;
    // ---- Peak tracking over N-crossing window --------------------------------
    reg signed [11:0] run_pk_pos;            // running max during current window
    reg signed [11:0] run_pk_neg;            // running min during current window
    reg signed [11:0] latched_pk_pos;        // latched at measurement boundary
    reg signed [11:0] latched_pk_neg;        // latched at measurement boundary

    // ---- Phase: I-to-Q zero-crossing delay measurement -----------------------
    reg signed [11:0] prev_sample_q;         // Q delayed 1 clk for ZC detection
    reg               q_zc_armed;            // armed after Q goes below -ZC_HYST
    reg [15:0]        iq_delay_counter;       // clocks since last I ZC
    reg               iq_delay_captured;      // Q ZC captured for current I cycle?
    reg [31:0]        iq_delay_accum;         // sum of I-to-Q delays over N crossings
    reg [31:0]        latched_iq_delay;       // latched at measurement boundary

    // ---- Costas correlation phase estimator ----------------------------------
    reg        costas_window_done;        // pulse: end window, trigger CORDIC
    reg        costas_window_start;       // pulse: reset accumulators (abort)
    wire signed [31:0] costas_phase_out;
    wire               costas_phase_valid;

    phase_costas #(
        .SAMPLE_W        (12),
        .ACC_W           (40)
    ) u_phase_costas (
        .clk                    (clk),
        .rst                    (rst),
        .sample_i               (sample_i),
        .sample_q               (sample_q),
        .window_start           (costas_window_start),
        .window_done            (costas_window_done),
        .phase_out              (costas_phase_out),
        .phase_valid            (costas_phase_valid)
    );

    // ---- Packet packing intermediates ----------------------------------------
    reg        [11:0] pk_pos_code, pk_neg_code;

    (* dont_touch = "true" *) reg  signed [31:0] latched_cordic_phase;   // latched from Costas estimator

    // =======================================================================
    always @(posedge clk) begin
        if (rst) begin
            packet_valid          <= 1'b0;
            measurement_ready     <= 1'b0;
            m_axis_tvalid         <= 1'b0;
            packet_byte_idx       <= 5'd0;
            prev_sample_i         <= 12'sd0;
            prev_sample_q         <= 12'sd0;
            zc_period_counter     <= 16'd1;
            measured_clk_count    <= 16'd0;
            measured_cycles_count <= FREQ_N_INIT[15:0];
            freq_n_target         <= FREQ_N_INIT[15:0];
            freq_cycle_count      <= 16'd0;
            freq_clk_accum        <= 32'd0;
            freq_accum_next        = 32'd0;
            zc_armed              <= 1'b0;
            run_pk_pos            <= -12'sd2048;
            run_pk_neg            <=  12'sd2047;
            latched_pk_pos        <= 12'sd0;
            latched_pk_neg        <= 12'sd0;
            q_zc_armed            <= 1'b0;
            iq_delay_counter      <= 16'd0;
            iq_delay_captured     <= 1'b1;
            iq_delay_accum        <= 32'd0;
            latched_iq_delay      <= 32'd0;
            costas_window_done    <= 1'b0;
            costas_window_start   <= 1'b0;
            latched_cordic_phase  <= 32'sd0;
        end else begin

            measurement_ready   <= 1'b0;   // default: single-cycle pulse
            costas_window_done  <= 1'b0;
            costas_window_start <= 1'b0;

            // ===== Frequency: count clocks over N crossings (adaptive N) ===
            prev_sample_i <= sample_i;
            prev_sample_q <= sample_q;

            // ---- Peak tracking: update running max/min every cycle ----
            if (sample_i > run_pk_pos) run_pk_pos <= sample_i;
            if (sample_i < run_pk_neg) run_pk_neg <= sample_i;

            // ---- I-to-Q delay counter: always incrementing ----
            if (iq_delay_counter < 16'hFFFF)
                iq_delay_counter <= iq_delay_counter + 1;

            // ---- Q zero-crossing detection (independent of I ZC) ----
            if (sample_q < -ZC_HYST)
                q_zc_armed <= 1'b1;

            if (q_zc_armed && prev_sample_q < ZC_HYST && sample_q >= ZC_HYST) begin
                if (!iq_delay_captured) begin
                    iq_delay_accum    <= iq_delay_accum + {16'd0, iq_delay_counter};
                    iq_delay_captured <= 1'b1;
                end
                q_zc_armed <= 1'b0;
            end

            // ---- I zero-crossing detection ----

            if (sample_i < -ZC_HYST)
                zc_armed <= 1'b1;

            // Positive-going zero-crossing detection with hysteresis
            if (zc_armed && prev_sample_i < ZC_HYST && sample_i >= ZC_HYST) begin
                if (zc_period_counter >= FREQ_MIN_PERIOD_CLKS) begin

                    freq_accum_next = freq_clk_accum + {16'd0, zc_period_counter};

                    if (freq_cycle_count + 1'b1 >= freq_choice) begin
                        // ---- Measurement complete ----
                        if (freq_accum_next <= 32'h0000FFFF) begin
                            measured_clk_count    <= freq_accum_next[15:0];
                        end
                        // Always update N so packet n_cycles matches the CORDIC multiply.
                        measured_cycles_count <= freq_choice;

                        // Latch peaks and delay sum, reset running trackers
                        latched_pk_pos      <= run_pk_pos;
                        latched_pk_neg      <= run_pk_neg;
                        latched_iq_delay    <= iq_delay_accum;
                        iq_delay_accum      <= 32'd0;
                        run_pk_pos       <= -12'sd2048;
                        run_pk_neg       <=  12'sd2047;

                        // Signal Costas correlator: end of window
                        costas_window_done <= 1'b1;

                        // Adapt N
                        if (freq_accum_next > 32'h0000FFFF)
                            freq_n_target <= (freq_n_target >> 2 < FREQ_N_MIN[15:0])
                                             ? FREQ_N_MIN[15:0] : freq_n_target >> 2;
                        else if (freq_accum_next > FREQ_CLK_TARGET_HI)
                            freq_n_target <= (freq_n_target >> 1 < FREQ_N_MIN[15:0])
                                             ? FREQ_N_MIN[15:0] : freq_n_target >> 1;
                        else if (freq_accum_next < FREQ_CLK_TARGET_LO)
                            freq_n_target <= (freq_n_target << 1 > FREQ_N_MAX[15:0])
                                             ? FREQ_N_MAX[15:0] : freq_n_target << 1;
                        freq_cycle_count <= 16'd0;
                        freq_clk_accum   <= 32'd0;

                    end else if (freq_accum_next > FREQ_ACCUM_ABORT) begin
                        // ---- Early abort ----
                        freq_n_target <= (freq_n_target >> 2 < FREQ_N_MIN[15:0])
                                         ? FREQ_N_MIN[15:0] : freq_n_target >> 2;
                        freq_cycle_count <= 16'd0;
                        freq_clk_accum   <= 32'd0;
                        run_pk_pos         <= -12'sd2048;
                        run_pk_neg         <=  12'sd2047;
                        iq_delay_accum     <= 32'd0;
                        costas_window_start <= 1'b1;

                    end else begin
                        freq_cycle_count   <= freq_cycle_count + 1'b1;
                        freq_clk_accum     <= freq_accum_next;
                    end
                    // Reset delay counter and capture flag at every I ZC
                    iq_delay_counter  <= 16'd0;
                    iq_delay_captured <= 1'b0;
                    zc_period_counter <= 16'd1;
                    zc_armed          <= 1'b0;
                end else begin
                    if (zc_period_counter < 16'hFFFF)
                        zc_period_counter <= zc_period_counter + 1;
                end
            end else begin
                if (zc_period_counter < 16'hFFFF)
                    zc_period_counter <= zc_period_counter + 1;
            end

            // Latch Costas phase result when ready
            if (costas_phase_valid) begin
                latched_cordic_phase <= costas_phase_out;
                measurement_ready    <= 1'b1;
            end

            // ===== Pack and emit packet when measurement completes =========
            if (measurement_ready && !packet_valid) begin
                pk_pos_code = to_offset(latched_pk_pos);
                pk_neg_code = to_offset(latched_pk_neg);

                packet_buf[0]  <= SYNC_BYTE;
                packet_buf[1]  <= pk_pos_code[11:4];
                packet_buf[2]  <= {pk_pos_code[3:0], pk_neg_code[11:8]};
                packet_buf[3]  <= pk_neg_code[7:0];
                packet_buf[4]  <= latched_iq_delay[31:24];
                packet_buf[5]  <= latched_iq_delay[23:16];
                packet_buf[6]  <= latched_iq_delay[15:8];
                packet_buf[7]  <= latched_iq_delay[7:0];
                packet_buf[8]  <= measured_clk_count[15:8];
                packet_buf[9]  <= measured_clk_count[7:0];
                packet_buf[10] <= measured_cycles_count[15:8];
                packet_buf[11] <= measured_cycles_count[7:0];
                packet_buf[12] <= latched_cordic_phase[31:24];
                packet_buf[13] <= latched_cordic_phase[23:16];
                packet_buf[14] <= latched_cordic_phase[15:8];
                packet_buf[15] <= latched_cordic_phase[7:0];

                packet_valid    <= 1'b1;
                packet_byte_idx <= 5'd0;
            end

            // ===== Output AXIS bytes =======================================
            if (packet_valid) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata  <= packet_buf[packet_byte_idx];
                if (m_axis_tready) begin
                    if (packet_byte_idx == 5'd15) begin
                        packet_valid    <= 1'b0;
                        packet_byte_idx <= 5'd0;
                    end else begin
                        packet_byte_idx <= packet_byte_idx + 1'd1;
                    end
                end
            end else begin
                m_axis_tvalid <= 1'b0;
            end

        end
    end

endmodule

`default_nettype wire
