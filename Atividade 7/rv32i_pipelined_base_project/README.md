# RV32I Pipelined Base Project

Processador RISC-V de 32 bits com pipeline de 5 estágios implementado em SystemVerilog, baseado nas seções 4.6 a 4.10 de *Computer Organization and Design: RISC-V Edition* (Patterson & Hennessy). O projeto tem como plataforma alvo a placa **DE2-115** (Intel Cyclone IV E) e é estruturado para servir de base para extensões do conjunto de instruções pelos alunos.

---

## Instruções suportadas

| # | Instrução | Tipo | Opcode | Status |
|---|-----------|------|--------|:------:|
| 1 | `ADD`     | R    | 0110011 | ✅ |
| 2 | `AND`     | R    | 0110011 | ✅ |
| 3 | `LW`      | I    | 0000011 | ✅ |
| 4 | `SW`      | S    | 0100011 | ✅ |
| 5 | `BEQ`     | B    | 1100011 | ✅ |

### Instruções a implementar

| #  | Instrução | Tipo | Opcode  | Status |
|----|-----------|------|---------|:------:|
|  1 | `JAL`     | J    | 1101111 | ❌ |
|  2 | `JALR`    | I    | 1100111 | ❌ |
|  3 | `BNE`     | B    | 1100011 | ❌ |
|  4 | `BLT`     | B    | 1100011 | ❌ |
|  5 | `BGE`     | B    | 1100011 | ❌ |
|  6 | `BLTU`    | B    | 1100011 | ❌ |
|  7 | `LB`      | I    | 0000011 | ❌ |
|  8 | `LH`      | I    | 0000011 | ❌ |
|  9 | `LBU`     | I    | 0000011 | ❌ |
| 10 | `SB`      | S    | 0100011 | ❌ |
| 11 | `SH`      | S    | 0100011 | ❌ |
| 12 | `ADDI`    | I    | 0010011 | ❌ |
| 13 | `SLTI`    | I    | 0010011 | ❌ |
| 14 | `SLLI`    | I    | 0010011 | ❌ |
| 15 | `SRLI`    | I    | 0010011 | ❌ |
| 16 | `SRAI`    | I    | 0010011 | ❌ |
| 17 | `SUB`     | R    | 0110011 | ❌ |
| 18 | `SLT`     | R    | 0110011 | ❌ |
| 19 | `XOR`     | R    | 0110011 | ❌ |
| 20 | `OR`      | R    | 0110011 | ❌ |
| 21 | `HALT`    | —    | —       | ❌ |

---

## Arquitetura

### Pipeline de 5 estágios

```
+------+     +------+     +------+     +------+     +------+
|  IF  | --> |  ID  | --> |  EX  | --> | MEM  | --> |  WB  |
+------+     +------+     +------+     +------+     +------+
  Busca      Decode       Execução     Memória     Write-back
  instrução  Regs         ALU          dmem/MMIO   Regfile
             Sign-ext     Branch
```

**Registradores de pipeline:** `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` (definidos em `pl_pipe_pkg.sv`).

### Tratamento de hazards

| Hazard | Mecanismo | Detalhe |
|--------|-----------|---------|
| RAW (dado) | Forwarding | EX/MEM → EX e MEM/WB → EX (`pl_forward.sv`) |
| Load-use | Stall | 1 bolha inserida em ID/EX (`pl_hazard.sv`) |
| Branch taken | Flush | 2 NOPs (IF e ID) na resolução em EX (`pl_datapath.sv`) |

**Resolução de branch no estágio EX:** quando `BEQ` é tomado, o PC retorna ao alvo e os dois estágios anteriores são esvaziados. O custo é de 2 ciclos de penalidade por branch tomado.

**Banco de registradores com escrita em negedge:** a escrita ocorre na borda de descida do clock, garantindo que o estágio ID leia o valor atualizado no próximo posedge sem necessidade de forwarding WB→ID explícito.

### Mapa de memória

