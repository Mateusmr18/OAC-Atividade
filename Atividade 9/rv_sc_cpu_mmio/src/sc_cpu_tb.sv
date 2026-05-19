// =============================================================================
// sc_cpu_tb.sv
// Testbench for sc_cpu (with MMIO) - verification against golden.txt
//
// -- What this testbench does --------------------------------------------------
//   1. Drives SW = 18'h15555 and KEY_IO = 4'hA as constant MMIO inputs.
//   2. Runs the CPU until halt (PC stable for two consecutive cycles).
//   3. Prints to console every register write, dmem write, and MMIO write.
//   4. Writes output.txt with the PC trace and final state
//      (registers x0..x10, dmem shadow words 0..7, LEDR, LEDG).
//   5. Compares output.txt line-by-line against golden.txt and prints PASS/FAIL.
//
// -- Prerequisites -------------------------------------------------------------
//   golden.txt must be present in the ModelSim working directory.
//   program.hex and data.hex must also be present there.
//
// -- Expected results for program.hex (MMIO test) -----------------------------
//   x0  = 00000000  (hardwired zero)
//   x1  = 00000400  (MMIO base address)
//   x2  = 0003ffff  (all 18 LEDR bits set)
//   x3  = 000001ff  (all  9 LEDG bits set)
//   x4  = 00015555  (SW value read back: SW = 18'h15555)
//   x5  = 0000000a  (KEY value read back: KEY = 4'hA)
//   LEDR register = 3ffff  (written via MMIO @ 0x408)
//   LEDG register = 1ff    (written via MMIO @ 0x40C)
//   MEM[03] = 00015555     (SW  value stored to dmem)
//   MEM[04] = 0000000a     (KEY value stored to dmem)
//
// -- How to run (ModelSim) -----------------------------------------------------
//   vlog -sv ../sc_alu.sv ../sc_alu_ctrl.sv ../sc_control.sv  \
//             ../sc_sign_ext.sv ../sc_regfile.sv               \
//             ../sc_imem.sv ../sc_dmem.sv                      \
//             ../sc_uart.sv ../sc_mmio.sv                      \
//             ../sc_datapath.sv ../sc_cpu.sv ../sc_cpu_tb.sv
//   vsim work.sc_cpu_tb
//   run -all
// =============================================================================

