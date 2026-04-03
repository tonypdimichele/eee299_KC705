//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
//                                                                              //
//  Author: meisq                                                               //
//          msq@qq.com                                                          //
//          ALINX(shanghai) Technology Co.,Ltd                                  //
//          heijin                                                              //
//     WEB: http://www.alinx.cn/                                                //
//     BBS: http://www.heijin.org/                                              //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
// Copyright (c) 2017,ALINX(shanghai) Technology Co.,Ltd                        //
//                    All rights reserved                                       //
//                                                                              //
// This source file may be used and distributed without restriction provided    //
// that this copyright statement is not removed from the file and that any      //
// derivative work contains the original copyright notice and the associated    //
// disclaimer.                                                                  //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////

//================================================================================
//  Revision History:
//  Date          By            Revision    Change Description
//--------------------------------------------------------------------------------
//  2018/2/24     meisq         1.0         Original
//*******************************************************************************/
module adc_top(
    //sys clock
    input                     clk_50M,
	input                     clk_125M,
	input 				      locked,
	input                     rst_n,        //low reset
	output                    adc1_clk_ref,//clk to first AD9627
	output                    adc2_clk_ref,//clk to second AD9627
	
	output                    adc1_spi_ce, //adc1 chip spi select
	output                    adc1_spi_sclk,//adc1 spi clk
	inout                     adc1_spi_io,  //spi data
	input                     adc1_clk_p,  //adc1 clk from ad9627
	input                     adc1_clk_n,	
	input[11:0]               adc1_data_p, //adc1 data
	input[11:0]               adc1_data_n,
	
	output                    adc2_spi_ce,//adc2 chip spi select
	output                    adc2_spi_sclk,//adc2 spi clk
	inout                     adc2_spi_io,//spi data
	input                     adc2_clk_p,//adc2 clk from ad9627
	input                     adc2_clk_n,
	input[11:0]               adc2_data_p,//adc2 data
	input[11:0]               adc2_data_n
    );
                                 
wire clk_50m;
wire clk_125m;
//wire locked;
wire[9:0]                       adc1_lut_index;
wire[24:0]                      adc1_lut_data;
wire[9:0]                       adc2_lut_index;
wire[24:0]                      adc2_lut_data;
wire                            adc1_clk;
wire                            adc2_clk;
wire[11:0]                      adc1_data;
wire[11:0]                      adc1_data_a;
wire[11:0]                      adc1_data_b;
wire[11:0]                      adc2_data;
wire[11:0]                      adc2_data_a;
wire[11:0]                      adc2_data_b;
(* MARK_DEBUG="true" *)reg[11:0] adc1_data_a_d0;
(* MARK_DEBUG="true" *)reg[11:0] adc1_data_b_d0;
(* MARK_DEBUG="true" *)reg[11:0] adc2_data_a_d0;
(* MARK_DEBUG="true" *)reg[11:0] adc2_data_b_d0;
assign fan_pwm=1'b0;
assign adc2_clk_ref = clk_125m;
assign adc1_clk_ref = clk_125m;

IBUFDS #(
	.DIFF_TERM("TRUE"),       // Differential Termination
	.IBUF_LOW_PWR("TRUE"),     // Low power="TRUE", Highest performance="FALSE" 
	.IOSTANDARD("LVDS_25")     // Specify the input I/O standard
) IBUFDS_adc1_clk (
	.O(adc1_clk),  // Buffer output
	.I(adc1_clk_p),  // Diff_p buffer input (connect directly to top-level port)
	.IB(adc1_clk_n) // Diff_n buffer input (connect directly to top-level port)
);

