`timescale 1ns/1ns
`define WORD_SIZE 16    // data and address word size

`include "constants.v"
`include "opcodes.v"

module cpu(
    input                    clk, 
    input                    reset_n,

    // Instruction memory interface
    output                   i_readM, 
    output                   i_writeM, 
    output [`WORD_SIZE-1:0]  i_address, 
    inout [4*`WORD_SIZE-1:0] i_dataM,
    input                    i_readyM,
    input                    i_input_readyM,

    // Data memory interface
    output                   d_readM, 
    output                   d_writeM, 
    output [`WORD_SIZE-1:0]  d_address, 
    inout [4*`WORD_SIZE-1:0] d_dataM,
    input                    d_readyM,
    input                    d_input_readyM,
    input                    d_doneM,
    input                    d_next_ready,
    input [`WORD_SIZE-1:0]   d_written_address,

    output [`WORD_SIZE-1:0]  num_inst, 
    output [`WORD_SIZE-1:0]  num_branch, 
    output [`WORD_SIZE-1:0]  num_branch_miss, 
    output [`WORD_SIZE-1:0]  output_port, 
    output                   is_halted
);
   //===-------------------------------------------------------------------===//
   // CPU feature configurations
   //===-------------------------------------------------------------------===//

   // Configures whether RF self-forwards its WB result to be read in the same
   // cycle, by doing synchronous write in negative clock edge.  This is done by
   // flipping !clk to RF, and bypassing WB dependence check in the hazard
   // detection unit.
   parameter RF_SELF_FORWARDING = 1;

   // Configures whether data forwarding is enabled.
   // Currently not working with RF_SELF_FORWARDING disabled (SWD-LWD).
   parameter DATA_FORWARDING = 1;

   // Selects branch predictor.
   //
   // Set to one of the following constants:
   // BPRED_NONE: always stall on branch
   // BPRED_ALWAYS_UNTAKEN: always untaken, no BTB, flush-on-miss
   // BPRED_ALWAYS_TAKEN: always taken, BTB without BHT, flush-on-miss
   // BPRED_SATURATION_COUNTER: saturation counter using 2-bit BHT
   // BPRED_HYSTERESIS_COUNTER: hysteresis counter using 2-bit BHT
   parameter BRANCH_PREDICTOR = `BPRED_HYSTERESIS_COUNTER;

   // Eanble cached implementation.  Set zero for baseline.
   parameter CACHE = 1;

   // Datapath - control Unit
   wire        clk;
   wire        reset_n;
   wire        branch;
   wire        i_or_d;
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
   wire        i_ready;
   wire        i_readyC;
   wire        d_ready;
   wire        d_readyC;
   wire        i_read;
   wire        d_read;
   wire        i_readM_from_cache;
   wire        d_readM_from_cache;
   wire        i_writeM_from_cache;
   wire        d_wirteM_from_cache;
   wire        i_write;
   wire        d_write;
   wire [`WORD_SIZE-1:0] i_data; 
   wire [`WORD_SIZE-1:0] d_data;
   wire [`WORD_SIZE-1:0] i_dataC; 
   wire [`WORD_SIZE-1:0] d_dataC;

   // Switch connection to data ports between cache or direct to memory
   assign i_ready = CACHE ? i_readyC : i_readyM;
   assign d_ready = CACHE ? d_readyC : d_readyM;
   assign i_readM = CACHE ? i_readM_from_cache : i_read;
   assign d_readM = CACHE ? d_readM_from_cache : d_read;
   assign i_writeM = CACHE ? i_writeM_from_cache : i_write;
   assign d_writeM = CACHE ? d_writeM_from_cache : d_write;
   assign i_data  = CACHE ? i_dataC  : i_dataM;
   assign d_data  = CACHE ? d_dataC  : d_dataM;

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
              .RF_SELF_FORWARDING(RF_SELF_FORWARDING),
              .DATA_FORWARDING(DATA_FORWARDING),
              .BRANCH_PREDICTOR(BRANCH_PREDICTOR))
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
       // .i_mem_read (i_mem_read),
       .d_mem_read (d_mem_read),
       .i_mem_write (i_mem_write),
       .d_mem_write (d_mem_write),
       .i_ready (i_ready),
       .d_ready (d_ready),
       .i_readyM (i_readyM),
       .d_written_address (d_written_address),
       .reg_write (reg_write),
       .reg_write_src (reg_write_src),
       .halt_id(halt_id),
       .input_ready (input_ready),
       .i_address (i_address),
       .d_address (d_address),
       .i_read (i_read),
       .d_read (d_read),
       .i_write (i_write),
       .d_write (d_write),
       .i_data (i_data),
       .d_data (d_data),
       .output_port (output_port),
       .opcode(opcode),
       .func_code (func_code),
       .inst_type (inst_type),
       .is_halted(is_halted),
       .num_inst (num_inst),
       .num_branch (num_branch),
       .num_branch_miss (num_branch_miss)
       );

   cache #(.WORD_SIZE(`WORD_SIZE))
   ICache (.clk(clk),
          .reset_n(reset_n),
          .readC(i_read),
          .writeC(i_write),
          .readyM(i_readyM),
          .input_readyM(i_input_readyM),
          .doneM(i_doneM),
          .address(i_address),
          .data(i_dataC),
          .dataM(i_dataM),
          .readM(i_readM_from_cache),
          .writeM(i_writeM_from_cache),
          .readyC(i_readyC)
          );

   cache #(.WORD_SIZE(`WORD_SIZE))
   DCache (.clk(clk),
          .reset_n(reset_n),
          .readC(d_read),
          .writeC(d_write),
          .readyM(d_readyM),
          .input_readyM(d_input_readyM),
          .doneM(d_doneM),
          .address(d_address),
          .data(d_dataC),
          .dataM(d_dataM),
          .readM(d_readM_from_cache),
          .writeM(d_writeM_from_cache),
          .readyC(d_readyC)
          );
endmodule
