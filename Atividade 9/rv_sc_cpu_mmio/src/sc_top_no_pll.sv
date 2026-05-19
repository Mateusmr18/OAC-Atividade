// =============================================================================
// sc_top_no_pll.sv
// Top-level alternativo — RV32I Single-Cycle MMIO sem PLL (DE2-115)
//
// CLOCK_50 (50 MHz) alimenta a CPU diretamente, sem o bloco pll_10mhz.
// Use este arquivo para testes de síntese/timing sem depender do IP de PLL.
//
// Hierarquia:
//   sc_top_no_pll
//     sc_cpu
//       sc_control
//       sc_datapath
//         sc_imem, sc_regfile, sc_sign_ext
//         sc_alu_ctrl, sc_alu
//         sc_dmem
//         sc_mmio
//           sc_uart
//
// Diferenças em relação a sc_top.sv:
//   - Sem instância pll_10mhz
//   - clk_cpu = clk (50 MHz direto)
//   - rst_n derivado de KEY[0] sem aguardar pll_locked
//   - KEY[3:0] agrupa todos os botões incluindo o reset
//
// Pinagem DE2-115:
//   clk        (PIN_Y2)          : clock de 50 MHz
//   KEY[0]     (PIN_M23)         : reset ativo-baixo
//   KEY[1]     (PIN_M21)         : botão disponível via MMIO 0x404
//   KEY[2]     (PIN_N21)         : botão disponível via MMIO 0x404
//   KEY[3]     (PIN_R24)         : botão disponível via MMIO 0x404
//   SW[17:0]   (vários pinos)    : chaves — MMIO 0x400
//   LEDR[17:0] (vários pinos)    : LEDs vermelhos — MMIO 0x408
//   LEDG[8:0]  (vários pinos)    : LEDs verdes — MMIO 0x40C
//   UART_TXD   (PIN_G9)          : RS-232 TX — MMIO 0x410
//   UART_RXD   (PIN_G12)         : RS-232 RX — MMIO 0x410
//
// ATENÇÃO — UART a 50 MHz:
//   sc_mmio instancia sc_uart com CLK_HZ = 10_000_000 (hardcoded).
//   A 50 MHz o divisor de baud estará errado por fator 5; a comunicação
//   serial NÃO funcionará corretamente. Para corrigir, altere sc_mmio.sv:
//     .CLK_HZ(50_000_000)
// =============================================================================

`timescale 1ns / 1ps

module sc_top_no_pll (
    input  logic        clk,          // PIN_Y2   — 50 MHz
    input  logic [3:0]  KEY,          // KEY[0]=reset ativo-baixo (PIN_M23)
                                      // KEY[3:1]=botões MMIO
    input  logic [17:0] SW,           // chaves deslizantes — MMIO 0x400
    output logic [31:0] PC,           // PC atual (SignalTap / debug)
    output logic [17:0] LEDR,         // LEDs vermelhos — MMIO 0x408
    output logic [8:0]  LEDG,         // LEDs verdes    — MMIO 0x40C
    output logic        UART_TXD,     // PIN_G9
    input  logic        UART_RXD      // PIN_G12
);

    // rst_n liberado imediatamente ao soltar KEY[0].
    // Sem PLL não há sinal locked para aguardar.
    logic rst_n;
    assign rst_n = KEY[0];

    // -------------------------------------------------------------------------
    // CPU single-cycle — clock direto de 50 MHz
    // -------------------------------------------------------------------------
    sc_cpu cpu (
        .clk      (clk),
        .rst_n    (rst_n),
        .PC       (PC),
        .SW       (SW),
        .KEY_IO   (KEY),
        .LEDR     (LEDR),
        .LEDG     (LEDG),
        .UART_TXD (UART_TXD),
        .UART_RXD (UART_RXD)
    );

endmodule
