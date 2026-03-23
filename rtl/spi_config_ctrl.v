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

module spi_config_ctrl
(
	input              	rst,
	input              	clk,
	input [15:0]       	clk_div_cnt,   //counter - 1
	input [15:0]	   	reg_addr,
	input [7:0]		   	write_data,
	input			   	write,
	output reg [7:0]	   	read_data,
	output	reg		   	read_data_valid,
	input			   	read,
	input           	cpol,
	input           	cpha,
	input			   	three_wire,
	input			   	addr_2byte,
	output 				busy,
	output 				wr_done,
	output             	spi_ce,
	output             	spi_sclk,
	inout               spi_sdio,
	input               spi_sdo,
	output              spi_sdio_i_dbg,
	output              spi_sdio_o_dbg,
	output              spi_sdio_t_dbg
	
	
);

 reg 		spi_read_req;
 wire 		spi_read_req_ack;
 reg 		spi_write_req;
 wire 		spi_write_req_ack;
 reg[15:0] 	spi_slave_reg_addr;
 reg[7:0] 	spi_write_data;
 wire[7:0] 	spi_read_data;

 wire         		spi_dir	;
 wire			   	spi_tri_in	;
 wire			   	spi_out ;
 wire			   	spi_in ;

 reg[3:0] state;

localparam S_IDLE                =  0;
localparam S_WR_SPI              =  1;
localparam S_RD_SPI              =  2;
localparam S_WR_SPI_DONE         =  3;

assign busy = (state == S_IDLE)?1'b0:1'b1; 
assign wr_done = (state == S_WR_SPI_DONE); 


IOBUF IOBUF_inst 
(
	.O (spi_tri_in),   
	.IO(spi_sdio),  
	.I (spi_out),
	.T (spi_dir)   
);


assign spi_in = three_wire?spi_tri_in:spi_sdo ;
assign spi_sdio_i_dbg = spi_tri_in;
assign spi_sdio_o_dbg = spi_out;
assign spi_sdio_t_dbg = spi_dir;


always@(posedge clk or posedge rst)
begin
	if(rst)
	begin
		state <= S_IDLE;
		read_data_valid <= 1'b0 ;
		spi_slave_reg_addr <= 16'd0 ;
		spi_write_data <= 8'd0 ;
	end
	else 
		case(state)
			S_IDLE:
			begin
				if (write == 1'b1)
				begin
				  state <= S_WR_SPI ;
				  spi_write_data <= write_data ;
				end
				else if (read == 1'b1)
				begin
				  state <= S_RD_SPI ;				  
				end
				else
				  state <= S_IDLE ;
				  
				spi_slave_reg_addr <= reg_addr ;
			end	
			S_WR_SPI:
			begin
				if(spi_write_req_ack)
				begin
					spi_write_req <= 1'b0;
					state <= S_WR_SPI_DONE;
				end
				else
					spi_write_req <= 1'b1;
			end			

			S_RD_SPI:
			begin
				if(spi_read_req_ack)
				begin
					spi_read_req <= 1'b0;
					state <= S_WR_SPI_DONE;
					read_data <= spi_read_data ;
					read_data_valid <= 1'b1 ;
				end
				else
					spi_read_req <= 1'b1;
			end		
			
			S_WR_SPI_DONE:
			begin				
				state <= S_IDLE;
				read_data_valid <= 1'b0 ;
			end
			
			default:
				state <= S_IDLE;
		endcase
end

spi_cmd spi_cmd_m0(
	.clk             (clk                 ),
	.rst             (rst                 ),
	.spi_ce          (spi_ce              ),
	.spi_sclk        (spi_sclk            ),
	.spi_dir          (spi_dir              ),
	.spi_in          (spi_in              ),
	.spi_out         (spi_out              ),
	.cpol         	 (cpol              ),
	.cpha         	 (cpha              ),
	.clk_div_cnt     (clk_div_cnt              ),
	.three_wire		 (three_wire),
	.addr_2byte		 (addr_2byte),
	.cmd_read        (spi_read_req        ),
	.cmd_write       (spi_write_req       ),
	.cmd_read_ack    (spi_read_req_ack    ),
	.cmd_write_ack   (spi_write_req_ack   ),
	.read_addr       (spi_slave_reg_addr ),
	.write_addr      (spi_slave_reg_addr  ),
	.read_data       (spi_read_data       ),
	.write_data      (spi_write_data      )
);
endmodule