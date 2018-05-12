`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 2014-16824
// Engineer: Hansung Kim
// 
// Create Date: 2018/03/17 04:52:34
// Design Name: 
// Module Name: ALU
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

`include "constants.v"

module ALU(
    input [3:0] OP,
    input [15:0] A,
    input [15:0] B,
    input Cin,
    output reg [15:0] C,
    output reg Cout
    );

    // Intermediate value to store the full 17-bit result of arithmetic operations.
    reg [16:0] res;

   always @* begin
      Cout = 0;
      
      case (OP)
        `OP_ADD: begin
           res = A + B + Cin;
           C = res[15:0];
           Cout = res[16];
        end
        `OP_SUB: begin
           res = A - B - Cin;
           C = res[15:0];
           Cout = res[16];
        end
        `OP_ID: begin
           C = A;
        end
        `OP_NAND: begin
           C = ~(A & B);
        end
        `OP_NOR: begin
           C = ~(A | B);
        end
        `OP_XNOR: begin
           C = A ~^ B;
        end
        `OP_NOT: begin
           C = ~A;
        end
        `OP_AND: begin
           C = A & B;
        end
        `OP_OR: begin
           C = A | B;
        end
        `OP_XOR: begin
           C = A ^ B;
        end
        `OP_EQ: begin
           C = A == B;
        end
        `OP_ARS: begin
           C = A >> 1;
           // preserve sign
           C[15] = A[15];
        end
        `OP_GT: begin
           C = $signed(A) > $signed(B);
        end
        `OP_NE: begin
           C = A != B;
        end
        `OP_ALS: begin
           C = A << 1;
        end
        `OP_LT: begin
           C = $signed(A) < $signed(B);
        end
        default: begin
           // Unreachable, mark everything with 1
           C = -1;
           Cout = 1;
        end
      endcase
   end
endmodule
