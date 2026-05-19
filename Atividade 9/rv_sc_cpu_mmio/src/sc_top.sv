// =============================================================================
// sc_top.sv
// Top-level module - single-cycle RISC-V with Memory-Mapped I/O
//
// Hierarchy:
//   sc_top
//     pll_10mhz       - ALTPLL: 50 MHz → 10 MHz
//     sc_cpu          - RISC-V CPU (control + datapath)
//       sc_control
//       sc_datapath
//         sc_imem, sc_regfile, sc_sign_ext
//         sc_alu_ctrl, sc_alu
//         sc_dmem
//         sc_mmio     - memory-mapped I/O (SW, KEY, LEDR, LEDG, UART)
//           sc_uart   - RS-232 UART 8N1 (9600 baud @ 10 MHz)
//
// Target board: DE2-115 (Intel Cyclone IV E, 50 MHz clock)
//   CLOCK_50    -> clk
//   KEY[0]      -> rst_n      (active-low push-button reset)
//   KEY[3:1]    -> KEY_IO     (push buttons available to software via MMIO)
//   SW[17:0]    -> SW         (slide switches, read via MMIO @ 0x400)
//   LEDR[17:0]  <- LEDR       (red LEDs,       write via MMIO @ 0x408)
//   LEDG[8:0]   <- LEDG       (green LEDs,     write via MMIO @ 0x40C)
//   UART_TXD    <- UART_TXD   (RS-232 TX,      write via MMIO @ 0x410)
//   UART_RXD    -> UART_RXD   (RS-232 RX,      read  via MMIO @ 0x410)
//
// Clock domain
//   clk (50 MHz, CLOCK_50 pin) → pll_10mhz → clk_cpu (10 MHz)
//   The CPU reset is held low until the PLL asserts locked, ensuring
//   the CPU never starts on a glitchy or out-of-frequency clock.
//
// MMIO address map (byte addresses, word-aligned):
//   0x400  SW[17:0]   read-only   18 slide switches
//   0x404  KEY[3:0]   read-only    4 push buttons  (KEY[0] wired to rst_n above)
//   0x408  LEDR[17:0] write-only  18 red LEDs
//   0x40C  LEDG[8:0]  write-only   9 green LEDs
//   0x410  UART       read/write  RS-232 serial (8N1, 9600 baud)
//            LW  0x410 -> {22'b0, tx_busy, rx_ready, rx_data[7:0]}
//            SW  0x410 -> transmit WriteData[7:0] via UART TX
// =============================================================================

`timescale 1ns / 1ps

module sc_top (
    input  logic        clk,          // CLOCK_50 (50 MHz board clock)
    output logic [31:0] PC,           // current PC (SignalTap / testbench)

    // Slide switches
    input  logic [17:0] SW,           // SW[17:0]

    // Push buttons
    input  logic [3:0]  KEY,          // KEY[3:0]

    // LEDs
    output logic [17:0] LEDR,         // red LEDs
    output logic [8:0]  LEDG,         // green LEDs

    // RS-232 serial (connected to MAX232 on DE2-115)
    output logic        UART_TXD,     // RS-232 TX (FPGA pin B25)
    input  logic        UART_RXD      // RS-232 RX (FPGA pin C25)
);

    // -------------------------------------------------------------------------
    // PLL — 50 MHz → 10 MHz
    // -------------------------------------------------------------------------
    logic clk_cpu;      // 10 MHz clock fed to the CPU
    logic pll_locked;   // high once PLL output is stable

    pll_10mhz pll_inst (
        .inclk0 (clk),
        .c0     (clk_cpu),
        .locked (pll_locked)
    );

    // -------------------------------------------------------------------------
    // Reset — held active until both the user button is released AND the PLL
    // has locked.  This prevents the CPU from running on a glitchy clock during
    // the PLL acquisition window (~1 ms after power-on / FPGA configuration).
    // -------------------------------------------------------------------------
    logic rst_cpu_n;
    assign rst_cpu_n = KEY[0] & pll_locked;

    sc_cpu cpu (
        .clk      (clk_cpu),
        .rst_n    (rst_cpu_n),
        .PC       (PC),
        .SW       (SW),
        .KEY_IO   (KEY),
        .LEDR     (LEDR),
        .LEDG     (LEDG),
        .UART_TXD (UART_TXD),
        .UART_RXD (UART_RXD)
    );

endmodule
