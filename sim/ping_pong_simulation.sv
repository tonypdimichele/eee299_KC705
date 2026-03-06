`timescale 1ns / 1ps
`default_nettype none

module ping_pong_simulation;

    localparam int DATA_WIDTH = 8;
    localparam int DEPTH = 64;

    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [DATA_WIDTH-1:0] from_rpi_tdata;
    logic                  from_rpi_tvalid;
    logic                  from_rpi_tready;
    logic                  from_rpi_tlast;

    // Intermediate stream between dut_tx and dut_rx (matches top-level naming)
    logic [DATA_WIDTH-1:0] buffer_tdata;
    logic                  buffer_tvalid;
    logic                  buffer_tready;
    logic                  buffer_tlast;

    // Final egress stream from dut_rx (matches top-level naming)
    logic [DATA_WIDTH-1:0] to_rpi_buffer_tdata;
    logic                  to_rpi_buffer_tvalid;
    logic                  to_rpi_buffer_tready;
    logic                  to_rpi_buffer_tlast;

    // DUT chain: dut_tx -> dut_rx
    ping_pong_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut_tx (
        .clk(clk),
        .rst(rst),
        .i_s_axis_tdata(from_rpi_tdata),
        .i_s_axis_tvalid(from_rpi_tvalid),
        .o_s_axis_tready(from_rpi_tready),
        .i_s_axis_tlast(from_rpi_tlast),
        .o_m_axis_tdata(buffer_tdata),
        .o_m_axis_tvalid(buffer_tvalid),
        .i_m_axis_tready(buffer_tready),
        .o_m_axis_tlast(buffer_tlast)
    );

    ping_pong_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut_rx (
        .clk(clk),
        .rst(rst),
        .i_s_axis_tdata(buffer_tdata),
        .i_s_axis_tvalid(buffer_tvalid),
        .o_s_axis_tready(buffer_tready),
        .i_s_axis_tlast(buffer_tlast),
        .o_m_axis_tdata(to_rpi_buffer_tdata),
        .o_m_axis_tvalid(to_rpi_buffer_tvalid),
        .i_m_axis_tready(to_rpi_buffer_tready),
        .o_m_axis_tlast(to_rpi_buffer_tlast)
    );

    always #8 clk = ~clk;

    typedef struct packed {
        logic [7:0] data;
        logic       last;
    } word_t;

    word_t exp_q[$];
    int error_count = 0;

    task automatic push_expected(input logic [7:0] d, input logic l);
        word_t w;
        begin
            w.data = d;
            w.last = l;
            exp_q.push_back(w);
        end
    endtask

    task automatic send_word(input logic [7:0] d, input logic l);
        begin
            @(posedge clk);
            from_rpi_tdata  <= d;
            from_rpi_tlast  <= l;
            from_rpi_tvalid <= 1'b1;
            // Wait for exactly one accepted beat.
            while (!(from_rpi_tvalid && from_rpi_tready)) @(posedge clk);
            push_expected(d, l);
            from_rpi_tvalid <= 1'b0;
            from_rpi_tlast  <= 1'b0;
        end
    endtask

    task automatic send_packet(input logic [7:0] base, input int nbytes);
        int i;
        begin
            for (i = 0; i < nbytes; i = i + 1) begin
                send_word(base + i[7:0], (i == nbytes-1));
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst && to_rpi_buffer_tvalid && to_rpi_buffer_tready) begin
            word_t exp;
            if (exp_q.size() == 0) begin
                $error("Output word with empty expected queue: data=%0h last=%0b", to_rpi_buffer_tdata, to_rpi_buffer_tlast);
                error_count <= error_count + 1;
            end else begin
                exp = exp_q.pop_front();
                if (to_rpi_buffer_tdata !== exp.data || to_rpi_buffer_tlast !== exp.last) begin
                    $error("Mismatch: got data=%0h last=%0b expected data=%0h last=%0b",
                           to_rpi_buffer_tdata, to_rpi_buffer_tlast, exp.data, exp.last);
                    error_count <= error_count + 1;
                end
            end
        end
    end

    initial begin
        from_rpi_tdata  = '0;
        from_rpi_tvalid = 1'b0;
        from_rpi_tlast  = 1'b0;
        to_rpi_buffer_tready = 1'b0;

        repeat (8) @(posedge clk);
        rst = 1'b0;

        // Keep output mostly ready, but add occasional backpressure.
        fork
            begin : ready_driver
                forever begin
                    @(posedge clk);
                    to_rpi_buffer_tready <= ($urandom_range(0, 3) != 0);
                end
            end
        join_none

        // Send a few packets to exercise ping-pong bank alternation.
        send_packet(8'h10, 12);
        send_packet(8'h40, 9);
        send_packet(8'h80, 16);

        // Wait for all expected words to drain.
        wait (exp_q.size() == 0);
        repeat (20) @(posedge clk);

        if (error_count == 0) begin
            $display("PASS: ping_pong_buffer simulation completed without mismatches");
        end else begin
            $display("FAIL: ping_pong_buffer simulation saw %0d mismatches", error_count);
        end

        $finish;
    end

endmodule

`default_nettype wire
