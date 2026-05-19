# =============================================================================
# sc_top.sdc  —  TimeQuest timing constraints
# Target : DE2-115  (Intel Cyclone IV E)
# Clocks : CLOCK_50 (50 MHz board) → pll_10mhz → clk_cpu (10 MHz, CPU)
#
# Caminho crítico (clock de 10 MHz → período de 100 ns)
# -------------------------------------------------------
# As memórias (sc_imem / sc_dmem) usam arrays SV com leitura assíncrona.
# Todo o caminho combinacional corre no período completo de 100 ns:
#   posedge(clk_cpu) → PC → imem(async) → decode → regfile(async) → ALU →
#   dmem(async) → mux → write_back → setup antes do próximo posedge
#
# Domínios de clock
# -----------------
#   clk      : 50 MHz, pino P11, usado apenas como referência para o PLL
#   clk_cpu  : 10 MHz, saída c0 do pll_10mhz (roteado no global clock network)
# =============================================================================

# -----------------------------------------------------------------------------
# 1.  Clock de entrada — CLOCK_50 (pino P11 no DE2-115)
#     Apenas referência para o PLL; nenhum FF do design captura neste clock.
# -----------------------------------------------------------------------------
create_clock \
    -name    {clk} \
    -period  20.000 \
    -waveform {0.000 10.000} \
    [get_ports {clk}]

# -----------------------------------------------------------------------------
# 2.  Clock derivado — saída c0 do PLL (10 MHz)
#     O Quartus reconhece automaticamente clocks gerados por ALTPLL quando se
#     usa create_generated_clock apontando para o pino de saída do PLL.
#
#     Caminho hierárquico padrão para ALTPLL no Cyclone IV E:
#       <inst>|altpll_component|auto_generated|pll1|clk[0]
# -----------------------------------------------------------------------------
create_generated_clock \
    -name    {clk_cpu} \
    -source  [get_ports {clk}] \
    -divide_by 5 \
    [get_pins {pll_inst|altpll_component|auto_generated|pll1|clk[0]}]

# -----------------------------------------------------------------------------
# 3.  Incerteza de clock (jitter + skew)
# -----------------------------------------------------------------------------
derive_clock_uncertainty

# -----------------------------------------------------------------------------
# 4.  Reset assíncrono (KEY[0] → rst_n)  e  sinal pll_locked
#     Ambos são assíncronos em relação ao clk_cpu — sem requisito de timing.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_pins  {pll_inst|altpll_component|auto_generated|pll1|locked}]

# -----------------------------------------------------------------------------
# 5.  Saída PC  (LEDs / SignalTap — sem requisito externo de timing)
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {PC[*]}]