| Endereço (byte) | Tamanho | Acesso | Descrição |
|-----------------|---------|--------|-----------|
| `0x000 – 0x3FC` | 256 × 32 b | R/W | Memória de dados (`pl_dmem`) |
| `0x400` | 32 b | R | SW\[17:0\] — chaves deslizantes |
| `0x404` | 32 b | R | KEY\[3:0\] — botões push |
| `0x408` | 32 b | W | LEDR\[17:0\] — LEDs vermelhos |
| `0x40C` | 32 b | W | LEDG\[8:0\] — LEDs verdes |
| `0x410` | 32 b | R/W | UART RS-232 (8N1, 9600 baud) |

Seleção: `alu_result[10] = 1` redireciona o acesso ao controlador MMIO (`pl_mmio`).

Leitura da UART: `{22'b0, tx_busy[9], rx_ready[8], rx_data[7:0]}`

### ALU — codificação de operação

| Operation | Instrução |
|-----------|-----------|
| `4'd01` ADD | LW, SW, ADD |
| `4'd02` SUB | BEQ (comparação) |
| `4'd04` OR  | OR |
| `4'd05` AND | AND |
| `4'd11` SLT | SLT |

---

## Estrutura do repositório

```
rv32i_pipelined_base_project/
│
├── src/                        Código-fonte SystemVerilog
│   ├── pl_pipe_pkg.sv          Structs dos registradores de pipeline
│   ├── pl_top.sv               Top-level (PLL 50→10 MHz + CPU)
│   ├── pl_cpu.sv               Wrapper: Control + ALU_Ctrl + Datapath
│   ├── pl_control.sv           Unidade de controle (estágio ID)
│   ├── pl_alu_ctrl.sv          Controle da ALU (estágio EX)
│   ├── pl_alu.sv               ALU 32 bits
│   ├── pl_regfile.sv           Banco de registradores 32×32 b
│   ├── pl_sign_ext.sv          Extensão de sinal I/S/B
│   ├── pl_imem.sv              Memória de instruções 256×32 b (MIF)
│   ├── pl_dmem.sv              Memória de dados 256×32 b (MIF)
│   ├── pl_mmio.sv              Controlador MMIO (SW/KEY/LED/UART)
│   ├── sc_uart.sv              UART RS-232 8N1 (9600 baud, 10 MHz)
│   ├── pl_hazard.sv            Detecção de hazard load-use
│   ├── pl_forward.sv           Unidade de forwarding
│   ├── pl_datapath.sv          Datapath 5 estágios
│   ├── pl_cpu_tb.sv            Testbench de verificação
│   └── pll_10mhz.v             PLL Altera (50 MHz → 10 MHz)
│
├── mifs/                       Arquivos de inicialização de memória
│   ├── instruction.mif         Programa de teste padrão
│   ├── data.mif                Dados iniciais do programa de teste
│   ├── mmio_test_program.mif   Programa de teste MMIO + UART
│   └── mmio_test_data.mif      Dados para o teste MMIO
│
├── assembler/
│   └── assembler.py            Montador Python: assembly → .mif
│
├── modelsim/                   Projeto ModelSim para simulação
│   ├── *.mpf                   Arquivo de projeto ModelSim
│   ├── program.hex             Imagem da instrução (.hex para $readmemh)
│   ├── data.hex                Imagem dos dados (.hex para $readmemh)
│   ├── golden.txt              Saída esperada pelo testbench
│   └── output.txt              Saída gerada na última simulação
│
└── quartus/                    Projeto Quartus Prime para síntese
    ├── *.qpf / *.qsf           Arquivos de projeto Quartus
    ├── instruction.mif         MIF da instrução (cópia de trabalho)
    └── data.mif                MIF dos dados (cópia de trabalho)
```

---

## Como simular (ModelSim)

1. Abra o ModelSim e carregue o projeto `modelsim/rv32i_pipelined_base_project.mpf`.
2. Compile todos os arquivos em `src/` — compilar `pl_pipe_pkg.sv` primeiro.
3. Inicie a simulação com o top `pl_cpu_tb`.
4. Execute `run -all`.

O testbench detecta o halt automaticamente (repetição periódica do PC causada pelo `beq x0, x0, 0`), imprime o estado final dos registradores e da memória, e compara a saída com `modelsim/golden.txt`.