IBUFDS #(
	.DIFF_TERM("TRUE"),       // Differential Termination
	.IBUF_LOW_PWR("TRUE"),     // Low power="TRUE", Highest performance="FALSE" 
	.IOSTANDARD("LVDS_25")     // Specify the input I/O standard
) IBUFDS_adc2_clk (
	.O(adc2_clk),  // Buffer output
	.I(adc2_clk_p),  // Diff_p buffer input (connect directly to top-level port)
	.IB(adc2_clk_n) // Diff_n buffer input (connect directly to top-level port)
);

					
genvar i;
generate
	for (i = 0; i < 12; i = i + 1) begin:IBUFDS_DATAS
		IBUFDS #(
		.DIFF_TERM("TRUE"),       // Differential Termination
		.IBUF_LOW_PWR("TRUE"),     // Low power="TRUE", Highest performance="FALSE" 
		.IOSTANDARD("LVDS_25")     // Specify the input I/O standard
		) IBUFDS_adc1_data (
		.O(adc1_data[i]),  // Buffer output
		.I(adc1_data_p[i]),  // Diff_p buffer input (connect directly to top-level port)
		.IB(adc1_data_n[i]) // Diff_n buffer input (connect directly to top-level port)
		);
		
		IDDR #(
		.DDR_CLK_EDGE("OPPOSITE_EDGE"), // "OPPOSITE_EDGE", "SAME_EDGE" 
										//    or "SAME_EDGE_PIPELINED" 
		.INIT_Q1(1'b0), // Initial value of Q1: 1'b0 or 1'b1
		.INIT_Q2(1'b0), // Initial value of Q2: 1'b0 or 1'b1
		.SRTYPE("ASYNC") // Set/Reset type: "SYNC" or "ASYNC" 
        ) IDDR_adc1_data (
		.Q1(adc1_data_b[i]), // 1-bit output for positive edge of clock 
		.Q2(adc1_data_a[i]), // 1-bit output for negative edge of clock
		.C(adc1_clk),   // 1-bit clock input
		.CE(1'b1), // 1-bit clock enable input
		.D(adc1_data[i]),   // 1-bit DDR data input
		.R(1'b0),   // 1-bit reset
		.S(1'b0)    // 1-bit set
        );
		
		IBUFDS #(
		.DIFF_TERM("TRUE"),       // Differential Termination
		.IBUF_LOW_PWR("TRUE"),     // Low power="TRUE", Highest performance="FALSE" 
		.IOSTANDARD("LVDS_25")     // Specify the input I/O standard
		) IBUFDS_adc2_data (
		.O(adc2_data[i]),  // Buffer output
		.I(adc2_data_p[i]),  // Diff_p buffer input (connect directly to top-level port)
		.IB(adc2_data_n[i]) // Diff_n buffer input (connect directly to top-level port)
		);
		
		IDDR #(
		.DDR_CLK_EDGE("OPPOSITE_EDGE"), // "OPPOSITE_EDGE", "SAME_EDGE" 
										//    or "SAME_EDGE_PIPELINED" 
		.INIT_Q1(1'b0), // Initial value of Q1: 1'b0 or 1'b1
		.INIT_Q2(1'b0), // Initial value of Q2: 1'b0 or 1'b1
		.SRTYPE("ASYNC") // Set/Reset type: "SYNC" or "ASYNC" 
        ) IDDR_adc2_data (
		.Q1(adc2_data_b[i]), // 1-bit output for positive edge of clock 
		.Q2(adc2_data_a[i]), // 1-bit output for negative edge of clock
		.C(adc2_clk),   // 1-bit clock input
		.CE(1'b1), // 1-bit clock enable input
		.D(adc2_data[i]),   // 1-bit DDR data input
		.R(1'b0),   // 1-bit reset
		.S(1'b0)    // 1-bit set
        );		
	end
endgenerate

always@(posedge adc1_clk)
begin
	adc1_data_a_d0 <= adc1_data_a;
	adc1_data_b_d0 <= adc1_data_b;
end
always@(posedge adc2_clk)
begin
	adc2_data_a_d0 <= adc2_data_a;
	adc2_data_b_d0 <= adc2_data_b;
end


//   clk_wiz_0 sys_pll
//    (
//     // Clock out ports
//     .clk_out1(clk_50m),     // output clk_out1
//     .clk_out2(clk_125m),     // output clk_out2
//     // Status and control signals
//     .locked(locked),       // output locked
//    // Clock in ports
//     .clk_in1_p(sys_clk_p),    // input clk_in1_p
//     .clk_in1_n(sys_clk_n));    // input clk_in1_n

//configure look-up table
adc_lut_config lut_config_adc1(
	.lut_index                  (adc1_lut_index           ),
	.lut_data                   (adc1_lut_data            )
);
adc_spi_config spi_config_adc1(
	.rst                        (~locked                  ),
	.clk                        (clk_50m                  ),
	.clk_div_cnt                (16'd500                  ),
	.lut_index                  (adc1_lut_index           ),
	.lut_reg_addr               (adc1_lut_data[23:8]      ),
	.lut_reg_data               (adc1_lut_data[7:0]       ),
	.error                      (                         ),
	.done                       (                         ),	
	.spi_ce                     (adc1_spi_ce              ),
	.spi_sclk                   (adc1_spi_sclk            ),
	.spi_io                     (adc1_spi_io              )
);
//configure look-up table
adc_lut_config lut_config_adc2(
	.lut_index                  (adc2_lut_index           ),
	.lut_data                   (adc2_lut_data            )
);
adc_spi_config spi_config_adc2(
	.rst                        (~locked                  ),
	.clk                        (clk_50m                  ),
	.clk_div_cnt                (16'd500                  ),
	.lut_index                  (adc2_lut_index           ),
	.lut_reg_addr               (adc2_lut_data[23:8]      ),
	.lut_reg_data               (adc2_lut_data[7:0]       ),
	.error                      (                         ),
	.done                       (                         ),	
	.spi_ce                     (adc2_spi_ce              ),
	.spi_sclk                   (adc2_spi_sclk            ),
	.spi_io                     (adc2_spi_io              )
);

  

endmodule 
    
    