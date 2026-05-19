// =============================================================================
// sc_control.sv
// Main Control Unit - single-cycle RISC-V (Section 4.4 - Patterson & Hennessy)
//
// Decodes the 7-bit opcode and asserts control signals for the datapath.
//
// Supported instructions:
//   R-type  (0110011): add, sub, and, or, slt
//   I-type  (0000011): lw
//   S-type  (0100011): sw
//   B-type  (1100011): beq
//
// Control signal summary:
//
//   Signal    | R-type | lw | sw | beq
//   ----------|--------|----|----|-----
//   ALUSrc    |   0    |  1 |  1 |  0    0=reg, 1=imm
//   MemtoReg  |   0    |  1 |  - |  -    0=ALU, 1=mem
//   RegWrite  |   1    |  1 |  0 |  0
//   MemRead   |   0    |  1 |  0 |  0
//   MemWrite  |   0    |  0 |  1 |  0
//   Branch    |   0    |  0 |  0 |  1
//   ALUOp[1]  |   1    |  0 |  0 |  0
//   ALUOp[0]  |   0    |  0 |  0 |  1
//
//   ALUOp encoding:
//     2'b00 = Load/Store (force ADD)
//     2'b01 = Branch     (force SUB)
//     2'b10 = R-type     (ALU Control decodes Funct3/Funct7)
// =============================================================================

`timescale 1ns / 1ps

module sc_control (
    input  logic [6:0] Opcode,
    output logic       ALUSrc,
    output logic       MemtoReg,
    output logic       RegWrite,
    output logic       MemRead,
    output logic       MemWrite,
    output logic       Branch,
    output logic [1:0] ALUOp
);

    localparam R_TYPE = 7'b0110011; // add, sub, and, or, slt
    localparam LOAD   = 7'b0000011; // lw
    localparam STORE  = 7'b0100011; // sw
    localparam BRANCH = 7'b1100011; // beq

    always_comb begin
        // Safe defaults: prevent accidental memory writes or register corruption
        // when an unrecognized opcode is encountered
        ALUSrc   = 1'b0;
        MemtoReg = 1'b0;
        RegWrite = 1'b0;
        MemRead  = 1'b0;
        MemWrite = 1'b0;
        Branch   = 1'b0;
        ALUOp    = 2'b00;

        case (Opcode)
            R_TYPE: begin
                ALUSrc   = 1'b0; // ALU operand B comes from register rs2
                MemtoReg = 1'b0; // Write-back data comes from ALU
                RegWrite = 1'b1; // Result is written into rd
                MemRead  = 1'b0;
                MemWrite = 1'b0;
                Branch   = 1'b0;
                ALUOp    = 2'b10; // ALU control decodes Funct3/Funct7
            end

            LOAD: begin
                ALUSrc   = 1'b1; // ALU operand B comes from sign-extended imm
                MemtoReg = 1'b1; // Write-back data comes from data memory
                RegWrite = 1'b1; // Load result written into rd
                MemRead  = 1'b1; // Read from data memory
                MemWrite = 1'b0;
                Branch   = 1'b0;
                ALUOp    = 2'b00; // ADD: compute address rs1 + imm
            end

            STORE: begin
                ALUSrc   = 1'b1; // ALU operand B comes from sign-extended imm
                MemtoReg = 1'b0; // Don't-care: no register write
                RegWrite = 1'b0; // Store does not write registers
                MemRead  = 1'b0;
                MemWrite = 1'b1; // Write to data memory
                Branch   = 1'b0;
                ALUOp    = 2'b00; // ADD: compute address rs1 + imm
            end

            BRANCH: begin
                ALUSrc   = 1'b0; // ALU operand B comes from register rs2
                MemtoReg = 1'b0; // Don't-care: no register write
                RegWrite = 1'b0; // Branch does not write registers
                MemRead  = 1'b0;
                MemWrite = 1'b0;
                Branch   = 1'b1; // Branch unit checks Zero flag
                ALUOp    = 2'b01; // SUB: subtract rs1 - rs2 to get Zero
            end

            default: ; // All signals remain at safe defaults (no operation)
        endcase
    end

endmodule
