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
//  2018/2/24     meisq          1.0         Original
//*******************************************************************************/

module spi_config
(
	input              	rst,
	input              	clk,
	input[15:0]        	clk_div_cnt,
	output reg[9:0]    	lut_index,
	input[15:0]        	lut_reg_addr,
	input[7:0]         	lut_reg_data,
	input			   	start,
	input			   	restart,
	input [7:0]        i_manual_read_addr,
	input              i_manual_read,
	output reg [7:0]   o_manual_read_data,
	output reg         o_manual_read_done_toggle,
	output             o_manual_read_busy,
	input			   	three_wire,
    input              	addr_2byte,	
	output reg         	error,
	output reg            	done,
	input				pll_check,
	output				pll_locked,
	output             	spi_ce,
	output             	spi_sclk,
	inout               spi_sdio,
	input               spi_sdo,
	output              spi_sdio_i_dbg,
	output              spi_sdio_o_dbg,
	output              spi_sdio_t_dbg
);

reg 			spi_read_req;
wire 			spi_read_req_ack;
reg 			spi_write_req;
wire 			spi_write_req_ack;
wire[15:0] 		spi_slave_reg_addr;
wire[7:0] 		spi_write_data;
wire[7:0] 		spi_read_data;
reg 			read_check_error ;
reg [7:0]       manual_read_addr_reg;

reg [31:0]	 	spi_cnt ;
reg [7:0]	 	pll_readback ;
wire 			err;

wire			busy ;
wire			read_data_valid ;
wire			wr_done ;

reg[3:0] 		state;

localparam S_IDLE                =  0;
localparam S_START               =  1;
localparam S_WR_SPI_CHECK        =  2;
localparam S_WR_SPI              =  3;
localparam S_RD_SPI_CHECK        =  4;
localparam S_RD_SPI              =  5;
localparam S_WR_SPI_DONE         =  6;
localparam S_PLL_STATUS_CHECK    =  7;
localparam S_PLL_SPI             =  8;
localparam S_MANUAL_RD_SPI       =  9;


assign spi_slave_reg_addr = (state == S_PLL_STATUS_CHECK || state == S_PLL_SPI) ? 16'h001F :
							(state == S_MANUAL_RD_SPI) ? {manual_read_addr_reg, 8'h00} :
                            lut_reg_addr;
assign spi_write_data  = lut_reg_data;

assign pll_locked = pll_readback[0] ;
assign o_manual_read_busy = (state != S_WR_SPI_DONE);

always@(posedge clk or posedge rst)
begin
	if(rst)
	begin
		state <= S_IDLE;
		error <= 1'b0;
		lut_index <= 8'd0;
		read_check_error <= 1'b0 ;
		spi_read_req <= 1'b0;
		spi_write_req <= 1'b0;
		spi_cnt <= 0 ;
		done <= 0 ;
		pll_readback <= 0 ;
		o_manual_read_data <= 8'h00;
		o_manual_read_done_toggle <= 1'b0;
		manual_read_addr_reg <= 8'h00;
	end
	else 
		case(state)
			S_IDLE:
			begin
				if (start)
				  state <= S_START ;
				else
				  state <= S_IDLE ;
			end
			S_START:
			begin
				if (busy)
				  state <= S_IDLE ;
				else
				  state <= S_WR_SPI_CHECK ;
			end
			
			S_WR_SPI_CHECK:
			begin
				if(spi_slave_reg_addr != 16'hffff)
				begin
					spi_write_req <= 1'b1;
					state <= S_WR_SPI;
				end
				else
				begin
					state <= S_RD_SPI_CHECK;
					lut_index <= 8'd0;
				end
			end
			S_WR_SPI:
			begin
				if(wr_done)
				begin
					lut_index <= lut_index + 8'd1;
					state <= S_WR_SPI_CHECK;
				end
				spi_write_req <= 1'b0;
			end			
			S_RD_SPI_CHECK:
			begin
				if(spi_slave_reg_addr != 16'hffff)
				begin
					spi_read_req <= 1'b1;
					state <= S_RD_SPI;
				end
				else
				begin
					if (pll_check == 1'b1)						
						state <= S_PLL_STATUS_CHECK;
					else
					begin
						done <= 1 ;
						state <= S_WR_SPI_DONE;
					end
				end
				read_check_error <= 1'b0 ;
			end
			S_RD_SPI:
			begin
				if(read_data_valid)
				begin
					if (spi_read_data != lut_reg_data)
						read_check_error <= 1'b1 ;
						
					lut_index <= lut_index + 8'd1;
					state <= S_RD_SPI_CHECK;
				end
				spi_read_req <= 1'b0;
			end
			S_PLL_STATUS_CHECK:
			begin
				if(spi_cnt >= 50_000_000)
				begin
					spi_read_req <= 1'b1;
					spi_cnt <= 0 ;
					state <= S_PLL_SPI;
				end
				else
				begin
					spi_cnt <= spi_cnt + 1'b1 ;
				end
			end
			S_PLL_SPI:
			begin
				if(read_data_valid)
				begin					
					pll_readback <= spi_read_data ;
					done <= 1 ;
					state <= S_WR_SPI_DONE;
				end
				spi_read_req <= 1'b0;
			end
			S_MANUAL_RD_SPI:
			begin
				if(read_data_valid)
				begin
					o_manual_read_data <= spi_read_data;
					o_manual_read_done_toggle <= ~o_manual_read_done_toggle;
					state <= S_WR_SPI_DONE;
				end
				spi_read_req <= 1'b0;
			end
			
			
			S_WR_SPI_DONE:
			begin	
				done <= 0 ;
				if (restart)
				begin
					lut_index <= 0 ;
					state <= S_START ;
				end
				else if (i_manual_read)
				begin
					manual_read_addr_reg <= i_manual_read_addr;
					spi_read_req <= 1'b1;
					state <= S_MANUAL_RD_SPI;
				end
				else				
					state <= S_WR_SPI_DONE;
			end
			
			default:
				state <= S_IDLE;
		endcase
end

spi_config_ctrl spi_config_ctrl_inst
(
	.rst                 (rst             ),
	.clk                 (clk             ),
	.clk_div_cnt         (16'd49     ),
	.reg_addr            (spi_slave_reg_addr        ),
	.write_data          (spi_write_data      ),
	.write               (spi_write_req           ),
	.read_data           (spi_read_data       ),
	.read_data_valid     (read_data_valid ),
	.read                (spi_read_req            ),
	.cpol                (1'b0            ),
	.cpha                (1'b0            ),
	.three_wire          (three_wire      ),
	.addr_2byte          (addr_2byte      ),
	.busy          		 (busy      ),
	.wr_done          	(wr_done      ),
	.spi_ce              (spi_ce          ),
	.spi_sclk            (spi_sclk        ),
	.spi_sdio            (spi_sdio         ),
	.spi_sdo             (spi_sdo          ),
	.spi_sdio_i_dbg      (spi_sdio_i_dbg   ),
	.spi_sdio_o_dbg      (spi_sdio_o_dbg   ),
	.spi_sdio_t_dbg      (spi_sdio_t_dbg   )
);



endmodule