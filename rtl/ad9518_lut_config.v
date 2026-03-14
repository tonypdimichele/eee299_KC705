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
/********************************************************************************
dual modulus mode(P//P + 1): fvco = (fref/R)*(P*B+A)
FD mode of 1, 2,or 3 : fvco = (fref/R)*(P*B+A)
example: refclk 25MHz,R=1,P=8,B=10, A=0, fvco=(25MHz/R)*(8*10+0)=2000MHz
ad9518-3, on-chip VCO 1750MHz-2250MHz,external VCO 2400MHz
*********************************************************************************/
module ad9518_lut_config(
	input[9:0]             lut_index,   //Look-up table address
	output reg[24:0]       lut_data     //reg address reg data
);

always@(*)
begin
	case(lut_index)			  
		10'd  0 : lut_data <= {16'h0000 , 8'h3C};  	//soft reset
		10'd  1 : lut_data <= {16'h0000 , 8'h18};
		10'd  2 : lut_data <= {16'h0004 , 8'h00};  	//[0] read back active register
		10'd  3 : lut_data <= {16'h0010 , 8'h7C};  	//pfd and charge pump [7]:pfd polarity [6:4]: charge pump current [3:2]:charge pump mode [1:0] PLL normal mode
        10'd  4 : lut_data <= {16'h0011 , 8'h01};   //14bit R divider LSB[7:0]   
		10'd  5 : lut_data <= {16'h0012 , 8'h00};   //14bit R divider MSB[13:8]=[5:0] 
		10'd  6 : lut_data <= {16'h0013 , 8'h00};   //6bit A counter
		10'd  7 : lut_data <= {16'h0014 , 8'h0A};   //13bit B divider LSB[7:0]    
		10'd  8 : lut_data <= {16'h0015 , 8'h00};   //14bit B divider MSB[12:8]  
		10'd  9 : lut_data <= {16'h0016 , 8'h04};   //PLL control 1 [2:0]:prescaler(P)
		10'd  10: lut_data <= {16'h0017 , 8'hB4}; 	//PLL control 2 [7:2]:STATUS pin control
        10'd  11: lut_data <= {16'h0018 , 8'h06};   //PLL control 3 [0]:VCO cal now
		10'd  12: lut_data <= {16'h0019 , 8'h00}; 	//PLL control 4
		10'd  13: lut_data <= {16'h001A , 8'h00}; 	//PLL control 5 [5:0]: LD pin control
		10'd  14: lut_data <= {16'h001B , 8'h00}; 	//PLL control 6
		10'd  15: lut_data <= {16'h001C , 8'h02};	//PLL control 7  [2]:REF2 power-on  [1]:REF1 power-on [0]:differential reference
		10'd  16: lut_data <= {16'h001D , 8'h00};	//PLL control 8	
		10'd  17: lut_data <= {16'h0232 , 8'h01}; 	//[0] update all register(self clearing)
		10'd  18: lut_data <= {16'h00F0 , 8'h08}; 	//LVPECL OUTPUT 0 [4]:invert [3:2]:voltage [1:0] power-down(2'b00 normal mode)
        10'd  19: lut_data <= {16'h00F1 , 8'h0A};	//LVPECL OUTPUT 1 [4]:invert [3:2]:voltage [1:0] power-down(2'b00 normal mode)
		10'd  20: lut_data <= {16'h00F2 , 8'h0A};   //LVPECL OUTPUT 2 [4]:invert [3:2]:voltage [1:0] power-down(2'b00 normal mode)
		10'd  21: lut_data <= {16'h00F3 , 8'h0A};   //LVPECL OUTPUT 3 [4]:invert [3:2]:voltage [1:0] power-down(2'b00 normal mode)
		10'd  22: lut_data <= {16'h00F4 , 8'h08};   //LVPECL OUTPUT 4 [4]:invert [3:2]:voltage [1:0] power-down(2'b00 normal mode)
		10'd  23: lut_data <= {16'h00F5 , 8'h08};   //LVPECL OUTPUT 5 [4]:invert [3:2]:voltage [1:0] power-down(2'b00 normal mode)
		10'd  24: lut_data <= {16'h0190 , 8'h00};	//divider 0: low cycle [7:4]+1  high cycle [3:0]+1  divider output = diviver input/([7:4]+1+[3:0]+1)
		10'd  25: lut_data <= {16'h0191 , 8'h80};	//divider 0
        10'd  26: lut_data <= {16'h0192 , 8'h00};	//divider 0
		10'd  27: lut_data <= {16'h0193 , 8'h00};	//divider 1: low cycle [7:4]+1  high cycle [3:0]+1  divider output = diviver input/([7:4]+1+[3:0]+1)
		10'd  28: lut_data <= {16'h0194 , 8'h00};   //divider 1
		10'd  29: lut_data <= {16'h0195 , 8'h00};   //divider 1
		10'd  30: lut_data <= {16'h0196 , 8'h44};   //divider 2: low cycle [7:4]+1  high cycle [3:0]+1  divider output = diviver input/([7:4]+1+[3:0]+1)
		10'd  31: lut_data <= {16'h0197 , 8'h80};   //divider 2
		10'd  32: lut_data <= {16'h0198 , 8'h00};   //divider 2
		10'd  33: lut_data <= {16'h01E0 , 8'h00};	//VCO divider [2:0]
		10'd  34: lut_data <= {16'h01E1 , 8'h02};	//Input clock select vco or clk
		10'd  35: lut_data <= {16'h0018 , 8'h07}; 	//PLL control 3 [0]:VCO cal now
		10'd  36: lut_data <= {16'h0232 , 8'h01};	//[0] update all register(self clearing)	
		default:lut_data <= {16'hffff,8'hff};
	endcase
end
endmodule                                             