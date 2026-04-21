`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/03/04 09:52:45
// Design Name: 
// Module Name: iobuf
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
//`define ULTRASCALE

module dac_iobuf
	(
	//dac input clock from ad9518
	input					   dac1_dco_p,
	input					   dac1_dco_n,
	input					   dac2_dco_p,
	input					   dac2_dco_n,
	//dac1 signals
	output                     dac1_dci_p,	//dac output clock p
	output                     dac1_dci_n,	//dac output clock n
	output[13:0]               dac1_data_p, //dac output data p
	output[13:0]               dac1_data_n, //dac output data n
	//dac2 signals
	output                     dac2_dci_p,	//dac output clock p
	output                     dac2_dci_n,  //dac output clock n
	output[13:0]               dac2_data_p, //dac output data p
	output[13:0]               dac2_data_n,  //dac output data n
	
	input [13:0]			   dac1_h ,  //dac data oddr posedge
	input [13:0]			   dac1_l ,  //dac data oddr negedge
	input [13:0]			   dac2_h ,  //dac data oddr posedge
	input [13:0]			   dac2_l ,  //dac data oddr negedge
	output					   dac1_dco_buf ,
	output					   dac2_dco_buf 

    );
	
wire			dac1_dci ;  //dac clock oddr output
wire			dac2_dci ;	//dac clock oddr output
wire [13:0]		dac1_data ; //dac data oddr output
wire [13:0]		dac2_data ; //dac data oddr output

wire			dac1_dco_ibuf;
wire			dac2_dco_ibuf;



IBUFDS IBUFDS1_inst (
   .O (dac1_dco_ibuf),  // Buffer output
   .I (dac1_dco_p),  // Diff_p buffer input (connect directly to top-level port)
   .IB(dac1_dco_n) // Diff_n buffer input (connect directly to top-level port)
);

BUFG BUFG1_inst (
   .O(dac1_dco_buf), // 1-bit output: Clock output
   .I(dac1_dco_ibuf)  // 1-bit input: Clock input
);

IBUFDS IBUFDS2_inst (
   .O (dac2_dco_ibuf),  // Buffer output
   .I (dac2_dco_p),  // Diff_p buffer input (connect directly to top-level port)
   .IB(dac2_dco_n) // Diff_n buffer input (connect directly to top-level port)
);

BUFG BUFG2_inst (
   .O(dac2_dco_buf), // 1-bit output: Clock output
   .I(dac2_dco_ibuf)  // 1-bit input: Clock input
);

OBUFDS dac1_dci_obufds (
   .O   (dac1_dci_p),   // 1-bit output: Diff_p output (connect directly to top-level port)
   .OB  (dac1_dci_n), // 1-bit output: Diff_n output (connect directly to top-level port)
   .I   (dac1_dci)    // 1-bit input: Buffer input
);


OBUFDS dac2_dci_obufds (
   .O   (dac2_dci_p),   // 1-bit output: Diff_p output (connect directly to top-level port)
   .OB  (dac2_dci_n), // 1-bit output: Diff_n output (connect directly to top-level port)
   .I   (dac2_dci)    // 1-bit input: Buffer input
);