**Programa de teste padrão (`mifs/instruction.mif`):**

```
000: lw  x1,  0(x0)   x1 = 10
001: lw  x2,  4(x0)   x2 = 20
002: add x3, x1, x2   x3 = 30   -- forwarding MEM/WB→EX
003: and x4, x3, x1   x4 = 10   -- forwarding EX/MEM→EX
004: lw  x5,  0(x0)   x5 = 10   -- causa load-use stall
005: add x6, x5, x2   x6 = 30   -- executado após 1 ciclo de stall
006: sw  x3,  8(x0)   dmem[2] = 30
007: beq x1, x2, +8   NÃO tomado (10 ≠ 20)
008: add x7, x1, x2   x7 = 30
009: beq x1, x5, +8   TOMADO (10 = 10) → flush de 00A
00A: add x8, x0, x0   DESCARTADO
00B: add x8, x1, x4   x8 = 20
00C: beq x0, x0,  0   halt
```

Estado final esperado: `x1=10  x2=20  x3=30  x4=10  x5=10  x6=30  x7=30  x8=20  dmem[2]=30`

---

## Como sintetizar (Quartus)

1. Abra o Quartus Prime e carregue `quartus/rv32i_pipelined_base_project.qpf`.
2. Verifique que os arquivos `instruction.mif` e `data.mif` estão na pasta `quartus/`.
3. Execute **Processing → Start Compilation**.
4. Grave o bitstream na DE2-115 via JTAG.

**Dispositivo alvo:** Intel Cyclone IV E — EP4CE115F29C7  
**Clock:** 50 MHz (entrada) → 10 MHz (saída da PLL, usado pelo CPU)  
**Reset:** KEY\[0\] ativo-baixo; liberado após a PLL travar.

---

## Assembler

O script `assembler/assembler.py` converte assembly textual para o formato `.mif`.

**Uso:**

```bash
# Edite assembler/instructions.txt com o programa desejado
python3 assembler/assembler.py
```

O script gera dois arquivos no diretório corrente:

| Arquivo | Formato | Uso |
|---------|---------|-----|
| `instruction.mif` | Quartus MIF (endereço : dado) | Síntese no Quartus e simulação no ModelSim via `ram_init_file` |
| `program.hex` | Um word hex por linha, sem cabeçalho | Simulação no ModelSim via `$readmemh` |

**Formato aceito (uma instrução por linha):**

```
add  x3, x1, x2
lw   x1, 0(x0)
sw   x3, 8(x0)
beq  x1, x2, -4
```

---

## Detalhes de implementação

### Banco de registradores — escrita em negedge

A escrita no banco de registradores ocorre na **borda de descida** do clock (`negedge clk`). Isso resolve o conflito de leitura/escrita simultânea que ocorre quando, após um load-use stall, o estágio WB escreve um registrador no mesmo ciclo em que o estágio ID o lê para captura no registrador ID/EX. Com a escrita em negedge, o valor é garantidamente visível antes do próximo posedge. Esta é a solução descrita na Fig. 4.63 do P&H.

### Detecção de halt no testbench

O halt é implementado como `beq x0, x0, 0`. Com resolução de branch no estágio EX, o PC oscila com período 3 (H, H+4, H+8, H, …). O testbench detecta halt quando `PC_atual == PC_de_3_ciclos_atrás` por 9 ciclos consecutivos (3 períodos completos).

### UART (9600 8N1 a 10 MHz)

A UART é compartilhada com o projeto `riscv_single_cycle_mmio` (`sc_uart.sv`). Taxa de erro de baud: < 0,1% (1041 clocks/bit, baud efetivo 9606).

---

## Recursos

- [Manual RISC-V ISA v2.2](https://riscv.org/wp-content/uploads/2017/05/riscv-spec-v2.2.pdf)
- [RISC-V ISA Reference (msyksphinz)](https://msyksphinz-self.github.io/riscv-isadoc/html/rvi.html)
- [RISC-V Interpreter — Cornell University](https://www.cs.cornell.edu/courses/cs3410/2019sp/riscv/interpreter/)
- Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition*, seções 4.6 – 4.10
