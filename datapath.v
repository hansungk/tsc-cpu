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
    input                      bubblify,
    input                      flush,

    // IF constrol signals
    input                      ir_write,

    // ID control signals
    input                      output_write,

    // EX control signals
    input [3:0]                alu_op,
    input                      alu_src_a,
    input [1:0]                alu_src_b,
    input                      alu_src_swap, 
    input [1:0]                reg_dst, // resolved in ID, only saved now

    // MEM control signals
    input                      i_mem_read, 
    input                      d_mem_read, 
    input                      i_mem_write,
    input                      d_mem_write, 

    // WB control signals
    input                      reg_write,
    input [1:0]                reg_write_src,

    input                      incr_num_inst,

    inout [WORD_SIZE-1:0]      i_data,
    inout [WORD_SIZE-1:0]      d_data,

    input                      input_ready,
    output reg                 valid_ex,
    output [WORD_SIZE-1:0]     i_address,
    output [WORD_SIZE-1:0]     d_address,
    output reg [WORD_SIZE-1:0] output_port,
    output [3:0]               opcode,
    output [5:0]               func_code,
    output [2:0]               inst_type,
    output [WORD_SIZE-1:0]     num_inst
);

   // Decoded info
   wire [1:0]           rs, rt, rd;
   wire [7:0]           imm;
   wire [11:0]          target_addr;                    

   // register file
   wire [1:0]           addr1, addr2, addr3;
   wire [WORD_SIZE-1:0] data1, data2, writeData;

   // ALU
   wire [WORD_SIZE-1:0] alu_temp_1, alu_temp_2; // operands before swap
   wire [WORD_SIZE-1:0] alu_operand_1, alu_operand_2; // operands after swap
   wire [WORD_SIZE-1:0] alu_result;

   ////////////////////////
   // Pipeline registers //
   ////////////////////////
   // don't forget to reset

   // unconditional latches
   reg [WORD_SIZE-1:0]  pc, pc_id, pc_ex, pc_mem, pc_wb; // program counter
   reg [WORD_SIZE-1:0]  npc_id; // PC + 4 at IF/ID
   reg [WORD_SIZE-1:0]  npc_ex; // PC + 4 at ID/EX
   reg [WORD_SIZE-1:0]  inst_type_ex, inst_type_mem, inst_type_wb;
   wire [WORD_SIZE-1:0] ir; // instruction register, bound to separate module
   reg [WORD_SIZE-1:0]  MDR_wb; // memory data register
   reg [WORD_SIZE-1:0]  rt_ex; // for reg_dst
   reg [WORD_SIZE-1:0]  rd_ex; // for reg_dst
   reg [WORD_SIZE-1:0]  a_ex, b_ex, b_mem;
   reg [WORD_SIZE-1:0]  alu_out_mem, alu_out_wb;
   reg [WORD_SIZE-1:0]  write_reg_mem, write_reg_wb;
   reg [WORD_SIZE-1:0]  imm_signed_ex, imm_signed_mem, imm_signed_wb;

   // debug purpose: which inst # is being passed through this stage?
   // num_inst_if effectively means "number of instructions fetched"
   reg [WORD_SIZE-1:0]  num_inst_if, num_inst_id, num_inst_ex;
   assign num_inst = num_inst_ex;

   // control signal latches
   reg                  valid_mem, valid_wb; // valid_ex already declared
   reg [3:0]            alu_op_ex;
   reg                  alu_src_a_ex;
   reg [1:0]            alu_src_b_ex;
   reg                  alu_src_swap_ex;
   reg [1:0]            reg_dst_ex;
   reg                  i_mem_read_ex, i_mem_read_mem;
   reg                  d_mem_read_ex, d_mem_read_mem;
   reg                  i_mem_write_ex, i_mem_write_mem;
   reg                  d_mem_write_ex, d_mem_write_mem;
   reg                  reg_write_ex, reg_write_mem, reg_write_wb;
   reg                  reg_write_src_ex, reg_write_src_mem, reg_write_src_wb;

   /////////////////////////
   // Module declarations //
   /////////////////////////

   ALU alu(.OP(alu_op_ex),
           .A(alu_operand_1),
           .B(alu_operand_2),
           .Cin(1'b0),
           .C(alu_result)
           /*.Cout()*/);

   // Register file
   RF rf(.clk(clk),
         .reset_n(reset_n),
         .write(reg_write_wb),
         .addr1(addr1),
         .addr2(addr2),
         .addr3(addr3),
         .data1(data1),
         .data2(data2),
         .data3(writeData));

   // Instruction register
   IR ir_module(.clk(clk),
                .nop(flush || !reset_n),
                .write(ir_write),
                .write_data(i_data),
                .inst(ir));

   // Instruction Type Decoder
   InstTypeDecoder itd(.opcode(opcode),
                       .func_code(func_code),
                       .inst_type(inst_type));

   ///////////////////////
   // Per-stage wirings //
   ///////////////////////

   // IF stage
   assign i_address = pc;
   assign d_address = alu_out_mem;

   // ID stage
   assign opcode = ir[15:12];
   assign func_code = ir[5:0];
   assign rs = ir[11:10];
   assign rt = ir[9:8];
   assign rd = ir[7:6];
   assign imm = ir[7:0];
   assign target_addr = ir[11:0];
   assign addr1 = rs;
   assign addr2 = rt;
   
   // EX stage
   assign alu_temp_1 = (alu_src_a_ex == `ALUSRCA_PC) ? pc :
                     /*(alu_src_a_ex == `ALUSRCA_REG) ?*/ a_ex;
   assign alu_temp_2 = (alu_src_b_ex == `ALUSRCB_ONE) ? 1 :
                     (alu_src_b_ex == `ALUSRCB_REG) ? b_ex :
                     (alu_src_b_ex == `ALUSRCB_IMM) ? imm_signed_ex :
                     /*(alu_src_b_ex == `ALUSRCB_ZERO) ?*/ 0;
   assign alu_operand_1 = alu_src_swap_ex ? alu_temp_2 : alu_temp_1;
   assign alu_operand_2 = alu_src_swap_ex ? alu_temp_1 : alu_temp_2;

   // MEM stage
   assign d_data = d_mem_write ? b_ex : {WORD_SIZE{1'bz}};

   // WB stage
   assign addr3 = write_reg_wb;
   assign writeData = (reg_write_src_wb == `REGWRITESRC_IMM) ? imm_signed_wb : // LHI
                      (reg_write_src_wb == `REGWRITESRC_REG) ? alu_out_wb :
                      (reg_write_src_wb == `REGWRITESRC_MEM) ? MDR_wb :
                      /*(reg_write_src_wb == `REGWRITESRC_PC) ?*/ pc_wb;

   ////////////////////////
   // Register transfers //
   ////////////////////////

   always @(posedge clk) begin
      if (reset_n == 0) begin
         // reset all pipeline registers and control signal registers
         // to zero to prevent any initial output
         pc <= 0;
         npc_id <= 0;
         npc_ex <= 0;
         valid_ex <= 0;
         MDR_wb <= 0;
         a_ex <= 0;
         b_ex <= 0;
         b_mem <= 0;
         alu_out_mem <= 0;
         // maybe set output_port to initially float
         output_port <= {WORD_SIZE{1'bz}};
         num_inst_if <= 0;
         num_inst_id <= 0;
         num_inst_ex <= 0;
      end
      else begin
         // ----------------------
         // Pipeline stage latches
         // ----------------------

         // PC update
         if (pc_write) begin
            pc <= (pc_src == `PCSRC_JUMP) ? {pc[15:12], target_addr} :
                  pc + 1; // TODO: else
         end

         // IF stage
         npc_id <= pc + 1; // adder for PC
         pc_id <= pc;
         num_inst_id <= num_inst_if;

         // ID stage
         npc_ex <= npc_id;
         pc_ex <= pc_id;
         num_inst_ex <= num_inst_id;
         inst_type_ex <= inst_type;
         a_ex <= data1;
         b_ex <= data2;
         rt_ex <= rt;
         rd_ex <= rd;
         imm_signed_ex <= {{8{imm[7]}}, imm};

         // EX stage
         pc_mem <= pc_ex;
         inst_type_mem <= inst_type_ex;
         alu_out_mem <= alu_result;
         write_reg_mem <= (reg_dst == `REGDST_RT) ? rt_ex :
                          (reg_dst == `REGDST_RD) ? rd_ex :
                          /*(reg_dst == `REGDST_2) ?*/ 2'd2;
         imm_signed_mem <= imm_signed_ex;

         // MEM stage
         pc_wb <= pc_mem;
         inst_type_wb <= inst_type_mem;
         MDR_wb <= d_data;
         write_reg_wb <= write_reg_mem;
         imm_signed_wb <= imm_signed_mem;

         // ----------------------
         // Control signal latches
         // ----------------------

         // EX stage (EX+MEM+WB)
         // if hazard detected, insert bubbles into pipeline
         if (bubblify) begin
            valid_ex <= 0;
            alu_op_ex <= 0;
            alu_src_a_ex <= 0;
            alu_src_b_ex <= 0;
            alu_src_swap_ex <= 0;
            reg_dst_ex <= 0;
            i_mem_read_ex <= 0;
            d_mem_read_ex <= 0;
            i_mem_write_ex <= 0;
            d_mem_write_ex <= 0;
            reg_write_ex <= 0;
            reg_write_src_ex <= 0;
         end
         else begin
            valid_ex <= 1;
            alu_op_ex <= alu_op;
            alu_src_a_ex <= alu_src_a;
            alu_src_b_ex <= alu_src_b;
            alu_src_swap_ex <= alu_src_swap;
            reg_dst_ex <= reg_dst;
            i_mem_read_ex <= i_mem_read;
            d_mem_read_ex <= d_mem_read;
            i_mem_write_ex <= i_mem_write;
            d_mem_write_ex <= d_mem_write;
            reg_write_ex <= reg_write;
            reg_write_src_ex <= reg_write_src;
         end

         // MEM stage (MEM+WB)
         valid_mem <= valid_ex;
         i_mem_read_mem <= i_mem_read_ex;
         d_mem_read_mem <= d_mem_read_ex;
         i_mem_write_mem <= i_mem_write_ex;
         d_mem_write_mem <= d_mem_write_ex;
         reg_write_mem <= reg_write_ex;
         reg_write_src_mem <= reg_write_src_ex;

         // WB stage (WB)
         valid_wb <= valid_mem;
         reg_write_wb <= reg_write_mem;
         reg_write_src_wb <= reg_write_src_mem;

         // output port assertion
         if (output_write == 1) begin
            output_port <= data1;
         end

         // num_inst update
         //
         // increased num_inst_if will propagate into the pipeline,
         // setting the right value for each stage
         if (incr_num_inst) begin
            num_inst_if <= num_inst_if + 1;
         end
      end
   end
endmodule
