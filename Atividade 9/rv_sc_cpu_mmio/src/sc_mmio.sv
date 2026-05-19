// =============================================================================
// sc_mmio.sv
// Memory-Mapped I/O controller - DE2-115 peripherals
//
// Address map (byte address, word-aligned):
//   0x400  SW   [17:0]  read-only    18 slide switches
//   0x404  KEY  [3:0]   read-only     4 push buttons
//   0x408  LEDR [17:0]  write-only   18 red LEDs
//   0x40C  LEDG [8:0]   write-only    9 green LEDs
//   0x410  UART  [31:0]  read/write    RS-232 serial port
//            LW  -> {22'b0, tx_busy, rx_ready, rx_data[7:0]}
//            SW  -> transmit WriteData[31:0] as 4 bytes, little-endian
//                   (byte 0 first, byte 3 last; tx_busy stays high until
//                    the last byte has been accepted by the UART)
//   0x414  CYCLE [31:0]  read-only    clock cycle counter (32 bits)
//
// Selection: alu_result[10] = 1 selects this module (addresses 0x400–0x7FF).
// The peripheral is chosen by alu_result[4:2] within the MMIO window.
//
// Reads are combinatorial; LED and UART writes are registered on posedge clk.
// LED registers and rx_ready clear to 0 on active-low asynchronous reset.
//
// rx_ready flag:
//   Set   : when the UART RX completes reception of a byte (rx_valid pulse).
//   Clear : when the CPU reads the UART address (MemRead & addr==3'b100),
//           or on reset.
//   This allows software to poll bit[8] of an LW to 0x410 to detect new data.
// =============================================================================

`timescale 1ns / 1ps

module sc_mmio (
    input  logic        clk,
    input  logic        rst_n,       // active-low asynchronous reset
    input  logic        MemWrite,    // 1 = write (SW instruction, already gated with mmio_sel)
    input  logic        MemRead,     // 1 = read  (LW instruction, already gated with mmio_sel)
    input  logic [2:0]  addr,        // alu_result[4:2]: selects peripheral

    input  logic [31:0] WriteData,   // data from rs2 (SW instruction)

    // Physical I/O — slide switches and push buttons
    input  logic [17:0] SW,
    input  logic [3:0]  KEY,

    // Physical I/O — LEDs
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,

    // Physical I/O — RS-232 serial
    output logic        UART_TXD,    // to MAX232 / DB9 TX
    input  logic        UART_RXD,    // from MAX232 / DB9 RX

    // Read data back to the CPU
    output logic [31:0] ReadData
);

    // -------------------------------------------------------------------------
    // UART instance
    // -------------------------------------------------------------------------
    logic       tx_write;   // one-cycle strobe: start TX
    logic       tx_busy;    // TX shift register active
    logic [7:0] rx_data;    // last received byte (held)
    logic       rx_valid;   // one-cycle pulse on new byte

    sc_uart #(
        .CLK_HZ (10_000_000),
        .BAUD   (9_600)
    ) uart_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_write (tx_write),
        .tx_data  (tx_byte),
        .tx_busy  (tx_busy),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .TXD      (UART_TXD),
        .RXD      (UART_RXD)
    );

    // -------------------------------------------------------------------------
    // 4-byte transmit sequencer (little-endian)
    //
    // When the CPU executes SW to 0x410, the 32-bit word is sent as 4 bytes:
    // byte[7:0] first, byte[31:24] last.  tx_word_busy stays high until the
    // last byte has been accepted by the UART shift register.
    // The CPU must wait for tx_busy == 0 (bit 9 of LW 0x410) before the next SW.
    // -------------------------------------------------------------------------
    logic [31:0] tx_word;       // latched 32-bit word being transmitted
    logic [1:0]  tx_byte_idx;   // current byte index (0 = LSB, 3 = MSB)
    logic        tx_word_busy;  // high while bytes remain to be sent
    logic [7:0]  tx_byte;       // current byte delivered to the UART

    always_comb begin
        case (tx_byte_idx)
            2'd0: tx_byte = tx_word[7:0];
            2'd1: tx_byte = tx_word[15:8];
            2'd2: tx_byte = tx_word[23:16];
            2'd3: tx_byte = tx_word[31:24];
        endcase
    end

    // UART write strobe: active while a byte is pending and UART is free
    assign tx_write = tx_word_busy & ~tx_busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_word      <= '0;
            tx_byte_idx  <= '0;
            tx_word_busy <= 1'b0;
        end else if (MemWrite && (addr == 3'b100) && !tx_word_busy) begin
            // CPU writes a new word: latch it and begin sequencing
            tx_word      <= WriteData;
            tx_byte_idx  <= 2'd0;
            tx_word_busy <= 1'b1;
        end else if (tx_word_busy && !tx_busy) begin
            // UART accepted the current byte (tx_write was high); advance
            if (tx_byte_idx == 2'd3)
                tx_word_busy <= 1'b0;   // last byte dispatched
            else
                tx_byte_idx <= tx_byte_idx + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Clock cycle counter (32-bit, read-only at 0x414)
    // -------------------------------------------------------------------------
    logic [31:0] cycle_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_count <= 32'b0;
        else        cycle_count <= cycle_count + 32'd1;
    end

    // -------------------------------------------------------------------------
    // rx_ready sticky flag
    //   Set   on rx_valid pulse (new byte arrived).
    //   Clear on CPU read of UART address (MemRead & addr==3'b100).
    //   rx_valid wins if both happen in the same cycle (new data takes priority).
    // -------------------------------------------------------------------------
    logic rx_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_ready <= 1'b0;
        end else if (rx_valid) begin
            rx_ready <= 1'b1;                               // new byte received
        end else if (MemRead & (addr == 3'b100)) begin
            rx_ready <= 1'b0;                               // CPU read clears the flag
        end
    end

    // -------------------------------------------------------------------------
    // Read mux (combinatorial)
    //   addr 3'b000 -> 0x400 : SW  zero-extended to 32 bits
    //   addr 3'b001 -> 0x404 : KEY zero-extended to 32 bits
    //   addr 3'b100 -> 0x410 : {22'b0, tx_busy, rx_ready, rx_data[7:0]}
    //   others               : 0  (write-only peripherals)
    // -------------------------------------------------------------------------
    always_comb begin
        case (addr)
            3'b000:  ReadData = {14'b0, SW};
            3'b001:  ReadData = {28'b0, KEY};
            3'b100:  ReadData = {22'b0, (tx_word_busy | tx_busy), rx_ready, rx_data};
            3'b101:  ReadData = cycle_count;
            default: ReadData = 32'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // LED write registers (synchronous write, asynchronous reset)
    //   addr 3'b010 -> 0x408 : write LEDR[17:0]
    //   addr 3'b011 -> 0x40C : write LEDG[8:0]
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
