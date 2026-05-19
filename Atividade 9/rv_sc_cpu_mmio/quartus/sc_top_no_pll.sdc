# =============================================================================
# sc_top_no_pll.sdc — TimeQuest Timing Constraints (variante sem PLL)
# Projeto : RV32I Single-Cycle MMIO
# Alvo    : DE2-115 — Intel Cyclone IV E (EP4CE115F29C7, speed grade -7)
# Top     : sc_top_no_pll
#
# CLOCK_50 (50 MHz, PIN_Y2) alimenta a CPU diretamente — domínio único.
#
# Caminho crítico do processador single-cycle (período 20 ns)
# ────────────────────────────────────────────────────────────
# Todo o caminho combinacional percorre o datapath inteiro em 1 ciclo:
#
#   PC-reg → imem (LUT-RAM async)                  ≈  8 ns
#          → decode + control (LUT)                ≈  4 ns
#          → regfile (LUT-RAM async)               ≈  5 ns
#          → ALU 32b (add/sub/and/or/slt)          ≈  8 ns
#          → dmem / MMIO (LUT-RAM async + decode)  ≈ 10 ns
#          → mux MemtoReg → regfile write setup    ≈  3 ns
#                                          total   ≈ 38 ns  ← > 20 ns
#
# O single-cycle dificilmente fecha timing a 50 MHz no Cyclone IV E -7.
# Este SDC serve para medir o slack negativo e identificar o caminho
# crítico exato via Timing Analyzer após a síntese.
#
# Comparação com sc_top.sdc (versão com PLL a 10 MHz):
#   sc_top.sdc       → período 100 ns (clk_cpu)  — folga ampla
#   sc_top_no_pll.sdc → período  20 ns (CLOCK_50) — slack negativo esperado
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Clock único — CLOCK_50 (50 MHz, PIN_Y2)
#    Alimenta diretamente todos os flip-flops (PC-reg, regfile, MMIO regs).
#    Não há PLL nem clock derivado.
# -----------------------------------------------------------------------------
create_clock \
    -name     {CLOCK_50} \
    -period   20.000 \
    -waveform {0.000 10.000} \
    [get_ports {CLOCK_50}]

# -----------------------------------------------------------------------------
# 2. Incerteza de clock
#    Sem PLL: jitter dominado pela fonte de clock da placa + skew da rede
#    de distribuição global do Cyclone IV.
# -----------------------------------------------------------------------------
derive_clock_uncertainty

# =============================================================================
# FALSE PATHS — Entradas assíncronas / de baixa frequência
# =============================================================================

# -----------------------------------------------------------------------------
# 3. KEY[3:0] — botões push-button
#    KEY[0]: reset ativo-baixo; sem requisito de setup/hold em relação a CLOCK_50.
#    KEY[3:1]: lidos pelo MMIO (0x404); mudam na escala de centenas de ms.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {KEY[*]}]

# -----------------------------------------------------------------------------
# 4. SW[17:0] — chaves deslizantes
#    Lidas pelo MMIO (0x400); mudança exclusivamente manual.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {SW[*]}]

# -----------------------------------------------------------------------------
# 5. UART_RXD — recepção serial (9600 baud, 104 µs/bit)
#    Sem relação de fase com CLOCK_50.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {UART_RXD}]

# =============================================================================
# FALSE PATHS — Saídas sem requisito externo de timing
# =============================================================================

# -----------------------------------------------------------------------------
# 6. LEDR[17:0] e LEDG[8:0] — LEDs da placa
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {LEDG[*]}]

# -----------------------------------------------------------------------------
# 7. UART_TXD — transmissão serial (9600 baud, 104 µs/bit)
#    Janela de amostragem do receptor (≥ 52 µs) >> 1 ciclo de 20 ns.
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {UART_TXD}]

# -----------------------------------------------------------------------------
# 8. PC[31:0] — PC atual (SignalTap / debug)
#    Saída sem requisito externo de timing.
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {PC[*]}]
