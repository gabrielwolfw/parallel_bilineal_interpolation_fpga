//============================================================
// dsa_mem_banked. sv
// Memoria con 4 bancos para escritura SIMD paralela
// LECTURA COMPLETAMENTE SÍNCRONA PARA INFERENCIA M10K
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
    
    // 4 bancos de memoria - CON ATRIBUTOS PARA M10K
    (* ramstyle = "M10K" *) reg [7:0] bank0 [0:BANK_SIZE-1];
    (* ramstyle = "M10K" *) reg [7:0] bank1 [0:BANK_SIZE-1];
    (* ramstyle = "M10K" *) reg [7:0] bank2 [0:BANK_SIZE-1];
    (* ramstyle = "M10K" *) reg [7:0] bank3 [0:BANK_SIZE-1];
    
    //========================================================
    // Señales de lectura
    //========================================================
    wire [1:0] read_bank_sel;
    wire [BANK_ADDR_WIDTH-1:0] read_bank_addr;
    
    assign read_bank_sel = read_addr[1:0];
    assign read_bank_addr = read_addr[ADDR_WIDTH-1:2];
    
    //========================================================
    // Señales de escritura simple
    //========================================================
    wire [1:0] write_bank_sel;
    wire [BANK_ADDR_WIDTH-1:0] write_bank_addr;
    
    assign write_bank_sel = write_addr[1:0];
    assign write_bank_addr = write_addr[ADDR_WIDTH-1:2];
    
    //========================================================
    // Direcciones SIMD
    //========================================================
    wire [BANK_ADDR_WIDTH-1:0] simd_bank_addr;
    assign simd_bank_addr = simd_base_addr[ADDR_WIDTH-1:2];

    //========================================================
    // Lectura de cada banco - SÍNCRONA SIMPLE
    // Cada banco lee su propia dirección
    //========================================================
    reg [7:0] read_data_0, read_data_1, read_data_2, read_data_3;
    reg [1:0] read_bank_sel_reg;
    
    // Lecturas síncronas de cada banco
    always @(posedge clk) begin
        if (read_en) begin
            read_data_0 <= bank0[read_bank_addr];
            read_data_1 <= bank1[read_bank_addr];
            read_data_2 <= bank2[read_bank_addr];
            read_data_3 <= bank3[read_bank_addr];
            read_bank_sel_reg <= read_bank_sel;
        end
    end
    
    // Multiplexor de salida (después del registro)
    always @(*) begin
        case (read_bank_sel_reg)
            2'd0: read_data = read_data_0;
            2'd1: read_data = read_data_1;
            2'd2: read_data = read_data_2;
            2'd3: read_data = read_data_3;
            default: read_data = 8'd0;
        endcase
    end
    
    //========================================================
    // Escritura Banco 0
    //========================================================
    always @(posedge clk) begin
        if (simd_write_en) begin
            bank0[simd_bank_addr] <= simd_data_0;
        end else if (write_en && write_bank_sel == 2'd0) begin
            bank0[write_bank_addr] <= write_data;
        end
    end
    
    //========================================================
    // Escritura Banco 1
    //========================================================
    always @(posedge clk) begin
        if (simd_write_en) begin
            bank1[simd_bank_addr] <= simd_data_1;
        end else if (write_en && write_bank_sel == 2'd1) begin
            bank1[write_bank_addr] <= write_data;
        end
    end
    
    //========================================================
    // Escritura Banco 2
    //========================================================
    always @(posedge clk) begin
        if (simd_write_en) begin
            bank2[simd_bank_addr] <= simd_data_2;
        end else if (write_en && write_bank_sel == 2'd2) begin
            bank2[write_bank_addr] <= write_data;
        end
    end
    
    //========================================================
    // Escritura Banco 3
    //========================================================
    always @(posedge clk) begin
        if (simd_write_en) begin
            bank3[simd_bank_addr] <= simd_data_3;
        end else if (write_en && write_bank_sel == 2'd3) begin
            bank3[write_bank_addr] <= write_data;
        end
    end

endmodule