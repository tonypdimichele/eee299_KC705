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

module adc_lut_config(
	input[9:0]             lut_index,   //Look-up table address
	output reg[24:0]       lut_data     //reg address reg data
);

always@(*)
begin
	case(lut_index)			  
		10'd  0: lut_data <= {16'h0014 , 8'h40};
		10'd  1: lut_data <= {16'h0017 , 8'h06};
//		10'd  2: lut_data <= {16'h000d , 8'h07};
//		10'd  3: lut_data <= {16'h00ff , 8'h01};
//		10'd  4: lut_data <= {16'h0005 , 8'h02};
//        10'd  5: lut_data <= {16'h000d , 8'h04};
        10'd  2: lut_data <= {16'h00ff , 8'h01};		
		default:lut_data <= {16'hffff,8'hff};
	endcase
end


endmodule 