`ifdef ULTRASCALE

	ODDRE1 #(
	.IS_C_INVERTED(1'b0),  // Optional inversion for C
	.IS_D1_INVERTED(1'b0), // Unsupported, do not use
	.IS_D2_INVERTED(1'b0), // Unsupported, do not use
	.SRVAL(1'b0)           // Initializes the ODDRE1 Flip-Flops to the specified value (1'b0, 1'b1)
	)
	dac1_dci_oddr (
	.Q(dac1_dci),   // 1-bit output: Data output to IOB
	.C(dac1_dco_buf),   // 1-bit input: High-speed clock input
	.D1(1'b1), // 1-bit input: Parallel data input 1
	.D2(1'b0), // 1-bit input: Parallel data input 2
	.SR(1'b0)  // 1-bit input: Active High Async Reset
	);
	
	ODDRE1 #(
	.IS_C_INVERTED(1'b0),  // Optional inversion for C
	.IS_D1_INVERTED(1'b0), // Unsupported, do not use
	.IS_D2_INVERTED(1'b0), // Unsupported, do not use
	.SRVAL(1'b0)           // Initializes the ODDRE1 Flip-Flops to the specified value (1'b0, 1'b1)
	)
	dac2_dci_oddr (
	.Q(dac2_dci),   // 1-bit output: Data output to IOB
	.C(dac2_dco_buf),   // 1-bit input: High-speed clock input
	.D1(1'b1), // 1-bit input: Parallel data input 1
	.D2(1'b0), // 1-bit input: Parallel data input 2
	.SR(1'b0)  // 1-bit input: Active High Async Reset
	);
	
						
	genvar i;
	generate
		for (i = 0; i < 14; i = i + 1) begin:OBUFDS_DATAS
		
		
		ODDRE1 #(
		.IS_C_INVERTED(1'b0),  // Optional inversion for C
		.IS_D1_INVERTED(1'b0), // Unsupported, do not use
		.IS_D2_INVERTED(1'b0), // Unsupported, do not use
		.SRVAL(1'b0)           // Initializes the ODDRE1 Flip-Flops to the specified value (1'b0, 1'b1)
		)
		dac1_data_oddr (
		.Q(dac1_data[i]),   // 1-bit output: Data output to IOB
		.C(dac1_dco_buf),   // 1-bit input: High-speed clock input
		.D1(dac1_h[i]), // 1-bit input: Parallel data input 1
		.D2(dac1_l[i]), // 1-bit input: Parallel data input 2
		.SR(1'b0)  // 1-bit input: Active High Async Reset
		);
			
		OBUFDS dac1_data_obufds (
		.O   (dac1_data_p[i]),   // 1-bit output: Diff_p output (connect directly to top-level port)
		.OB  (dac1_data_n[i]), // 1-bit output: Diff_n output (connect directly to top-level port)
		.I   (dac1_data[i])    // 1-bit input: Buffer input
		);
		
		ODDRE1 #(
		.IS_C_INVERTED(1'b0),  // Optional inversion for C
		.IS_D1_INVERTED(1'b0), // Unsupported, do not use
		.IS_D2_INVERTED(1'b0), // Unsupported, do not use
		.SRVAL(1'b0)           // Initializes the ODDRE1 Flip-Flops to the specified value (1'b0, 1'b1)
		)
		dac2_data_oddr (
		.Q   (dac2_data[i]),   // 1-bit output: Data output to IOB
		.C   (dac2_dco_buf),   // 1-bit input: High-speed clock input
		.D1  (dac2_h[i]), // 1-bit input: Parallel data input 1
		.D2  (dac2_l[i]), // 1-bit input: Parallel data input 2
		.SR  (1'b0)  // 1-bit input: Active High Async Reset
		);
			
		OBUFDS dac2_data_obufds (
		.O   (dac2_data_p[i]),   // 1-bit output: Diff_p output (connect directly to top-level port)
		.OB  (dac2_data_n[i]), // 1-bit output: Diff_n output (connect directly to top-level port)
		.I   (dac2_data[i])    // 1-bit input: Buffer input
		);
	
	
		end
	endgenerate
`else
	ODDR #(
	.DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
	.INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
	.SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
	) dac1_dci_oddr (
		.Q(dac1_dci),   // 1-bit DDR output
		.C(dac1_dco_buf),   // 1-bit clock input
		.CE(1'b1), // 1-bit clock enable input
		.D1(1'b1), // 1-bit data input (positive edge)
		.D2(1'b0), // 1-bit data input (negative edge)
		.R(1'b0),   // 1-bit reset
		.S(1'b0)    // 1-bit set
	);

	ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
		.INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
		.SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
	) dac2_dci_oddr (
		.Q(dac2_dci),   // 1-bit DDR output
		.C(dac2_dco_buf),   // 1-bit clock input
		.CE(1'b1), // 1-bit clock enable input
		.D1(1'b1), // 1-bit data input (positive edge)
		.D2(1'b0), // 1-bit data input (negative edge)
		.R(1'b0),   // 1-bit reset
		.S(1'b0)    // 1-bit set
	);
	
	
	genvar i;
	generate
		for (i = 0; i < 14; i = i + 1) begin:OBUFDS_DATAS
				
		ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
		.INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
		.SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
		) dac1_data_oddr (
			.Q(dac1_data[i]),   // 1-bit DDR output
			.C(dac1_dco_buf),   // 1-bit clock input
			.CE(1'b1), // 1-bit clock enable input
			.D1(dac1_h[i]), // 1-bit data input (positive edge)
			.D2(dac1_l[i]), // 1-bit data input (negative edge)
			.R(1'b0),   // 1-bit reset
			.S(1'b0)    // 1-bit set
		);
			
		OBUFDS dac1_data_obufds (
		.O   (dac1_data_p[i]),   // 1-bit output: Diff_p output (connect directly to top-level port)
		.OB  (dac1_data_n[i]), // 1-bit output: Diff_n output (connect directly to top-level port)
		.I   (dac1_data[i])    // 1-bit input: Buffer input
		);
		
		
		ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
		.INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
		.SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
		) dac2_data_oddr (
			.Q(dac2_data[i]),   // 1-bit DDR output
			.C(dac2_dco_buf),   // 1-bit clock input
			.CE(1'b1), // 1-bit clock enable input
			.D1(dac2_h[i]), // 1-bit data input (positive edge)
			.D2(dac2_l[i]), // 1-bit data input (negative edge)
			.R(1'b0),   // 1-bit reset
			.S(1'b0)    // 1-bit set
		);
			
		OBUFDS dac2_data_obufds (
		.O   (dac2_data_p[i]),   // 1-bit output: Diff_p output (connect directly to top-level port)
		.OB  (dac2_data_n[i]), // 1-bit output: Diff_n output (connect directly to top-level port)
		.I   (dac2_data[i])    // 1-bit input: Buffer input
		);
	
	
		end
	endgenerate

`endif
	
endmodule
