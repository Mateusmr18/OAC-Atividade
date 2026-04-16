`timescale 1ns/1ps

module mux4to1_32bits_tb;

    // Sinais de teste
    logic [31:0] t_a, t_b, t_c, t_d;
    logic [1:0]  t_sel;
    logic [31:0] t_f;

    // Instanciação do Design Under Test (DUT)
    mux4to1_32bits dut (
        .a(t_a), .b(t_b), .c(t_c), .d(t_d),
        .sel(t_sel),
        .f(t_f)
    );

    initial begin
        // Valores iniciais nas entradas (Hexadecimal para facilitar leitura)
        t_a = 32'hAAAAAAAA; // Padrão 1010...
        t_b = 32'hBBBBBBBB; // Padrão 1011...
        t_c = 32'hCCCCCCCC;
        t_d = 32'hDDDDDDDD;

        // Monitor de console para facilitar a verificação no ModelSim
        $monitor("Tempo=%0t | Sel=%b | Saida F=%h", $time, t_sel, t_f);

        // Testando Seleção 00
        t_sel = 2'b00; #10;
        
        // Testando Seleção 01
        t_sel = 2'b01; #10;
        
        // Testando Seleção 10
        t_sel = 2'b10; #10;
        
        // Testando Seleção 11
        t_sel = 2'b11; #10;

        // Teste com novos valores aleatórios
        t_a = 32'd123456; t_sel = 2'b00; #10;

        $display("Simulação finalizada com sucesso!");
        $stop; // Pausa a simulação no ModelSim
    end

endmodule