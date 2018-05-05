`timescale 1ns/1ns
`define WORD_SIZE 16    // data and address word size

`include "opcodes.v"

module cpu(
        input clk, 
        input reset_n,

	// Instruction memory interface
        output i_readM, 
        output i_writeM, 
        output [`WORD_SIZE-1:0] i_address, 
        inout [`WORD_SIZE-1:0] i_data, 

	// Data memory interface
        output d_readM, 
        output d_writeM, 
        output [`WORD_SIZE-1:0] d_address, 
        inout [`WORD_SIZE-1:0] d_data, 

        output [`WORD_SIZE-1:0] num_inst, 
        output [`WORD_SIZE-1:0] output_port, 
        output is_halted
);
   //===-------------------------------------------------------------------===//
   // CPU feature configurations
   //===-------------------------------------------------------------------===//

   // Configures whether RF self-forwards its WB result to be read in the same
   // cycle, by doing synchronous write in negative clock edge, achieving
   // 1/2-cycle earlier write.  This is done by flipping !clk to RF, and
   // bypassing WB dependence check in the hazard detection unit.
   parameter RF_SELF_FORWARDING = 1;

   // Datapath - control Unit
   wire        clk;
   wire        reset_n;
   wire        branch;
   wire        i_or_d;
   wire        valid_ex;
   wire        bubblify;
   wire        input_ready;
   wire [3:0]  opcode;
   wire [2:0]  inst_type;
   wire [5:0]  func_code;
   wire        reg_write, ir_write, output_write;
   wire [1:0]  reg_dst, reg_write_src;
   wire        alu_src_a;
   wire [1:0]  pc_src, alu_src_b;
   wire        alu_src_swap;
   wire [3:0]  alu_op;
   wire        halt_id;

   control_unit Control (.clk (clk),
			 .reset_n (reset_n),
			 .opcode (opcode),
			 .func_code (func_code),
                         .inst_type(inst_type),
                         .branch(branch),
			 .pc_src (pc_src),
			 .i_or_d (i_or_d),
			 .i_mem_read(i_mem_read),
			 .d_mem_read(d_mem_read),
			 .i_mem_write(i_mem_write),
			 .d_mem_write(d_mem_write),
			 .ir_write (ir_write),
			 .alu_op (alu_op),
			 .alu_src_a (alu_src_a),
			 .alu_src_b (alu_src_b),
			 .alu_src_swap (alu_src_swap),
			 .reg_write (reg_write),
			 .reg_write_src (reg_write_src),
			 .reg_dst (reg_dst),
			 .output_write (output_write),
			 .halt_id (halt_id)); 

   datapath #(.WORD_SIZE (`WORD_SIZE),
              .RF_SELF_FORWARDING(RF_SELF_FORWARDING)) 
   DP (
       .clk(clk),
       .reset_n (reset_n),
       .pc_src (pc_src),
       .i_or_d (i_or_d),
       .output_write (output_write),
       .alu_op (alu_op),
       .alu_src_a (alu_src_a),
       .alu_src_b (alu_src_b),
       .alu_src_swap (alu_src_swap),
       .reg_dst (reg_dst),
       .branch(branch),
       .i_mem_read (i_mem_read),
       .d_mem_read (d_mem_read),
       .i_mem_write (i_mem_write),
       .d_mem_write (d_mem_write),
       .reg_write (reg_write),
       .reg_write_src (reg_write_src),
       .halt_id(halt_id),
       .input_ready (input_ready),
       .valid_ex (valid_ex),
       .i_address (i_address),
       .d_address (d_address),
       .i_readM (i_readM),
       .d_readM (d_readM),
       .i_writeM (i_writeM),
       .d_writeM (d_writeM),
       .i_data (i_data),
       .d_data (d_data),
       .output_port (output_port),
       .opcode(opcode),
       .func_code (func_code),
       .inst_type (inst_type),
       .is_halted(is_halted),
       .num_inst (num_inst)
       );
endmodule
