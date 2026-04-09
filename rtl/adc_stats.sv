/**
 * ADC Statistics Module
 *
 * Computes peak positive/negative from cosine (I), phase from sine (Q),
 * and frequency via period measurement between zero crossings.
 *
 * Pipeline:
 *   1. Accept sample into sliding window (non-blocking)
 *   2. When window full: scan peaks, compute phase, pack + output via AXIS
 *   3. Shift window for overlap
 *
 * Frequency is measured independently by counting samples between
 * consecutive positive-going zero crossings (hysteretic).  The raw
 * period count is sent in bytes [6:7] after a sync byte [0]; Python decodes as
 *   freq_mhz = sample_rate_msps / period_count.
 */

`timescale 1ns / 1ps
`default_nettype none

module adc_stats #(
    parameter WINDOW_SIZE     = 64,
    parameter OVERLAP_PERCENT = 80
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

    // ---- Derived constants ------------------------------------------------
    localparam IDX_W = $clog2(WINDOW_SIZE + 1);   // index width
    localparam [IDX_W-1:0] NEW_SAMPLES  = (WINDOW_SIZE * (100 - OVERLAP_PERCENT)) / 100;
    localparam [IDX_W-1:0] KEEP_SAMPLES = WINDOW_SIZE[IDX_W-1:0] - NEW_SAMPLES;
    localparam signed [11:0] ZC_HYST    = 12'sd16;

    // ---- Offset-binary <-> signed (MSB flip) ------------------------------
    wire signed [11:0] sample_i = {~adc1_data_a_d0[11], adc1_data_a_d0[10:0]};
    wire signed [11:0] sample_q = {~adc1_data_b_d0[11], adc1_data_b_d0[10:0]};

    function automatic [11:0] to_offset(input signed [11:0] val);
        to_offset = {~val[11], val[10:0]};
    endfunction

    // ---- Phase helper (simple atan2 approximation) ------------------------
    function automatic [15:0] atan2_approx(
        input signed [11:0] q_val,
        input signed [11:0] i_val
    );
        reg [15:0] result;
        begin
            if (i_val == 0 && q_val == 0)
                result = 16'd0;
            else if (i_val > 0)
                result = ((q_val << 13) / (i_val + 1));
            else if (q_val > 0)
                result = 16'd32768 - ((((-i_val) << 13) / (q_val + 1)));
            else
                result = 16'd32768 + ((((-q_val) << 13) / ((-i_val) + 1)));
            atan2_approx = result;
        end
    endfunction

    // ---- Window storage ---------------------------------------------------
    reg signed [11:0] window_i [0:WINDOW_SIZE-1];
    reg signed [11:0] window_q [0:WINDOW_SIZE-1];
    reg [IDX_W-1:0]   window_idx;
    reg [IDX_W-1:0]   sample_count;

    // ---- Output packet ----------------------------------------------------
    localparam [7:0] SYNC_BYTE = 8'hA7;
    reg [7:0] packet_buf [0:7];
    reg [3:0] packet_byte_idx;
    reg       packet_valid;

    // ---- Period-based frequency measurement (free-running) ----------------
    reg signed [11:0] prev_sample_i;
    reg [15:0]        zc_period_counter;
    reg [15:0]        measured_period;    // latched on each + crossing
    reg               zc_armed;

    // ---- Stage-2 computation intermediates (module scope for Vivado) ------
    reg signed [11:0] pk_pos, pk_neg;
    reg        [11:0] pk_pos_code, pk_neg_code;
    reg        [15:0] phase_val;
    reg signed [11:0] dq_q;
    integer k;

    // =======================================================================
    always @(posedge clk) begin
        if (rst) begin
            window_idx        <= {IDX_W{1'b0}};
            sample_count      <= {IDX_W{1'b0}};
            packet_valid      <= 1'b0;
            m_axis_tvalid     <= 1'b0;
            packet_byte_idx   <= 3'd0;
            prev_sample_i     <= 12'sd0;
            zc_period_counter <= 16'd0;
            measured_period   <= 16'hFFFF;
            zc_armed          <= 1'b0;
        end else begin

            // ===== Frequency: period between positive-going zero crossings =
            prev_sample_i <= sample_i;

            if (sample_i < -ZC_HYST)
                zc_armed <= 1'b1;

            if (zc_armed && prev_sample_i < ZC_HYST && sample_i >= ZC_HYST) begin
                measured_period   <= zc_period_counter;
                zc_period_counter <= 16'd1;
                zc_armed          <= 1'b0;
            end else begin
                if (zc_period_counter < 16'hFFFF)
                    zc_period_counter <= zc_period_counter + 1;
            end

            // ===== STAGE 1: Accept sample into window ======================
            if (window_idx < WINDOW_SIZE[IDX_W-1:0]) begin
                window_i[window_idx] <= sample_i;
                window_q[window_idx] <= sample_q;
                window_idx   <= window_idx + 1'd1;
                sample_count <= sample_count + 1'd1;
            end

            // ===== STAGE 2: Compute stats when window full =================
            if (window_idx == WINDOW_SIZE[IDX_W-1:0]
                && sample_count >= NEW_SAMPLES
                && !packet_valid) begin

                // Peak detection over full window (cosine / I channel)
                pk_pos = window_i[0];
                pk_neg = window_i[0];
                for (k = 0; k < WINDOW_SIZE; k = k + 1) begin
                    if (window_i[k] > pk_pos) pk_pos = window_i[k];
                    if (window_i[k] < pk_neg) pk_neg = window_i[k];
                end

                // Phase from sine channel
                dq_q      = window_q[WINDOW_SIZE-1] - window_q[WINDOW_SIZE-2];
                phase_val = atan2_approx(window_q[WINDOW_SIZE-1], dq_q);

                pk_pos_code = to_offset(pk_pos);
                pk_neg_code = to_offset(pk_neg);

                // Pack 8 bytes: sync(1) + peaks(3) + phase(2) + period(2)
                packet_buf[0] <= SYNC_BYTE;
                packet_buf[1] <= pk_pos_code[11:4];
                packet_buf[2] <= {pk_pos_code[3:0], pk_neg_code[11:8]};
                packet_buf[3] <= pk_neg_code[7:0];
                packet_buf[4] <= phase_val[15:8];
                packet_buf[5] <= phase_val[7:0];
                packet_buf[6] <= measured_period[15:8];
                packet_buf[7] <= measured_period[7:0];

                packet_valid    <= 1'b1;
                packet_byte_idx <= 3'd0;

                // Overlap shift: keep newest KEEP_SAMPLES at the front
                for (k = 0; k < KEEP_SAMPLES; k = k + 1) begin
                    window_i[k] <= window_i[k + NEW_SAMPLES];
                    window_q[k] <= window_q[k + NEW_SAMPLES];
                end
                window_idx   <= KEEP_SAMPLES;
                sample_count <= {IDX_W{1'b0}};
            end

            // ===== STAGE 3: Output AXIS bytes ==============================
            if (packet_valid) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata  <= packet_buf[packet_byte_idx];
                if (m_axis_tready) begin
                    if (packet_byte_idx == 4'd7) begin
                        packet_valid    <= 1'b0;
                        packet_byte_idx <= 4'd0;
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
