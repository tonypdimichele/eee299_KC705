`timescale 1ns / 1ps
`default_nettype none

module tb_adc_stats;

    localparam real CLK_HALF_NS          = 4.0;  // 125 MHz
    localparam real SAMPLE_HZ            = 125_000_000.0;
    localparam real PI                   = 3.14159265358979323846;
    localparam int  AMP_CODES            = 500;
    localparam int  FRAMES_PER_CASE      = 3;
    `define TB_USE_XILINX_CORDIC;
    // To use the real Xilinx cordic_0 model, compile with: +define+TB_USE_XILINX_CORDIC

    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [11:0] adc1_data_a_d0 = 12'h800;
    logic [11:0] adc1_data_b_d0 = 12'h800;

    wire [7:0] m_axis_tdata;
    wire       m_axis_tvalid;
    logic      m_axis_tready = 1'b1;

    real tone_freq_hz;
    real tone_phase_deg;
    bit  tone_enable;

    longint unsigned sample_idx;

    logic [7:0] pkt [0:15];
    int pkt_idx;

    int case_frame_counter;
    real case_sum_phase_zc;
    real case_sum_phase_cordic;
    string case_name;

    event got_case_frame;

    always #(CLK_HALF_NS) clk = ~clk;

    // DUT: fixed N for fast deterministic simulation.
    adc_stats #(
        .FREQ_N_INIT(2000),
        .FREQ_N_MIN(2000),
        .FREQ_N_MAX(2000),
        .EXPERIMENTAL_MODE(0),
        .FREQ_N_EXPERIMENTAL(2000)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .adc1_data_a_d0(adc1_data_a_d0),
        .adc1_data_b_d0(adc1_data_b_d0),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready)
    );

    function automatic signed [11:0] clamp_s12(input integer val);
        integer tmp;
        begin
            tmp = val;
            if (tmp > 2047)
                tmp = 2047;
            else if (tmp < -2048)
                tmp = -2048;
            clamp_s12 = tmp[11:0];
        end
    endfunction

    function automatic [11:0] signed_to_offset12(input signed [11:0] sval);
        begin
            signed_to_offset12 = {~sval[11], sval[10:0]};
        end
    endfunction

    function automatic int unsigned be16(input logic [7:0] b0, input logic [7:0] b1);
        begin
            be16 = {b0, b1};
        end
    endfunction

    function automatic int unsigned be32u(
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3
    );
        begin
            be32u = {b0, b1, b2, b3};
        end
    endfunction

    function automatic int signed be32s(
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3
    );
        logic [31:0] raw;
        begin
            raw = {b0, b1, b2, b3};
            be32s = $signed(raw);
        end
    endfunction

    task automatic apply_reset;
        begin
            tone_enable      = 1'b0;
            adc1_data_a_d0   = 12'h800;
            adc1_data_b_d0   = 12'h800;
            rst              = 1'b1;
            repeat (12) @(posedge clk);
            rst = 1'b0;
            repeat (6) @(posedge clk);
            tone_enable = 1'b1;
        end
    endtask

    task automatic process_frame;
        int unsigned iq_delay_sum;
        int unsigned total_clk_count;
        int unsigned n_cycles;
        int signed   cordic_phase_sum;
        real         phase_zc_deg;
        real         phase_zc_wrapped_deg;
        real         phase_cordic_deg;
        real         phase_cordic_wrapped_deg;
        begin
            if (pkt[0] !== 8'hA7) begin
                $display("[%0t] ERROR: bad sync byte 0x%02x", $time, pkt[0]);
                return;
            end

            iq_delay_sum     = be32u(pkt[4],  pkt[5],  pkt[6],  pkt[7]);
            total_clk_count  = be16 (pkt[8],  pkt[9]);
            n_cycles         = be16 (pkt[10], pkt[11]);
            cordic_phase_sum = be32s(pkt[12], pkt[13], pkt[14], pkt[15]);

            if (total_clk_count > 0)
                phase_zc_deg = 360.0 * $itor(iq_delay_sum) / $itor(total_clk_count);
            else
                phase_zc_deg = 0.0;

            phase_zc_wrapped_deg = phase_zc_deg;
            while (phase_zc_wrapped_deg >= 180.0)
                phase_zc_wrapped_deg = phase_zc_wrapped_deg - 360.0;
            while (phase_zc_wrapped_deg < -180.0)
                phase_zc_wrapped_deg = phase_zc_wrapped_deg + 360.0;

            phase_cordic_deg = $itor(cordic_phase_sum) * 180.0 / 32768.0;

            phase_cordic_wrapped_deg = phase_cordic_deg;
            while (phase_cordic_wrapped_deg >= 180.0)
                phase_cordic_wrapped_deg = phase_cordic_wrapped_deg - 360.0;
            while (phase_cordic_wrapped_deg < -180.0)
                phase_cordic_wrapped_deg = phase_cordic_wrapped_deg + 360.0;

            case_frame_counter   = case_frame_counter + 1;
            case_sum_phase_zc    = case_sum_phase_zc + phase_zc_deg;
            case_sum_phase_cordic = case_sum_phase_cordic + phase_cordic_deg;

            $display(
                "[%0t] %s frame=%0d  N=%0d clk_sum=%0d  phase_zc=%0.3f deg (%0.3f wrapped)  phase_cordic=%0.3f deg (%0.3f wrapped)",
                $time, case_name, case_frame_counter, n_cycles, total_clk_count,
                phase_zc_deg, phase_zc_wrapped_deg, phase_cordic_deg, phase_cordic_wrapped_deg
            );

            ->got_case_frame;
        end
    endtask

    task automatic run_case(input real freq_mhz, input real angle_deg);
        real avg_zc;
        real avg_cordic;
        real avg_zc_wrapped;
        real avg_cordic_wrapped;
        real expected_cordic_phase_deg;
        begin
            case_name = $sformatf("f=%0.1fMHz, q_lag=%0.1fdeg", freq_mhz, angle_deg);
            tone_freq_hz   = freq_mhz * 1.0e6;
            tone_phase_deg = angle_deg;

            case_frame_counter    = 0;
            case_sum_phase_zc     = 0.0;
            case_sum_phase_cordic = 0.0;

            apply_reset();

            while (case_frame_counter < FRAMES_PER_CASE)
                @(got_case_frame);

            avg_zc     = case_sum_phase_zc / FRAMES_PER_CASE;
            avg_cordic = case_sum_phase_cordic / FRAMES_PER_CASE;
            avg_zc_wrapped = avg_zc;
            while (avg_zc_wrapped >= 180.0)
                avg_zc_wrapped = avg_zc_wrapped - 360.0;
            while (avg_zc_wrapped < -180.0)
                avg_zc_wrapped = avg_zc_wrapped + 360.0;

            avg_cordic_wrapped = avg_cordic;
            while (avg_cordic_wrapped >= 180.0)
                avg_cordic_wrapped = avg_cordic_wrapped - 360.0;
            while (avg_cordic_wrapped < -180.0)
                avg_cordic_wrapped = avg_cordic_wrapped + 360.0;

            expected_cordic_phase_deg = angle_deg;
            while (expected_cordic_phase_deg >= 180.0)
                expected_cordic_phase_deg = expected_cordic_phase_deg - 360.0;
            while (expected_cordic_phase_deg < -180.0)
                expected_cordic_phase_deg = expected_cordic_phase_deg + 360.0;

            $display("CASE DONE: %s", case_name);
            $display("          avg phase_zc     = %0.3f deg (%0.3f wrapped)", avg_zc, avg_zc_wrapped);
            $display("          avg phase_cordic = %0.3f deg (%0.3f wrapped)", avg_cordic, avg_cordic_wrapped);
            $display("          expected CORDIC relative phase ~= %0.1f deg", expected_cordic_phase_deg);
            $display("");

            tone_enable = 1'b0;
            repeat (20) @(posedge clk);
        end
    endtask

    // Sample generation:
    // I = cos(wt)
    // Q = cos(wt - phase_offset)
    // where phase_offset (tone_phase_deg) means Q lags I by that many degrees.
    // At phase_offset = 90 deg, Q = sin(wt), i.e. true sine/cos quadrature.
    // Both are converted to 12-bit offset-binary at DUT top-level inputs.
    always @(posedge clk) begin
        real t_sec;
        real theta;
        real phase_rad;
        integer i_int;
        integer q_int;
        logic signed [11:0] i_s12;
        logic signed [11:0] q_s12;

        if (rst) begin
            sample_idx      <= 0;
            adc1_data_a_d0  <= 12'h800;
            adc1_data_b_d0  <= 12'h800;
        end else if (tone_enable) begin
            t_sec     = $itor(sample_idx) / SAMPLE_HZ;
            theta     = 2.0 * PI * tone_freq_hz * t_sec;
            phase_rad = tone_phase_deg * PI / 180.0;

            i_int = $rtoi(AMP_CODES * $cos(theta));
            q_int = $rtoi(AMP_CODES * $cos(theta - phase_rad));

            i_s12 = clamp_s12(i_int);
            q_s12 = clamp_s12(q_int);

            adc1_data_a_d0 <= signed_to_offset12(i_s12);
            adc1_data_b_d0 <= signed_to_offset12(q_s12);
            sample_idx <= sample_idx + 1;
        end else begin
            adc1_data_a_d0 <= 12'h800;
            adc1_data_b_d0 <= 12'h800;
            sample_idx <= 0;
        end
    end

    // Packet capture
    always @(posedge clk) begin
        if (rst) begin
            pkt_idx <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            pkt[pkt_idx] = m_axis_tdata;
            if (pkt_idx == 15) begin
                pkt_idx <= 0;
                process_frame();
            end else begin
                pkt_idx <= pkt_idx + 1;
            end
        end
    end

    initial begin
        integer fi;
        integer ai;
        real freqs_mhz [0:2];
        real angles_deg [0:2];

        $dumpfile("tb_adc_stats.vcd");
        $dumpvars(0, tb_adc_stats);

        freqs_mhz[0] = 10.0;
        freqs_mhz[1] = 25.6;
        freqs_mhz[2] = 40.0;

        angles_deg[0] = 15.0;
        angles_deg[1] = 45.0;
        angles_deg[2] = 90.0;

        tone_enable = 1'b0;
        tone_freq_hz = 10.0e6;
        tone_phase_deg = 0.0;

        repeat (5) @(posedge clk);

        $display("=== tb_adc_stats start ===");
        $display("Clock: 125 MHz, 12-bit offset-binary ADC drive");
        $display("Runs: 3 frequencies x 3 phase offsets, %0d frames/case", FRAMES_PER_CASE);
        $display("Stimulus convention: I=cos(wt), Q=cos(wt-phase), so phase means Q lag relative to I");
        $display("");

        for (fi = 0; fi < 3; fi = fi + 1) begin
            for (ai = 0; ai < 3; ai = ai + 1) begin
                run_case(freqs_mhz[fi], angles_deg[ai]);
            end
        end

        $display("=== tb_adc_stats complete ===");
        $finish;
    end

endmodule


// -----------------------------------------------------------------------------
// Behavioral CORDIC model for simulation only.
// Matches port signature of generated Xilinx cordic_0 IP used by adc_stats.
// -----------------------------------------------------------------------------
`ifndef TB_USE_XILINX_CORDIC
module cordic_0 (
    input  wire        aclk,
    input  wire        s_axis_cartesian_tvalid,
    input  wire [31:0] s_axis_cartesian_tdata,
    output reg         m_axis_dout_tvalid,
    output reg  [15:0] m_axis_dout_tdata
);

    localparam integer LATENCY = 16;
    localparam real PI = 3.14159265358979323846;

    reg [LATENCY:0] vpipe;
    reg signed [15:0] dpipe [0:LATENCY];

    integer i;
    real x;
    real y;
    real ang;
    integer q;

    initial begin
        vpipe = '0;
        m_axis_dout_tvalid = 1'b0;
        m_axis_dout_tdata = 16'd0;
        for (i = 0; i <= LATENCY; i = i + 1)
            dpipe[i] = 16'sd0;
    end

    always @(posedge aclk) begin
        vpipe[0] <= s_axis_cartesian_tvalid;

        if (s_axis_cartesian_tvalid) begin
            x = $itor($signed(s_axis_cartesian_tdata[11:0])) / 2048.0;
            y = $itor($signed(s_axis_cartesian_tdata[27:16])) / 2048.0;
            ang = $atan2(y, x);

            q = $rtoi(ang * 32768.0 / PI);
            if (q > 32767)
                q = 32767;
            else if (q < -32768)
                q = -32768;

            dpipe[0] <= q[15:0];
        end

        for (i = 1; i <= LATENCY; i = i + 1) begin
            vpipe[i] <= vpipe[i-1];
            dpipe[i] <= dpipe[i-1];
        end

        m_axis_dout_tvalid <= vpipe[LATENCY];
        m_axis_dout_tdata  <= dpipe[LATENCY];
    end

endmodule
`endif

`default_nettype wire
