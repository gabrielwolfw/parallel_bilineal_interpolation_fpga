//============================================================
// dsa_mem_banked.sv
// Memoria con 4 bancos para escritura SIMD paralela
// VERSIÓN CORREGIDA
//============================================================

module dsa_mem_banked #(
    parameter MEM_SIZE   = 262144,
    parameter ADDR_WIDTH = 18,
    parameter NUM_BANKS  = 4
)(
    input  logic                    clk,
    
    // Puerto de lectura
    input  logic                    read_en,
    input  logic [ADDR_WIDTH-1:0]   read_addr,
    output logic [7:0]              read_data,
    
    // Puerto de escritura simple (secuencial/externo)
    input  logic                    write_en,
    input  logic [ADDR_WIDTH-1:0]   write_addr,
    input  logic [7:0]              write_data,
    
    // Puerto de escritura SIMD (4 píxeles paralelos)
    input  logic                    simd_write_en,
    input  logic [ADDR_WIDTH-1:0]   simd_base_addr,
    input  logic [7:0]              simd_data_0,
    input  logic [7:0]              simd_data_1,
    input  logic [7:0]              simd_data_2,
    input  logic [7:0]              simd_data_3
);

    // Tamaño de cada banco
    localparam BANK_SIZE = MEM_SIZE / NUM_BANKS;
    localparam BANK_ADDR_WIDTH = ADDR_WIDTH - 2;
    
    // 4 bancos de memoria
    logic [7:0] bank0 [0:BANK_SIZE-1];
    logic [7:0] bank1 [0:BANK_SIZE-1];
    logic [7:0] bank2 [0:BANK_SIZE-1];
    logic [7:0] bank3 [0:BANK_SIZE-1];
    
    //========================================================
    // Señales de lectura
    //========================================================
    logic [1:0] read_bank_sel;
    logic [BANK_ADDR_WIDTH-1:0] read_bank_addr;
    
    assign read_bank_sel = read_addr[1:0];
    assign read_bank_addr = read_addr[ADDR_WIDTH-1:2];
    
    //========================================================
    // Señales de escritura simple
    //========================================================
    logic [1:0] write_bank_sel;
    logic [BANK_ADDR_WIDTH-1:0] write_bank_addr;
    
    assign write_bank_sel = write_addr[1:0];
    assign write_bank_addr = write_addr[ADDR_WIDTH-1:2];
    
    //========================================================
    // Direcciones SIMD - para escritura alineada
    // Asumimos que simd_base_addr está alineado a 4
    //========================================================
    logic [BANK_ADDR_WIDTH-1:0] simd_bank_addr;
    assign simd_bank_addr = simd_base_addr[ADDR_WIDTH-1:2];

    //========================================================
    // Lectura - 1 ciclo de latencia
    //========================================================
    always_ff @(posedge clk) begin
        if (read_en) begin
            case (read_bank_sel)
                2'd0: read_data <= bank0[read_bank_addr];
                2'd1: read_data <= bank1[read_bank_addr];
                2'd2: read_data <= bank2[read_bank_addr];
                2'd3: read_data <= bank3[read_bank_addr];
            endcase
        end
    end
    
    //========================================================
    // Escritura Banco 0
    //========================================================
    always_ff @(posedge clk) begin
        if (simd_write_en) begin
            // Escritura SIMD: dato 0 siempre va a banco 0
            bank0[simd_bank_addr] <= simd_data_0;
        end else if (write_en && write_bank_sel == 2'd0) begin
            bank0[write_bank_addr] <= write_data;
        end
    end
    
    //========================================================
    // Escritura Banco 1
    //========================================================
    always_ff @(posedge clk) begin
        if (simd_write_en) begin
            // Escritura SIMD: dato 1 siempre va a banco 1
            bank1[simd_bank_addr] <= simd_data_1;
        end else if (write_en && write_bank_sel == 2'd1) begin
            bank1[write_bank_addr] <= write_data;
        end
    end
    
    //========================================================
    // Escritura Banco 2
    //========================================================
    always_ff @(posedge clk) begin
        if (simd_write_en) begin
            // Escritura SIMD: dato 2 siempre va a banco 2
            bank2[simd_bank_addr] <= simd_data_2;
        end else if (write_en && write_bank_sel == 2'd2) begin
            bank2[write_bank_addr] <= write_data;
        end
    end
    
    //========================================================
    // Escritura Banco 3
    //========================================================
    always_ff @(posedge clk) begin
        if (simd_write_en) begin
            // Escritura SIMD: dato 3 siempre va a banco 3
            bank3[simd_bank_addr] <= simd_data_3;
        end else if (write_en && write_bank_sel == 2'd3) begin
            bank3[write_bank_addr] <= write_data;
        end
    end

endmodule