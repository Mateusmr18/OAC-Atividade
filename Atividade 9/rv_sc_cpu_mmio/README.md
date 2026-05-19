# RISC-V Single-Cycle com MMIO

Implementação em SystemVerilog de um processador RISC-V RV32I single-cycle com suporte a Memory-Mapped I/O (MMIO), baseada no Capítulo 4 de *Patterson & Hennessy — Computer Organization and Design (RISC-V Edition)*. Alvo: placa **DE2-115** (Intel Cyclone IV E, EP4CE115F29C7, 50 MHz).

---

## Sumário

1. [Compilando um programa com o assembler](#compilando-um-programa-com-o-assembler)
2. [Organização do MMIO](#organização-do-mmio)
3. [Dump serial](#dump-serial)
4. [Arquitetura](#arquitetura)
5. [Instruções suportadas](#instruções-suportadas)
6. [Sinais de controle](#sinais-de-controle)
7. [Síntese no Quartus](#síntese-no-quartus)
8. [Simulação no ModelSim](#simulação-no-modelsim)

---

## Compilando um programa com o assembler

O script `assembler/assembler.py` traduz um arquivo de texto com instruções RISC-V para arquivos `.mif` no formato que o Quartus usa para inicializar as memórias na FPGA.

### Uso

```bash
cd assembler

# modo normal — gera instruction.mif + program.hex
python3 assembler.py programa.asm

# sem argumento — usa instructions.txt como padrão
python3 assembler.py

# modo dump — gera instruction.mif + data.mif com dump serial embutido
python3 assembler.py --dump programa.asm
```

Todos os arquivos de saída são gerados na própria pasta `assembler/`.

### Formato de entrada

Uma instrução por linha, sem rótulos:

```
<instr> <rd>,<rs1>,<rs2>        # R-type  (ex: add  x3,x1,x2)
<instr> <rd>,<rs1>,<imm>        # I-type  (ex: addi x1,x0,8)
<instr> <rd>,<imm>(<rs1>)       # Load    (ex: lw   x2,0(x1))
<instr> <rs2>,<imm>(<rs1>)      # Store   (ex: sw   x2,8(x1))
<instr> <rs1>,<rs2>,<imm>       # Branch  (ex: beq  x0,x0,-8)
<instr> <rd>,<imm>              # U / J   (ex: lui  x1,1)
```

### Modo normal

Gera dois arquivos em `assembler/`:

| Arquivo | Uso |
|---------|-----|
| `instruction.mif` | Síntese no Quartus (`ram_init_file`) e simulação no ModelSim |
| `program.hex` | Simulação via `$readmemh` |

### Modo `--dump`

Appenda automaticamente o código de dump serial ao programa do usuário. Útil para inspecionar o estado do processador via porta serial após a execução.

| Arquivo | Conteúdo |
|---------|----------|
| `instruction.mif` | Código do usuário + `beq` de desvio + dump serial a partir de `0x080` |
| `data.mif` | Zeros + constantes de infraestrutura do dump em `0x080–0x086` |

**Layout da memória de instruções com `--dump`:**

```
0x000..N-1    Código do usuário (máx. 127 instruções)
0xN           beq x0,x0,→0x80  (desvio incondicional para o dump)
0xN+1..07F    NOP (addi x0,x0,0)
0x080..0x0AD  Dump serial — Parts 2–8 (46 instruções)
```

**Layout da memória de dados com `--dump`:**

```
0x000..0x01F  Área do usuário  (byte 0x000–0x07C) — transmitida no dump
0x078..0x07F  Saves de x1–x8  (byte 0x1E0–0x1FC) — escritos em runtime
0x080..0x086  Constantes de infraestrutura         — inicializadas no MIF
```

**O que o dump transmite via UART (164 bytes = 41 palavras):**

```
bytes  0–  3   Contador de ciclos (MMIO 0x414)
bytes  4– 35   Registradores x1–x8
bytes 36–163   dmem[0x000–0x07C] (32 palavras do usuário)
```

### Sintetizando após compilar

Copie os MIFs gerados para a pasta `quartus/` e recompile:

```bash
cp assembler/instruction.mif quartus/
cp assembler/data.mif quartus/      # apenas no modo --dump
```

No Quartus: **Processing → Start Compilation**, depois **Tools → Programmer**.

---

## Organização do MMIO

O MMIO é implementado no módulo `sc_mmio.sv` e mapeia os periféricos físicos da DE2-115 no espaço de endereços do processador.

### Decodificação de endereço

A separação entre memória de dados e MMIO é feita pelo **bit 10** do resultado da ULA (endereço calculado pela instrução `lw`/`sw`):

```
alu_result[10] = 0  →  sc_dmem  (0x000 – 0x3FC, memória de dados comum)
alu_result[10] = 1  →  sc_mmio  (0x400 – 0x40C, periféricos)
```

Dentro da janela MMIO, os bits `[3:2]` selecionam o periférico:

```
alu_result[3:2] = 00  →  0x400  SW[17:0]   (leitura)
alu_result[3:2] = 01  →  0x404  KEY[3:0]   (leitura)
alu_result[3:2] = 10  →  0x408  LEDR[17:0] (escrita)
alu_result[3:2] = 11  →  0x40C  LEDG[8:0]  (escrita)
```

### Mapa de endereços

| Endereço | Periférico   | Direção  | Largura | Descrição |
|----------|--------------|----------|---------|-----------|
| `0x400`  | `SW[17:0]`   | leitura  | 18 bits | Chaves deslizantes |
| `0x404`  | `KEY[3:0]`   | leitura  | 4 bits  | Botões (KEY[0] = reset) |
| `0x408`  | `LEDR[17:0]` | escrita  | 18 bits | LEDs vermelhos |
| `0x40C`  | `LEDG[8:0]`  | escrita  | 9 bits  | LEDs verdes |
| `0x410`  | UART RS-232  | leitura/escrita | 32 bits | Serial 8N1, 9600 baud |
| `0x414`  | Ciclos       | leitura  | 32 bits | Contador de ciclos de clock |

**Leitura UART (`lw` em 0x410):** `{22'b0, tx_busy[9], rx_ready[8], rx_data[7:0]}`

**Escrita UART (`sw` em 0x410):** o hardware divide automaticamente a palavra de 32 bits em 4 bytes e os transmite em ordem little-endian. `tx_busy` permanece alto até o último byte ser enviado.

### Comportamento elétrico

- **Leituras** (`lw`): combinatoriais — o valor nos pinos físicos é lido no ciclo em que a instrução executa.
- **Escritas** (`sw`): registradas — o valor é registrado no registrador de LED na borda de subida do clock do mesmo ciclo.
- **Reset** (`KEY[0]`, ativo em baixo): `LEDR` e `LEDG` são zerados assincronamente.

### Usando o MMIO no programa

O endereço base `0x400` não pode ser carregado diretamente com `addi` (campo imediato de 12 bits, mas o valor tem bit 10 = 1 e parte alta zero). A solução é armazená-lo na memória de dados e carregá-lo com `lw`:

```asm
# data.mif palavra 0 = 0x00000400
lw  x1,  0(x0)      # x1 = 0x400  (base MMIO)

lw  x2,  0(x1)      # lê SW[17:0]    (addr 0x400)
lw  x3,  4(x1)      # lê KEY[3:0]    (addr 0x404)
sw  x2,  8(x1)      # escreve LEDR   (addr 0x408)
sw  x3, 12(x1)      # escreve LEDG   (addr 0x40C)
```

O `MemWrite` é internamente multiplexado por `mmio_sel` para evitar que um `sw` para um endereço MMIO corrompa a memória de dados, e vice-versa:

```systemverilog
// sc_datapath.sv
sc_dmem dmem (.MemWrite(MemWrite & ~mmio_sel), .addr(alu_result[9:2]), ...);
sc_mmio mmio (.MemWrite(MemWrite &  mmio_sel), .addr(alu_result[3:2]), ...);
```

---

## Dump serial

O script `dump/serial_dump.py` captura o dump transmitido pelo FPGA e exibe o estado do processador.

### Pré-requisitos

```bash
pip install pyserial
```

### Uso

```bash
# Compile com --dump e copie para quartus/; grave o bitstream; então:
python3 dump/serial_dump.py COM3            # Windows
python3 dump/serial_dump.py /dev/ttyUSB0   # Linux
```

O script aguarda **164 bytes** (41 palavras a 9600 baud, ≈ 164 ms) e imprime:

```
==============================================================
  RV32I Dump
  2025-05-08 14:32:01
==============================================================

[ Contador de Ciclos ]
  cycles =        423  (0x000001A7)

[ Registradores x1 – x8 ]
  Reg    ABI         Hex    Dec (uint)     Dec (int)
  -------------------------------------------------------
  x1     ra    0x0000000A          10            10
  ...

[ Memória de Dados  0x000 – 0x07C ]
  Endereço          Hex    Dec (uint)     Dec (int)
  -------------------------------------------------------
  0x000        0x0000000A          10            10
  ...
```

O relatório também é salvo em `dump.txt` (configurável com `--out`).

### Fluxo completo

```bash
cd assembler
python3 assembler.py --dump meu_programa.asm  # gera instruction.mif + data.mif
cp instruction.mif data.mif ../quartus/        # copia para o projeto Quartus
# compilar e gravar na FPGA via Quartus...
cd ../dump
python3 serial_dump.py COM3                    # captura o resultado
```

---

## Arquitetura

```
sc_top
├── pll_10mhz          — ALTPLL: 50 MHz → 10 MHz
└── sc_cpu
    ├── sc_control     — Unidade de controle (decodifica opcode)
    └── sc_datapath
        ├── sc_imem    — Memória de instruções (256 × 32 bits)
        ├── sc_regfile — Banco de registradores (32 × 32 bits)
        ├── sc_sign_ext— Extensor de sinal (formatos I, S, B)
        ├── sc_alu_ctrl— Controle da ALU
        ├── sc_alu     — ALU de 32 bits
        ├── sc_dmem    — Memória de dados (256 × 32 bits)
        └── sc_mmio    — MMIO: SW, KEY, LEDR, LEDG
```

### Memórias — leitura assíncrona

`sc_imem` e `sc_dmem` são implementadas como arrays SystemVerilog com leitura puramente combinacional:

```systemverilog
assign instr    = rom[addr];   // sc_imem: sem clock
assign ReadData = ram[addr];   // sc_dmem: sem clock
```

Escritas em `sc_dmem` são síncronas na borda de subida:

```systemverilog
always @(posedge clk)
    if (MemWrite) ram[addr] <= WriteData;
```

O Quartus infere **MLAB** (LUT-RAM) para arrays com leitura combinacional, que suportam leitura assíncrona no Cyclone IV.

### Clock e reset

O clock da CPU é **10 MHz**, derivado do `CLOCK_50` pelo PLL. O reset (`KEY[0]`) mantém o processador em reset até que o PLL trave (`pll_locked`), evitando execução em clock instável no boot.

---

## Instruções suportadas

### Hardware implementado (`sc_control.sv`)

| Tipo   | Instrução | Opcode    |
|--------|-----------|-----------|
| R-type | `add`, `sub`, `and`, `or`, `slt` | `0110011` |
| I-type | `lw`      | `0000011` |
| S-type | `sw`      | `0100011` |
| B-type | `beq`     | `1100011` |

### Suportadas pelo assembler (requerem extensão do controle)

O assembler codifica corretamente todas as instruções abaixo, mas o hardware precisaria ser estendido para executá-las:

| Tipo   | Instruções |
|--------|-----------|
| R-type | `xor`, `sll`, `srl`, `sra`, `sltu` |
| I-type | `addi`, `slti`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai`, `jalr` |
| S-type | `sb`, `sh` |
| B-type | `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| U-type | `lui`, `auipc` |
| J-type | `jal` |

---

## Sinais de controle

| Sinal    | R-type | `lw` | `sw` | `beq` |
|----------|:------:|:----:|:----:|:-----:|
| ALUSrc   | 0      | 1    | 1    | 0     |
| MemtoReg | 0      | 1    | —    | —     |
| RegWrite | 1      | 1    | 0    | 0     |
| MemRead  | 0      | 1    | 0    | 0     |
| MemWrite | 0      | 0    | 1    | 0     |
| Branch   | 0      | 0    | 0    | 1     |
| ALUOp    | `10`   | `00` | `00` | `01`  |

ALUOp: `00` = força ADD (load/store), `01` = força SUB (branch), `10` = R-type (ALU ctrl decodifica funct3/funct7).

---

## Síntese no Quartus

1. Abra `quartus/riscv_single_cycle.qpf` no **Quartus Prime 21.1**.
2. Certifique-se de que `instruction.mif` e o `.mif` de dados estão na **raiz do projeto**.
3. Execute **Processing → Start Compilation**.
4. Grave com **Tools → Programmer** (USB-Blaster, dispositivo EP4CE115F29C7).

---

## Simulação no ModelSim

Os arquivos `modelsim/program.hex` e `modelsim/data.hex` são carregados via `$readmemh` nos blocos `initial` (guardados por `// synthesis translate_off`).

```bash
cd modelsim

vlog -sv ../sc_alu.sv ../sc_alu_ctrl.sv ../sc_control.sv \
         ../sc_sign_ext.sv ../sc_regfile.sv               \
         ../sc_imem.sv ../sc_dmem.sv ../sc_mmio.sv        \
         ../sc_datapath.sv ../sc_cpu.sv ../sc_cpu_tb.sv

vsim work.sc_cpu_tb
run -all
```

O testbench imprime cada escrita no console, gera `output.txt` e compara com `golden.txt`:

```
[cycle   5] REG  x1  <= 00000400
[cycle   6] MMIO LEDR  <= 3ffff
=== PASS: all 36 lines match ===
```

---

## Referências

- Patterson, D. A.; Hennessy, J. L. *Computer Organization and Design: RISC-V Edition*. 2ª ed. Morgan Kaufmann, 2020. Capítulos 4.1–4.4.
- [RISC-V Instruction Set Manual, Volume I: Unprivileged ISA](https://riscv.org/specifications/)
