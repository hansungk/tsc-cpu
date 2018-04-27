`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: SNU
// Engineer: Hansung Kim 2014-16824
// 
// Create Date: 2018/03/23 17:54:02
// Design Name: 
// Module Name: RF
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


module RF(
    input         write,
    input         clk,
    input         reset_n,
    input [1:0]   addr1,
    input [1:0]   addr2,
    input [1:0]   addr3,
    input [15:0]  data3,
    output [15:0] data1,
    output [15:0] data2
    );

   // Registers, represented as a 2d array.
   // 4 registers are needed for 2-bit address.
   reg [15:0] regs [3:0];

   // Reset operation.
   //
   // Set all registers to zero whenever reset_n transitions to 0.
   // (Assumes asynchronous reset.)
   always @(negedge reset_n) begin
   	  regs[0] <= 16'h0;
   	  regs[1] <= 16'h0;
   	  regs[2] <= 16'h0;
   	  regs[3] <= 16'h0;
   end

   // Read operation.
   assign data1 = regs[addr1];
   assign data2 = regs[addr2];

   // Write operation.
   always @(posedge clk) begin
	  if (write == 1) begin
		 regs[addr3] <= data3;
	  end
   end
endmodule
