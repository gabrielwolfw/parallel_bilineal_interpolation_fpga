//============================================================
// dsa_de1soc_top.sv
// Top-level para DE1-SoC con comunicación JTAG + DSA Bilinear Interpolation
// 
// Control:
//   SW[9]: Reset general
//   SW[8]: Modo Start DSA (1=Start, 0=Idle)
//   SW[7]: Modo SIMD (1) vs Secuencial (0)
//   SW[0]: Modo visualización: JTAG (0) vs DSA status (1)
//   
//   KEY[3]: Reset (activo bajo)
//   KEY[0]: Incrementar dirección de visualización
//   KEY[1]: Decrementar dirección de visualización
//
// HEX Displays:
//   HEX5-4: Dirección actual de memoria
//   HEX3-0: Dato leído o estado DSA
//============================================================

module dsa_de1soc_top (
    //////////// CLOCK //////////
    input  logic        CLOCK_50,
    
    //////////// KEY //////////
    input  logic [3:0]  KEY,
    
    //////////// SW //////////
    input  logic [9:0]  SW,
    
    //////////// LED //////////
    output logic [9:0]  LEDR,
    
    //////////// 7-SEG //////////
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5
);

    //========================================================
    // PARÁMETROS
    //========================================================
    localparam DATA_WIDTH = 8;      // Ancho de datos JTAG
    localparam ADDR_WIDTH = 18;     // Ancho de dirección de memoria (256KB)
    localparam MEM_SIZE   = 262144; // 256KB
    localparam IMG_WIDTH  = 512;
    localparam IMG_HEIGHT = 512;
    localparam SIMD_WIDTH = 4;
    
    //========================================================
    // SEÑALES DE RELOJ Y RESET
    //========================================================
    logic clk;
    logic rst_n;
    logic rst;
    logic rst_sw;
    
    assign clk = CLOCK_50;
    assign rst_n = KEY[3];           // Reset por botón
    assign rst_sw = SW[9];           // Reset por switch
    assign rst = ~rst_n | rst_sw;    // Reset combinado
    
    //========================================================
    // CONTROLES DE USUARIO
    //========================================================
    logic dsa_start_trigger;
    logic mode_simd;
    logic display_mode;
    
    assign dsa_start_trigger = SW[8];  // Start DSA
    assign mode_simd = SW[7];          // SIMD vs Secuencial
    assign display_mode = SW[0];       // 0=JTAG data, 1=DSA status
    
    //========================================================
    // VIRTUAL JTAG IP CORE SIGNALS
    //========================================================
    wire        vjtag_tdi;
    wire        vjtag_tdo;
    wire [1:0]  vjtag_ir_in;
    wire [1:0]  vjtag_ir_out;
    wire        vjtag_v_cdr;
    wire        vjtag_v_sdr;
    wire        vjtag_v_udr;
    wire        vjtag_tck;
    
    //========================================================
    // VJTAG INTERFACE SIGNALS
    //========================================================
    logic [DATA_WIDTH-1:0] jtag_data_out;  // PC → FPGA (WRITE)
    logic [DATA_WIDTH-1:0] jtag_data_in;   // FPGA → PC (READ)
    logic [14:0]           jtag_addr_out;  // Dirección desde SETADDR
    
    //========================================================
    // SINCRONIZACIÓN JTAG → CLK DOMAIN
    // Crucial: JTAG opera en dominio TCK, necesitamos sincronizar a CLK
    //========================================================
    logic [DATA_WIDTH-1:0] jtag_data_sync;
    logic [DATA_WIDTH-1:0] jtag_data_prev;
    logic                  jtag_data_valid;  // Pulso cuando hay nuevo dato WRITE
    
    logic [14:0] jtag_addr_sync;
    logic [14:0] jtag_addr_prev;
    logic        jtag_addr_valid;  // Pulso cuando hay nueva dirección SETADDR
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            jtag_data_sync <= '0;
            jtag_data_prev <= '0;
            jtag_data_valid <= 1'b0;
            jtag_addr_sync <= '0;
            jtag_addr_prev <= '0;
            jtag_addr_valid <= 1'b0;
        end else begin
            // Sincronizar datos WRITE
            jtag_data_prev <= jtag_data_sync;
            jtag_data_sync <= jtag_data_out;
            jtag_data_valid <= (jtag_data_sync != jtag_data_prev);
            
            // Sincronizar dirección SETADDR
            jtag_addr_prev <= jtag_addr_sync;
            jtag_addr_sync <= jtag_addr_out;
            jtag_addr_valid <= (jtag_addr_sync != jtag_addr_prev);
        end
    end
    
    //========================================================
    // FSM PARA CONTROL DE MEMORIA JTAG
    // Estados: IDLE → WRITE_MEM → WAIT → IDLE
    //========================================================
    typedef enum logic [1:0] {
        ST_JTAG_IDLE    = 2'd0,
        ST_JTAG_WRITE   = 2'd1,
        ST_JTAG_WAIT    = 2'd2
    } jtag_state_t;
    
    jtag_state_t jtag_state, jtag_next_state;
    
    logic [ADDR_WIDTH-1:0] jtag_mem_address;    // Dirección de memoria JTAG
    logic [7:0]            jtag_write_data_reg; // Dato a escribir
    logic                  jtag_mem_write_en;   // Enable de escritura JTAG
    logic                  jtag_mem_read_en;    // Enable de lectura JTAG
    
    // FSM secuencial
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            jtag_state <= ST_JTAG_IDLE;
        end else begin
            jtag_state <= jtag_next_state;
        end
    end
    
    // FSM combinacional
    always_comb begin
        jtag_next_state = jtag_state;
        jtag_mem_write_en = 1'b0;
        jtag_mem_read_en = 1'b0;
        
        case (jtag_state)
            ST_JTAG_IDLE: begin
                if (jtag_data_valid) begin
                    jtag_next_state = ST_JTAG_WRITE;
                end
            end
            
            ST_JTAG_WRITE: begin
                jtag_mem_write_en = 1'b1;
                jtag_next_state = ST_JTAG_WAIT;
            end
            
            ST_JTAG_WAIT: begin
                jtag_next_state = ST_JTAG_IDLE;
            end
            
            default: jtag_next_state = ST_JTAG_IDLE;
        endcase
    end
    
    // Control de dirección JTAG
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            jtag_mem_address <= '0;
        end else begin
            if (jtag_addr_valid) begin
                // Actualizar dirección con SETADDR (extender a 18 bits)
                jtag_mem_address <= {3'b000, jtag_addr_sync};
            end else if (jtag_state == ST_JTAG_WRITE) begin
                // Auto-incremento después de escritura
                jtag_mem_address <= jtag_mem_address + 1;
            end
        end
    end
    
    // Registro de dato a escribir
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            jtag_write_data_reg <= '0;
        end else if (jtag_data_valid) begin
            jtag_write_data_reg <= jtag_data_sync;
        end
    end
    
    //========================================================
    // CONTROL DE NAVEGACIÓN CON BOTONES (Debounce)
    //========================================================
    localparam DEBOUNCE_CYCLES = 500_000; // 10ms @ 50MHz
    
    logic [ADDR_WIDTH-1:0] display_address;
    logic [19:0] debounce_counter0, debounce_counter1;
    logic        key0_sync1, key0_sync2, key0_stable;
    logic        key1_sync1, key1_sync2, key1_stable;
    logic        key0_prev, key1_prev;
    logic        key0_edge, key1_edge;
    
    // Sincronizador KEY[0]
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            key0_sync1 <= 1'b1;
            key0_sync2 <= 1'b1;
        end else begin
            key0_sync1 <= KEY[0];
            key0_sync2 <= key0_sync1;
        end
    end
    
    // Sincronizador KEY[1]
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            key1_sync1 <= 1'b1;
            key1_sync2 <= 1'b1;
        end else begin
            key1_sync1 <= KEY[1];
            key1_sync2 <= key1_sync1;
        end
    end
    
    // Debounce KEY[0]
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            debounce_counter0 <= '0;
            key0_stable <= 1'b1;
        end else begin
            if (key0_sync2 == key0_stable) begin
                debounce_counter0 <= '0;
            end else begin
                debounce_counter0 <= debounce_counter0 + 1'b1;
                if (debounce_counter0 == DEBOUNCE_CYCLES) begin
                    key0_stable <= key0_sync2;
                end
            end
        end
    end
    
    // Debounce KEY[1]
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            debounce_counter1 <= '0;
            key1_stable <= 1'b1;
        end else begin
            if (key1_sync2 == key1_stable) begin
                debounce_counter1 <= '0;
            end else begin
                debounce_counter1 <= debounce_counter1 + 1'b1;
                if (debounce_counter1 == DEBOUNCE_CYCLES) begin
                    key1_stable <= key1_sync2;
                end
            end
        end
    end
    
    // Detectar flancos
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            key0_prev <= 1'b1;
            key1_prev <= 1'b1;
        end else begin
            key0_prev <= key0_stable;
            key1_prev <= key1_stable;
        end
    end
    
    always_comb begin
        key0_edge = (key0_prev == 1'b1) && (key0_stable == 1'b0);
        key1_edge = (key1_prev == 1'b1) && (key1_stable == 1'b0);
    end
    
    // Control de dirección de visualización
    localparam MAX_ADDR = MEM_SIZE - 1;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            display_address <= '0;
        end else begin
            if (key0_edge) begin
                if (display_address < MAX_ADDR)
                    display_address <= display_address + 1;
            end else if (key1_edge) begin
                if (display_address > 0)
                    display_address <= display_address - 1;
            end
        end
    end
    
    //========================================================
    // DSA (Domain-Specific Accelerator) CONTROL
    //========================================================
    logic dsa_start;
    logic dsa_start_prev;
    logic dsa_busy;
    logic dsa_ready;
    logic [15:0] dsa_progress;
    logic [31:0] dsa_flops_count;
    logic [31:0] dsa_mem_reads_count;
    logic [31:0] dsa_mem_writes_count;
    
    // Detector de flanco para start
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dsa_start <= 1'b0;
            dsa_start_prev <= 1'b0;
        end else begin
            dsa_start_prev <= dsa_start_trigger;
            dsa_start <= (dsa_start_trigger && !dsa_start_prev);
        end
    end
    
    //========================================================
    // MULTIPLEXOR DE ACCESO A MEMORIA
    // Prioridad: DSA > JTAG > Visualización
    //========================================================
    logic                   mem_read_en;
    logic                   mem_write_en;
    logic [ADDR_WIDTH-1:0]  mem_addr;
    logic [7:0]             mem_data_in;
    logic [7:0]             mem_data_out;
    
    // Señales DSA
    logic                   dsa_mem_write_en;
    logic                   dsa_mem_read_en;
    logic [ADDR_WIDTH-1:0]  dsa_mem_addr;
    logic [7:0]             dsa_mem_data_in;
    logic [7:0]             dsa_mem_data_out;
    
    // Señal de lectura para visualización
    logic [7:0] display_data_reg;
    
    // Arbitraje de memoria
    always_comb begin
        if (dsa_mem_write_en || dsa_mem_read_en) begin
            // DSA tiene máxima prioridad
            mem_write_en = dsa_mem_write_en;
            mem_read_en  = dsa_mem_read_en;
            mem_addr     = dsa_mem_addr;
            mem_data_in  = dsa_mem_data_in;
        end else if (jtag_mem_write_en) begin
            // JTAG escritura
            mem_write_en = 1'b1;
            mem_read_en  = 1'b0;
            mem_addr     = jtag_mem_address;
            mem_data_in  = jtag_write_data_reg;
        end else begin
            // Lectura continua para visualización
            mem_write_en = 1'b0;
            mem_read_en  = 1'b1;
            mem_addr     = display_address;
            mem_data_in  = 8'd0;
        end
    end
    
    // Registro de dato leído para visualización
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            display_data_reg <= '0;
        end else begin
            display_data_reg <= mem_data_out;
        end
    end
    
    // Dato de retorno para JTAG READ
    assign jtag_data_in = mem_data_out;
    
    //========================================================
    // INSTANCIA: Virtual JTAG IP Core
    //========================================================
    vjtag_dsa u_vjtag_dsa (
        .tdi                (vjtag_tdi),
        .tdo                (vjtag_tdo),
        .ir_in              (vjtag_ir_in),
        .ir_out             (vjtag_ir_out),
        .virtual_state_cdr  (vjtag_v_cdr),
        .virtual_state_sdr  (vjtag_v_sdr),
        .virtual_state_e1dr (),
        .virtual_state_pdr  (),
        .virtual_state_e2dr (),
        .virtual_state_udr  (vjtag_v_udr),
        .virtual_state_cir  (),
        .virtual_state_uir  (),
        .tck                (vjtag_tck)
    );
    
    //========================================================
    // INSTANCIA: VJTAG Interface
    //========================================================
    vjtag_interface #(
        .DW(DATA_WIDTH)
    ) u_vjtag_interface (
        .tck        (vjtag_tck),
        .tdi        (vjtag_tdi),
        .aclr       (rst_n),
        .ir_in      (vjtag_ir_in),
        .v_sdr      (vjtag_v_sdr),
        .v_cdr      (vjtag_v_cdr),
        .udr        (vjtag_v_udr),
        .data_out   (jtag_data_out),
        .data_in    (jtag_data_in),
        .addr_out   (jtag_addr_out),
        .tdo        (vjtag_tdo),
        .debug_dr1  (),
        .debug_dr2  ()
    );
    
    //========================================================
    // INSTANCIA: DSA Top (Bilinear Interpolation Accelerator)
    //========================================================
    dsa_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .SIMD_WIDTH(SIMD_WIDTH),
        .MEM_SIZE(MEM_SIZE)
    ) u_dsa_top (
        .clk                (clk),
        .rst                (rst),
        .start              (dsa_start),
        .mode_simd          (mode_simd),
        .img_width_in       (16'd512),         // Parámetro fijo por ahora
        .img_height_in      (16'd512),         // Parámetro fijo por ahora
        .scale_factor       (8'd128),          // 0.5x (Q8.8 format)
        
        // Puerto externo de memoria (conectado al multiplexor)
        .ext_mem_write_en   (dsa_mem_write_en),
        .ext_mem_read_en    (dsa_mem_read_en),
        .ext_mem_addr       (dsa_mem_addr),
        .ext_mem_data_in    (dsa_mem_data_in),
        .ext_mem_data_out   (dsa_mem_data_out),
        
        // Estado y contadores
        .busy               (dsa_busy),
        .ready              (dsa_ready),
        .progress           (dsa_progress),
        .flops_count        (dsa_flops_count),
        .mem_reads_count    (dsa_mem_reads_count),
        .mem_writes_count   (dsa_mem_writes_count)
    );
    
    // Conectar salida de memoria DSA
    assign dsa_mem_data_in = mem_data_out;
    
    //========================================================
    // INSTANCIA: Memoria RAM Bankeada
    //========================================================
    dsa_mem_banked #(
        .MEM_SIZE(MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_memory (
        .clk(clk),
        
        // Puerto de lectura
        .read_en(mem_read_en),
        .read_addr(mem_addr),
        .read_data(mem_data_out),
        
        // Puerto de escritura simple
        .write_en(mem_write_en),
        .write_addr(mem_addr),
        .write_data(mem_data_in),
        
        // Escritura SIMD deshabilitada (DSA maneja internamente)
        .simd_write_en(1'b0),
        .simd_base_addr('0),
        .simd_data_0('0),
        .simd_data_1('0),
        .simd_data_2('0),
        .simd_data_3('0)
    );
    
    //========================================================
    // LEDs INDICADORES
    //========================================================
    assign LEDR[0] = jtag_mem_write_en;       // JTAG escribiendo
    assign LEDR[1] = key0_edge | key1_edge;   // Botones presionados
    assign LEDR[2] = jtag_data_valid;         // Dato JTAG válido
    assign LEDR[3] = display_mode;            // Modo visualización
    assign LEDR[4] = dsa_busy;                // DSA trabajando
    assign LEDR[5] = dsa_ready;               // DSA terminado
    assign LEDR[6] = mode_simd;               // Modo SIMD activo
    assign LEDR[7] = dsa_start_trigger;       // Start DSA
    assign LEDR[8] = (display_address == MAX_ADDR);  // Límite superior
    assign LEDR[9] = (display_address == 0);         // Límite inferior
    
    //========================================================
    // 7-SEGMENT DISPLAYS
    //========================================================
    function logic [6:0] hex7seg(input logic [3:0] hex);
        case (hex)
            4'h0: hex7seg = 7'b1000000;
            4'h1: hex7seg = 7'b1111001;
            4'h2: hex7seg = 7'b0100100;
            4'h3: hex7seg = 7'b0110000;
            4'h4: hex7seg = 7'b0011001;
            4'h5: hex7seg = 7'b0010010;
            4'h6: hex7seg = 7'b0000010;
            4'h7: hex7seg = 7'b1111000;
            4'h8: hex7seg = 7'b0000000;
            4'h9: hex7seg = 7'b0010000;
            4'hA: hex7seg = 7'b0001000;
            4'hB: hex7seg = 7'b0000011;
            4'hC: hex7seg = 7'b1000110;
            4'hD: hex7seg = 7'b0100001;
            4'hE: hex7seg = 7'b0000110;
            4'hF: hex7seg = 7'b0001110;
            default: hex7seg = 7'b1111111;
        endcase
    endfunction
    
    logic [7:0] displayed_value;
    
    always_comb begin
        if (display_mode == 1'b0) begin
            // Modo JTAG: Mostrar dato leído de memoria
            displayed_value = display_data_reg;
        end else begin
            // Modo DSA: Mostrar progreso
            displayed_value = dsa_progress[7:0];
        end
    end
    
    // HEX5-4: Dirección de visualización (2 nibbles = 8 bits)
    assign HEX5 = hex7seg(display_address[7:4]);
    assign HEX4 = hex7seg(display_address[3:0]);
    
    // HEX3-0: Dato visualizado
    assign HEX3 = hex7seg(displayed_value[7:4]);
    assign HEX2 = hex7seg(displayed_value[3:0]);
    
    // HEX1-0: Indicador de modo
    // "Jt" = JTAG mode, "dS" = DSA mode
    assign HEX1 = display_mode ? 7'b0100001 : 7'b0001010;  // d o J
    assign HEX0 = display_mode ? 7'b0010010 : 7'b0000111;  // S o t

endmodule
