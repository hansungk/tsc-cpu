`define PERIOD1 100
`define READ_DELAY 30 // delay before memory data is ready
`define WRITE_DELAY 30 // delay in writing to memory
`define MEMORY_SIZE 256 // size of memory is 2^8 words (reduced size)
`define WORD_SIZE 16 // instead of 2^16 words to reduce memory
                        
`define NUM_TEST 56
`define TESTID_SIZE 5

// ALU operations

// Arithmetic
`define	OP_ADD	4'b0000
`define	OP_SUB	4'b0001
//  Bitwise Boolean operation
`define	OP_ID	4'b0010
`define	OP_NAND	4'b0011
`define	OP_NOR	4'b0100
`define	OP_XNOR	4'b0101
`define	OP_NOT	4'b0110
`define	OP_AND	4'b0111
`define	OP_OR	4'b1000
`define	OP_XOR	4'b1001
// Shifting
`define	OP_EQ	4'b1010
`define	OP_ARS	4'b1011
`define	OP_GT	4'b1100
`define	OP_NE	4'b1101
`define	OP_ALS	4'b1110
`define	OP_LT	4'b1111

// Instruction types
`define INSTTYPE_RTYPE 4'd0
`define INSTTYPE_LOAD 4'd1
`define INSTTYPE_STORE 4'd2
`define INSTTYPE_BRANCH 4'd3
`define INSTTYPE_JUMP 4'd4
`define INSTTYPE_OUTPUT 4'd5
`define INSTTYPE_NOP 4'd6

// MUX selectors

`define PCSRC_SEQ 0
`define PCSRC_JUMP 1
`define PCSRC_BRANCH 2
`define PCSRC_REG 3

`define ALUSRCA_PC 0
`define ALUSRCA_REG 1

`define ALUSRCB_ONE 0
`define ALUSRCB_REG 1
`define ALUSRCB_IMM 2
`define ALUSRCB_ZERO 3

`define REGWRITESRC_IMM 0
`define REGWRITESRC_ALU 1
`define REGWRITESRC_MEM 2
`define REGWRITESRC_PC 3

`define REGDST_RT 0
`define REGDST_RD 1
`define REGDST_2 2

`define FORWARD_SRC_MEM 0
`define FORWARD_SRC_WB 1
`define FORWARD_SRC_RF 2
