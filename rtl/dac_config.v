`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/02/25 09:13:43
// Design Name: 
// Module Name: adc_config
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module dac_config#
(
	parameter DAC1_DELAY  = 5'd10, //0-31
	parameter DAC2_DELAY  = 5'd5  //0-31
)
	(
	input              	rst,
	input              	clk,
	input  wire [4:0]   i_dac1_delay,
	input  wire [4:0]   i_dac2_delay,
	input  wire         i_apply,
	input  wire [7:0]   i_manual_read_addr,
	input  wire         i_manual_read,
	output wire [7:0]   o_manual_read_data,
	output wire         o_manual_read_done_toggle,
	output wire         o_manual_read_busy,
	output             	clk_spi_ce,		//ad9518 ce
	output             	dac1_spi_ce,	//ad9781 ce
	output             	dac2_spi_ce,	//ad9781 ce
	output             	spi_sclk,
	inout               spi_sdio,
	input               spi_sdo
    );
(*mark_debug = "true"*)
reg sdio_debug;
(*mark_debug = "true"*)
reg sdo_debug; 
(*mark_debug = "true"*)
reg spi_clk_debug;
(*mark_debug = "true"*)
reg dac1_cs_debug;
(*mark_debug = "true"*)
reg dac2_cs_debug;
(*mark_debug = "true"*)
reg pll_locked_debug;
always@(posedge clk)
begin
sdio_debug <= spi_sdio_o_dbg;
sdo_debug <= spi_sdo;
spi_clk_debug <= spi_sclk;
dac1_cs_debug <= dac1_spi_ce;
dac2_cs_debug <= dac2_spi_ce;
pll_locked_debug <= pll_locked;
end
	
wire [9:0]    	   	lut_index;
wire [23:0]        	lut_reg_data;
wire [9:0]    	   	ad9518_lut_index;
wire [23:0]        	ad9518_lut_data;
wire [9:0]    	   	ad9781_lut_index;
wire [23:0]        	ad9781_lut_data;





wire				spi_ce;
reg					three_wire;
reg        			addr_2byte;	
wire 				done ;
reg 				pll_check ;
wire 				pll_locked ;
reg 				start ;
reg 				restart ;
wire                spi_sdio_i_dbg;
wire                spi_sdio_o_dbg;
wire                spi_sdio_t_dbg;

reg	[7:0] 			delay_value;
(* mark_debug = "true" *) reg	[3:0] 			state;

localparam S_IDLE                		=  0;
localparam S_CONFIG_AD9518        		=  1;
localparam S_CONFIG_AD9781_1            =  2;
localparam S_CONFIG_AD9781_2        	=  3;
localparam S_CONFIG_DONE              	=  4;
localparam S_MANUAL_READ              	=  5;




assign ad9518_lut_index = (state == S_CONFIG_AD9518)?lut_index: 0 ;
assign ad9781_lut_index = (state == S_CONFIG_AD9781_1 || state == S_CONFIG_AD9781_2)?lut_index: 0 ;

assign lut_reg_data = (state == S_CONFIG_AD9781_1 || state == S_CONFIG_AD9781_2)?ad9781_lut_data:ad9518_lut_data ;

assign clk_spi_ce = (state == S_CONFIG_AD9518)?spi_ce: 1 ;
assign dac1_spi_ce = (state == S_CONFIG_AD9781_1 || state == S_MANUAL_READ)?spi_ce: 1 ;
assign dac2_spi_ce = (state == S_CONFIG_AD9781_2)?spi_ce: 1 ;



always@(posedge clk or posedge rst)
begin
	if(rst)
	begin
		state <= S_IDLE;
		start <= 1'b0 ;
		pll_check <= 1'b0 ;
		restart <= 1'b0 ;
		three_wire <= 1'b0 ;
		addr_2byte <= 1'b0 ;
		delay_value <= 8'd0 ;
	end
	else 
		case(state)
			S_IDLE:
			begin
				start <= 1'b1 ;
				pll_check <= 1'b1 ;
				three_wire <= 1'b1 ;
				addr_2byte <= 1'b1 ;
				state <= S_CONFIG_AD9518 ;
			end
			
			S_CONFIG_AD9518:
			begin
				start <= 1'b0 ;
				if(done & pll_locked)
				begin
					restart <= 1'b1;
					state <= S_CONFIG_AD9781_1;
				end
			end
			S_CONFIG_AD9781_1:
			begin
				three_wire <= 1'b0 ;
				addr_2byte <= 1'b0 ;
				pll_check <= 1'b0 ;
				delay_value <= {3'd0, i_dac1_delay} ;
				if(done)
				begin
					restart <= 1'b1;
					state <= S_CONFIG_AD9781_2;
				end
				else
				begin
					restart <= 1'b0;
					state <= S_CONFIG_AD9781_1;
				end
			end
			S_CONFIG_AD9781_2:
			begin
				restart <= 1'b0;
				three_wire <= 1'b0 ;
				addr_2byte <= 1'b0 ;
				pll_check <= 1'b0 ;
				delay_value <= {3'd0, i_dac2_delay} ;
				if(done)
				begin
					state <= S_CONFIG_DONE;
				end
			end
			S_CONFIG_DONE:
			begin
				three_wire <= 1'b0 ;
				addr_2byte <= 1'b0 ;
				pll_check <= 1'b0 ;
				if(i_apply)
				begin
					restart <= 1'b1;
					state <= S_CONFIG_AD9781_1;
				end
				else if(i_manual_read)
				begin
					restart <= 1'b0;
					state <= S_MANUAL_READ;
				end
				else
				begin
					restart <= 1'b0;
					state <= S_CONFIG_DONE;
				end
			end
			S_MANUAL_READ:
			begin
				restart <= 1'b0;
				three_wire <= 1'b0 ;
				addr_2byte <= 1'b0 ;
				pll_check <= 1'b0 ;
				if(!o_manual_read_busy)
				begin
					state <= S_CONFIG_DONE;
				end
				else
				begin
					state <= S_MANUAL_READ;
				end
			end
			
			default:
				state <= S_IDLE;
		endcase
end


ad9518_lut_config lut_config_clk(
	.lut_index                  (ad9518_lut_index           ),
	.lut_data                   (ad9518_lut_data            )
);


ad9781_lut_config lut_config_dac(
	.delay_value                (delay_value           ),
	.lut_index                  (ad9781_lut_index           ),
	.lut_data                   (ad9781_lut_data            )
);	
	
spi_config spi_config_clk(
	.rst                        (rst                 	),
	.clk                        (clk                 	),
	.clk_div_cnt                (16'd500                 	),
	.lut_index                  (lut_index           	),
	.lut_reg_addr               (lut_reg_data[23:8]      	),
	.lut_reg_data               (lut_reg_data[7:0]       	),
	.pll_check                  (pll_check              	),
	.pll_locked                 (pll_locked      	),
	.start          			(start      			 	),
	.restart          			(restart      			 	),
	.i_manual_read_addr         (i_manual_read_addr      ),
	.i_manual_read              (i_manual_read           ),
	.o_manual_read_data         (o_manual_read_data      ),
	.o_manual_read_done_toggle  (o_manual_read_done_toggle),
	.o_manual_read_busy         (o_manual_read_busy      ),
	.three_wire          		(three_wire      			),
    .addr_2byte          		(addr_2byte     			),	
	.error                      (                        	),
	.done                       (done                  		),	
	.spi_ce              		(spi_ce          ),
	.spi_sclk            		(spi_sclk        ),
	.spi_sdio            		(spi_sdio         ),
	.spi_sdo             		(spi_sdo          ),
	.spi_sdio_i_dbg      		(spi_sdio_i_dbg   ),
	.spi_sdio_o_dbg      		(spi_sdio_o_dbg   ),
	.spi_sdio_t_dbg      		(spi_sdio_t_dbg   )
);   	



endmodule
