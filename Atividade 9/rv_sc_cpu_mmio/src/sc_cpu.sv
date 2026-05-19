// =============================================================================
// sc_cpu.sv
// Single-cycle RISC-V CPU
//
// Bundles the main control unit (sc_control) and the datapath (sc_datapath)
// into a single CPU module.
//
// Supported instructions:
//   add  sub  and  or  slt   (R-type, opcode 0110011)
//   lw                       (I-type, opcode 0000011)
//   sw                       (S-type, opcode 0100011)
//   beq                      (B-type, opcode 1100011)
// =============================================================================

`timescale 1ns / 1ps

module sc_cpu (
    input  logic        clk,
    input  logic        rst_n,    // active-low asynchronous reset

    // Observability
    output logic [31:0] PC,

    // Memory-mapped I/O ports (DE2-115)
    input  logic [17:0] SW,       // slide switches (read-only)
    input  logic [3:0]  KEY_IO,   // push buttons   (read-only, KEY[3:1] - KEY[0] is rst_n)
    output logic [17:0] LEDR,     // red LEDs        (write-only)
    output logic [8:0]  LEDG,     // green LEDs      (write-only)
    // RS-232 serial (UART)
    output logic        UART_TXD, // RS-232 transmit pin
    input  logic        UART_RXD  // RS-232 receive  pin
);

    // -------------------------------------------------------------------------
    // Control signals
    // -------------------------------------------------------------------------
    logic [6:0] opcode;
    logic       ALUSrc;
    logic       MemtoReg;
    logic       RegWrite;
    logic       MemRead;
    logic       MemWrite;
    logic       Branch;
    logic [1:0] ALUOp;

    // -------------------------------------------------------------------------
    // Control Unit
    // -------------------------------------------------------------------------
    sc_control ctrl (
        .Opcode   (opcode),
        .ALUSrc   (ALUSrc),
        .MemtoReg (MemtoReg),
        .RegWrite (RegWrite),
        .MemRead  (MemRead),
        .MemWrite (MemWrite),
        .Branch   (Branch),
        .ALUOp    (ALUOp)
    );

    // -------------------------------------------------------------------------
    // Datapath
    // -------------------------------------------------------------------------
    sc_datapath datapath (
        .clk       (clk),
        .rst_n     (rst_n),
        .ALUSrc    (ALUSrc),
        .MemtoReg  (MemtoReg),
        .RegWrite  (RegWrite),
        .MemRead   (MemRead),
        .MemWrite  (MemWrite),
        .Branch    (Branch),
        .ALUOp     (ALUOp),
        .Opcode    (opcode),
        .PC        (PC),
        .SW        (SW),
        .KEY       (KEY_IO),
        .LEDR      (LEDR),
        .LEDG      (LEDG),
        .UART_TXD  (UART_TXD),
        .UART_RXD  (UART_RXD)
    );

endmodule
