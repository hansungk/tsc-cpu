`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2018/04/06 15:53:03
// Design Name: 
// Module Name: datapath
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
`define WORD_SIZE 16

module datapath
  #(parameter WORD_SIZE = `WORD_SIZE)
   (input                      clk,
    input                      reset_n,
    input                      pc_write,
    input                      pc_write_cond,
    input [1:0]                pc_src,
    input                      i_or_d,
    input                      i_mem_write, 
    input                      d_mem_write, 
    input                      ir_write,
    input [3:0]                alu_op,
    input                      alu_src_a,
    input [1:0]                alu_src_b,
    input                      alu_src_swap, 
    input                      reg_write,
    input [1:0]                reg_write_src,
    input [1:0]                reg_dst,
    input                      output_write,

    inout [WORD_SIZE-1:0]      i_data,
    inout [WORD_SIZE-1:0]      d_data,

    input                      input_ready,
    output [WORD_SIZE-1:0]     i_address,
    output [WORD_SIZE-1:0]     d_address,
    output reg [WORD_SIZE-1:0] num_inst,
    output reg [WORD_SIZE-1:0] output_port,
    output [3:0]               opcode,
    output [5:0]               func_code);

   // Decoded info
   wire [1:0]                  rs, rt, rd;
   wire [7:0]                  imm;
   wire [11:0]                 target_addr;                    

   // register file
   wire [1:0]                  addr1, addr2, addr3;
   wire [WORD_SIZE-1:0]        data1, data2, writeData;

   // ALU
   wire [WORD_SIZE-1:0]        alu_temp_1, alu_temp_2; // operands before swap
   wire [WORD_SIZE-1:0]        alu_operand_1, alu_operand_2; // operands after swap
   wire [WORD_SIZE-1:0]        alu_result;

   // Stage latches
   reg [WORD_SIZE-1:0]         PC; // program counter
   reg [WORD_SIZE-1:0]         IR; // instruction register
   reg [WORD_SIZE-1:0]         MDR; // memory data register
   reg [WORD_SIZE-1:0]         A_ex, B_ex;
   reg [WORD_SIZE-1:0]         alu_out;

   ALU alu(.OP(alu_op),
           .A(alu_operand_1),
           .B(alu_operand_2),
           .Cin(1'b0),
           .C(alu_result)
           /*.Cout()*/);

   RF rf(.write(reg_write),
         .clk(clk),
         .reset_n(reset_n),
         .addr1(addr1),
         .addr2(addr2),
         .addr3(addr3),
         .data1(data1),
         .data2(data2),
         .data3(writeData));

   // IF stage
   // assign address = (i_or_d == 0) ? PC : alu_out;
   assign i_address = PC;
   assign d_address = alu_out;

   // ID stage
   assign opcode = IR[15:12];
   assign func_code = IR[5:0];
   assign rs = IR[11:10];
   assign rt = IR[9:8];
   assign rd = IR[7:6];
   assign imm = IR[7:0];
   assign target_addr = IR[11:0];
   assign addr1 = rs;
   assign addr2 = rt;
   
   // EX stage
   assign alu_temp_1 = (alu_src_a == `ALUSRCA_PC) ? PC :
                     /*(alu_src_a == `ALUSRCA_REG) ?*/ A_ex;
   assign alu_temp_2 = (alu_src_b == `ALUSRCB_ONE) ? 1 :
                     (alu_src_b == `ALUSRCB_REG) ? B_ex :
                     (alu_src_b == `ALUSRCB_IMM) ? {{8{imm[7]}}, imm} :
                     /*(alu_src_b == `ALUSRCB_ZERO) ?*/ 0;
   assign alu_operand_1 = alu_src_swap ? alu_temp_2 : alu_temp_1;
   assign alu_operand_2 = alu_src_swap ? alu_temp_1 : alu_temp_2;

   // MEM stage
   assign d_data = d_mem_write ? B_ex : {WORD_SIZE{1'bz}};

   // WB stage
   assign addr3 = (reg_dst == `REGDST_RT) ? rt :
                  (reg_dst == `REGDST_RD) ? rd :
                  /*(reg_dst == `REGDST_2) ?*/ 2'd2;
   assign writeData = (reg_write_src == `REGWRITESRC_IMM) ? {imm, 8'b0} :
                      (reg_write_src == `REGWRITESRC_REG) ? alu_out :
                      (reg_write_src == `REGWRITESRC_MEM) ? MDR :
                      /*(reg_write_src == `REGWRITESRC_PC) ?*/ PC;

   // Register transfers
   always @(posedge clk) begin
      if (reset_n == 0) begin
         PC <= {WORD_SIZE{1'b0}};
         IR <= {WORD_SIZE{1'b0}};
         // maybe set output_port to initially float
         output_port <= {WORD_SIZE{1'bz}};
      end
      else begin
         // unconditional latches
         alu_out <= alu_result;
         A_ex <= data1;
         B_ex <= data2;

         // instruction register
         //
         // TODO: stall when input_ready does not turn on in given time
         if (ir_write) begin
            IR <= i_data;
         end

         // memory data register
         // if (input_ready) begin
            MDR <= d_data;
         // end
         
         // output port assertion
         if (output_write == 1) begin
            output_port <= data1;
         end

         // PC update
         if (pc_write || (pc_write_cond && (alu_result != 0))) begin
            case (pc_src)
              `PCSRC_SEQ: PC <= alu_result;
              `PCSRC_JUMP: PC <= {PC[15:12], target_addr};
              `PCSRC_BRANCH: PC <= alu_out;
              `PCSRC_REG: PC <= data1; // *before* B_ex
            endcase
         end
      end
   end
endmodule
