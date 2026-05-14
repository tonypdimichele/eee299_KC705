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


module ad9781_lut_config(
	input [7:0]			   delay_value,
	input[9:0]             lut_index,   //Look-up table address
	output reg[23:0]       lut_data     //reg address reg data
);

always@(*)
begin
	case(lut_index)			  
		10'd  0 : lut_data <= {16'h0200 , 8'h00};
		10'd  1 : lut_data <= {16'h0B00 , 8'h00}; //DAC1 FSC made as low as possible to minimize swing
		10'd  2 : lut_data <= {16'h0C00 , 8'h00}; //DAC1 FSC
		10'd  3 : lut_data <= {16'h0D00 , 8'h00}; //AUXDAC1
		10'd  4 : lut_data <= {16'h0E00 , 8'h00}; //AUXDAC1
		10'd  5 : lut_data <= {16'h0F00 , 8'h00}; //DAC2 FSC same trying to minimize swing
        10'd  6 : lut_data <= {16'h1000 , 8'h00}; //DAC2 FSC
        10'd  7 : lut_data <= {16'h1100 , 8'h00}; //AUXDAC2
        10'd  8 : lut_data <= {16'h1200 , 8'h00}; //AUXDAC2
		10'd  9 : lut_data <= {16'h0500 , delay_value};		
		default:lut_data <= {16'hffff,8'hff};
	endcase
end


endmodule 