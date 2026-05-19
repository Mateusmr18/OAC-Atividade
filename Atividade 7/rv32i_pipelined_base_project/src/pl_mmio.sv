// =============================================================================
// pl_mmio.sv
// Controlador de E/S Mapeada em Memoria -- DE2-115 (RV32I pipelined)
//
// Mapa de enderecos (byte address, word-aligned):
//   0x400  SW   [17:0]  read-only    18 chaves deslizantes
//   0x404  KEY  [3:0]   read-only     4 botoes push
//   0x408  LEDR [17:0]  write-only   18 LEDs vermelhos
//   0x40C  LEDG [8:0]   write-only    9 LEDs verdes
//   0x410  UART [31:0]  read/write    porta serial RS-232
//            LW  -> {22'b0, tx_busy, rx_ready, rx_data[7:0]}
//            SW  -> transmitir WriteData[7:0] via UART TX
//
// Selecao: alu_result[10] = 1 seleciona este modulo (enderecos 0x400-0x7FF).
// O periferico e selecionado por alu_result[4:2] dentro da janela MMIO.
//
// Leituras: combinatoriais; escritas em LED e UART: registradas em posedge clk.
// =============================================================================

`timescale 1ns / 1ps

module pl_mmio (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        MemWrite,
    input  logic        MemRead,
    input  logic [2:0]  addr,        // alu_result[4:2]
    input  logic [31:0] WriteData,

    input  logic [17:0] SW,
    input  logic [3:0]  KEY,

    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,

    output logic        UART_TXD,
    input  logic        UART_RXD,

    output logic [31:0] ReadData
);

    // -------------------------------------------------------------------------
    // Instancia da UART
    // -------------------------------------------------------------------------
    logic       tx_write;
    logic       tx_busy;
    logic [7:0] rx_data;
    logic       rx_valid;

    sc_uart #(
        .CLK_HZ (10_000_000),
        .BAUD   (9_600)
    ) uart_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_write (tx_write),
        .tx_data  (WriteData[7:0]),
        .tx_busy  (tx_busy),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .TXD      (UART_TXD),
        .RXD      (UART_RXD)
    );

    assign tx_write = MemWrite & (addr == 3'b100);

    // -------------------------------------------------------------------------
    // Flag rx_ready (sticky): set em rx_valid, clear em LW do endereco UART
    // -------------------------------------------------------------------------
    logic rx_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_ready <= 1'b0;
        else if (rx_valid)
            rx_ready <= 1'b1;
        else if (MemRead & (addr == 3'b100))
            rx_ready <= 1'b0;
    end

    // -------------------------------------------------------------------------
    // Mux de leitura (combinatorial)
    // -------------------------------------------------------------------------
    always_comb begin
        case (addr)
            3'b000:  ReadData = {14'b0, SW};
            3'b001:  ReadData = {28'b0, KEY};
            3'b100:  ReadData = {22'b0, tx_busy, rx_ready, rx_data};
            default: ReadData = 32'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Registradores de LED (escrita sincrona)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            LEDR <= 18'b0;
            LEDG <=  9'b0;
        end else if (MemWrite) begin
            case (addr)
                3'b010: LEDR <= WriteData[17:0];
                3'b011: LEDG <= WriteData[8:0];
                default: ;
            endcase
        end
    end

endmodule
