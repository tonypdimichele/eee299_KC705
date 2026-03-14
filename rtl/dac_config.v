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
	output             	clk_spi_ce,		//ad9518 ce
	output             	dac1_spi_ce,	//ad9781 ce
	output             	dac2_spi_ce,	//ad9781 ce
	output             	spi_sclk,
	inout               spi_sdio,
	input               spi_sdo
    );

	
	
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

reg	[7:0] 			delay_value;
reg	[3:0] 			state;

localparam S_IDLE                		=  0;
localparam S_CONFIG_AD9518        		=  1;
localparam S_CONFIG_AD9781_1            =  2;
localparam S_CONFIG_AD9781_2        	=  3;
localparam S_CONFIG_DONE              	=  4;




assign ad9518_lut_index = (state == S_CONFIG_AD9518)?lut_index: 0 ;
assign ad9781_lut_index = (state == S_CONFIG_AD9781_1 || state == S_CONFIG_AD9781_2)?lut_index: 0 ;

assign lut_reg_data = (state == S_CONFIG_AD9781_1 || state == S_CONFIG_AD9781_2)?ad9781_lut_data:ad9518_lut_data ;

assign clk_spi_ce = (state == S_CONFIG_AD9518)?spi_ce: 1 ;
assign dac1_spi_ce = (state == S_CONFIG_AD9781_1)?spi_ce: 1 ;
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
				delay_value <= DAC1_DELAY ;
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
				delay_value <= DAC2_DELAY ;
				if(done)
				begin
					state <= S_CONFIG_DONE;
				end
			end
			S_CONFIG_DONE:
			begin
				state <= S_CONFIG_DONE;
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
	.three_wire          		(three_wire      			),
    .addr_2byte          		(addr_2byte     			),	
	.error                      (                        	),
	.done                       (done                  		),	
	.spi_ce              		(spi_ce          ),
	.spi_sclk            		(spi_sclk        ),
	.spi_sdio            		(spi_sdio         ),
	.spi_sdo             		(spi_sdo          )
);   	



endmodule
