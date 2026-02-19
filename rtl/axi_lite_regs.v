// rtl/axi_lite_regs.v
`timescale 1ns/1ps
`default_nettype none
module axi_lite_regs #
(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6   // 0x00..0x0C
)
(
    input  wire                         s_axi_aclk,
    input  wire                         s_axi_aresetn,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,

    output reg  [1:0]                    s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,

    output reg  [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]                    s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    output reg  [7:0]                    reg3_out
);

    reg [31:0] reg0, reg1, reg3, reg2_counter;
    reg  aw_en;
    reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_latched, araddr_latched;

    // AW
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin s_axi_awready<=0; aw_en<=1; end
        else begin
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready<=1; awaddr_latched<=s_axi_awaddr; aw_en<=0;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_awready<=0; aw_en<=1;
            end else s_axi_awready<=0;
        end
    end

    // W
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) s_axi_wready<=0;
        else s_axi_wready <= (~s_axi_wready && s_axi_wvalid && s_axi_awvalid && aw_en);
    end

    wire [3:0] wstrb = s_axi_wstrb;
    wire [31:0] wdata = s_axi_wdata;
    wire [3:0] aw_word = awaddr_latched[5:2];

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin reg0<=0; reg1<=0; reg3<=0; end
        else if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid) begin
            case (aw_word)
                4'h0: begin if (wstrb[0]) reg0[7:0]  <=wdata[7:0];
                           if (wstrb[1]) reg0[15:8] <=wdata[15:8];
                           if (wstrb[2]) reg0[23:16]<=wdata[23:16];
                           if (wstrb[3]) reg0[31:24]<=wdata[31:24]; end
                4'h1: begin if (wstrb[0]) reg1[7:0]  <=wdata[7:0];
                           if (wstrb[1]) reg1[15:8] <=wdata[15:8];
                           if (wstrb[2]) reg1[23:16]<=wdata[23:16];
                           if (wstrb[3]) reg1[31:24]<=wdata[31:24]; end
                4'h3: begin if (wstrb[0]) reg3[7:0]  <=wdata[7:0];
                           if (wstrb[1]) reg3[15:8] <=wdata[15:8];
                           if (wstrb[2]) reg3[23:16]<=wdata[23:16];
                           if (wstrb[3]) reg3[31:24]<=wdata[31:24]; end
                default: ;
            endcase
        end
    end

    // B
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin s_axi_bvalid<=0; s_axi_bresp<=2'b00; end
        else if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid && ~s_axi_bvalid) begin
            s_axi_bvalid<=1; s_axi_bresp<=2'b00;
        end else if (s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
    end

    // AR
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin s_axi_arready<=0; araddr_latched<='h0; end
        else begin
            if (~s_axi_arready && s_axi_arvalid) begin s_axi_arready<=1; araddr_latched<=s_axi_araddr; end
            else s_axi_arready<=0;
        end
    end

    // R
    wire [3:0] ar_word = araddr_latched[5:2];
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin s_axi_rvalid<=0; s_axi_rresp<=2'b00; s_axi_rdata<=0; end
        else begin
            if (s_axi_arready && s_axi_arvalid && ~s_axi_rvalid) begin
                case (ar_word)
                    4'h0: s_axi_rdata <= reg0;
                    4'h1: s_axi_rdata <= reg1;
                    4'h2: s_axi_rdata <= reg2_counter;
                    4'h3: s_axi_rdata <= reg3;
                    default: s_axi_rdata <= 32'hDEAD_BEEF;
                endcase
                s_axi_rvalid<=1; s_axi_rresp<=2'b00;
            end else if (s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
        end
    end

    // Counter + LED
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin reg2_counter<=0; reg3_out<=8'h00; end
        else begin reg2_counter<=reg2_counter+1; reg3_out<=reg3[7:0]; end
    end
endmodule
`default_nettype wire