`timescale 1ns / 1ps

module sc_cpu_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter int CLK_PERIOD   = 20;   // ns - 50 MHz
    parameter int RESET_CYCLES = 4;    // cycles rst_n held low
    parameter int MAX_CYCLES   = 60;   // timeout budget

    // =========================================================================
    // DUT signals
    // =========================================================================
    logic        clk;
    logic        rst_n;
    logic [31:0] PC;

    // MMIO inputs (constant stimulus - represent physical board state)
    logic [17:0] SW;       // slide switches: 18'h15555 = 0b01_0101_0101_0101_0101
    logic [3:0]  KEY_IO;   // push buttons:   4'hA     = 4'b1010

    // MMIO outputs (LED registers driven by CPU via sw instructions)
    logic [17:0] LEDR;
    logic [8:0]  LEDG;

    // RS-232 UART — TX floated; RX tied to idle (HIGH)
    logic        UART_TXD;
    logic        UART_RXD;

    sc_cpu dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .PC       (PC),
        .SW       (SW),
        .KEY_IO   (KEY_IO),
        .LEDR     (LEDR),
        .LEDG     (LEDG),
        .UART_TXD (UART_TXD),
        .UART_RXD (UART_RXD)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Constant MMIO stimulus
    // =========================================================================
    initial begin
        SW       = 18'h15555;  // alternating-bit pattern on switches
        KEY_IO   = 4'hA;       // push buttons: 1010
        UART_RXD = 1'b1;       // RS-232 idle line = HIGH (no incoming data)
    end

    // =========================================================================
    // Cycle counter (shared between monitors and main sequence)
    // =========================================================================
    int cycle = 0;

    // =========================================================================
    // Register-write monitor
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n &&
            dut.datapath.regfile.RegWrite &&
            dut.datapath.regfile.rd != 5'b0)
        begin
            $display("[cycle %3d] REG  x%-2d <= %08h",
                cycle + 1,
                dut.datapath.regfile.rd,
                dut.datapath.regfile.WriteData);
        end
    end

    // =========================================================================
    // Data-memory write monitor
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n && dut.datapath.dmem.MemWrite) begin
            $display("[cycle %3d] DMEM [word %02h] <= %08h",
                cycle + 1,
                dut.datapath.dmem.addr,
                dut.datapath.dmem.WriteData);
        end
    end

    // =========================================================================
    // MMIO write monitor
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n && dut.datapath.mmio.MemWrite) begin
            case (dut.datapath.mmio.addr)
                3'b010: $display("[cycle %3d] MMIO LEDR      <= %05h",
                            cycle + 1, dut.datapath.mmio.WriteData[17:0]);
                3'b011: $display("[cycle %3d] MMIO LEDG      <= %03h",
                            cycle + 1, dut.datapath.mmio.WriteData[8:0]);
                3'b100: $display("[cycle %3d] MMIO UART TX   <= %02h ('%s')",
                            cycle + 1, dut.datapath.mmio.WriteData[7:0],
                            dut.datapath.mmio.WriteData[7:0]);
                default: ;
            endcase
        end
    end

    // =========================================================================
    // Data-memory write shadow
    // Mirrors every dmem SW so dump_state() can report final memory contents.
    // =========================================================================
    logic [31:0] mem_shadow [0:255];

    initial
        for (int i = 0; i < 256; i++) mem_shadow[i] = '0;

    always @(posedge clk)
        if (rst_n && dut.datapath.dmem.MemWrite)
            mem_shadow[dut.datapath.dmem.addr] <= dut.datapath.dmem.WriteData;

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("sc_cpu_tb.vcd");
        $dumpvars(0, sc_cpu_tb);
    end

    // =========================================================================
    // Main sequence
    // =========================================================================
    integer      fd;
    logic [31:0] prev_pc;

    initial begin
        // --- Reset -----------------------------------------------------------
        rst_n = 0;
        repeat (RESET_CYCLES) @(posedge clk);
        @(negedge clk);         // release between posedges to avoid metastability
        rst_n = 1;

        // --- Open output file ------------------------------------------------
        fd = $fopen("output.txt", "w");
        if (fd == 0) begin
            $display("ERROR: could not open output.txt.");
            $finish;
        end

        // --- Run until halt (PC stable for two consecutive cycles) -----------
        prev_pc = ~32'h0;   // sentinel

        while (1) begin
            @(posedge clk);
            cycle++;

            $fdisplay(fd, "CYCLE %3d  PC=%08h", cycle, PC);

            if (PC === prev_pc) begin
                dump_state();
                break;
            end

            prev_pc = PC;

            if (cycle >= MAX_CYCLES) begin
                $display("TIMEOUT: halt not reached after %0d cycles.", MAX_CYCLES);
                $fclose(fd);
                $finish;
            end
        end

        $fclose(fd);

        // --- Verify against golden -------------------------------------------
        verify_output();

        $finish;
    end

    // =========================================================================
    // dump_state
    // Appends registers x0..x10, data-memory shadow words 00..07,
    // and final LEDR/LEDG values to output.txt.
    // =========================================================================
    task automatic dump_state;
        logic [31:0] v;

        $fdisplay(fd, "---");
        for (int i = 0; i <= 10; i++) begin
            v = (i == 0) ? 32'h0 : dut.datapath.regfile.regs[i];
            $fdisplay(fd, "x%-2d = %08h", i, v);
        end

        $fdisplay(fd, "---");
        for (int w = 0; w <= 7; w++)
            $fdisplay(fd, "MEM[%2d] = %08h", w, mem_shadow[w]);

        $fdisplay(fd, "---");
        $fdisplay(fd, "LEDR = %08h", {14'b0, dut.LEDR});
        $fdisplay(fd, "LEDG = %08h", {23'b0, dut.LEDG});
    endtask

    // =========================================================================
    // verify_output
    // Compares output.txt line-by-line against golden.txt.
    // =========================================================================
    task automatic verify_output;
        integer fg, fo;
        string  lg, lo;
        int     ng, no;
        int     lineno, errs;

        fg = $fopen("golden.txt", "r");
        if (fg == 0) begin
            $display("ERROR: golden.txt not found.");
            return;
        end
        fo = $fopen("output.txt", "r");

        lineno = 0;
        errs   = 0;

        forever begin
            ng = $fgets(lg, fg);
            no = $fgets(lo, fo);

            if (ng == 0 && no == 0) break;

            lineno++;

            if (ng == 0) begin
                $display("  MISMATCH: golden.txt ended before output.txt (line %0d)", lineno);
                errs++;
                break;
            end
            if (no == 0) begin
                $display("  MISMATCH: output.txt ended before golden.txt (line %0d)", lineno);
                errs++;
                break;
            end

            if (lg != lo) begin
                errs++;
                $display("  line %3d MISMATCH", lineno);
                $display("    expected: %s", lg.substr(0, lg.len() - 2));
                $display("    got:      %s", lo.substr(0, lo.len() - 2));
            end
        end

        $fclose(fg);
        $fclose(fo);

        $display("");
        if (errs == 0)
            $display("=== PASS: all %0d lines match ===", lineno);
        else
            $display("=== FAIL: %0d mismatch(es) in %0d lines ===", errs, lineno);
    endtask

endmodule
