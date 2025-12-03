//============================================================
// dsa_vjtag_mem_top.sv
// Top-level SIMPLIFICADO para escritura/lectura de memoria vía JTAG
// Permite: SETADDR -> WRITE/READ directo a memoria RAM
// Control:
//   SW[0]: 0=Ver datos JTAG recibidos, 1=Ver datos de memoria
//   KEY[0]: Incrementar dirección de lectura (con debounce)
//   KEY[1]: Decrementar dirección de lectura (con debounce)
//   HEX3-0: Muestra dato seleccionado (JTAG o memoria)
//============================================================

module dsa_vjtag_mem_top (
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
    // Parámetros
    //========================================================
    localparam DATA_WIDTH = 8;   // Ancho de datos VJTAG
    localparam ADDR_WIDTH = 18;  // Ancho de dirección de memoria
    localparam MEM_SIZE   = 262144; // 256KB
    
    //========================================================
    // Señales de reloj y reset
    //========================================================
    logic clk;
    logic rst_n;
    logic rst;
    
    assign clk = CLOCK_50;
    assign rst_n = KEY[3];  // KEY[3] como reset
    assign rst = ~rst_n;
    
    //========================================================
    // Señales Virtual JTAG IP (vjtag_dsa)
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
    // Señales VJTAG Interface
    //========================================================
    logic [DATA_WIDTH-1:0] jtag_data_out;  // PC -> FPGA (8 bits)
    logic [DATA_WIDTH-1:0] jtag_data_in;   // FPGA -> PC (8 bits)
    logic [14:0]           jtag_addr_out;  // Dirección desde SETADDR
    
    //========================================================
    // Máquina de estados para control de memoria
    //========================================================
    typedef enum logic [2:0] {
        ST_IDLE        = 3'd0,
        ST_WRITE_MEM   = 3'd1,
        ST_READ_MEM    = 3'd2,
        ST_WAIT        = 3'd3
    } state_t;
    
    state_t state, next_state;
    
    //========================================================
    // Registros internos
    //========================================================
    logic [ADDR_WIDTH-1:0] mem_address;      // Dirección de memoria para JTAG write
    logic [ADDR_WIDTH-1:0] display_address;  // Dirección para navegación y lectura
    logic [7:0]            write_data_reg;   // Dato a escribir desde JTAG
    logic [7:0]            read_data_reg;    // Dato leído desde JTAG
    logic [7:0]            display_data_reg; // Dato leído para visualización
    logic                  mem_write_en;
    logic                  mem_read_en;
    
    // Sincronización de JTAG (dominio tck) a clk del sistema
    logic [DATA_WIDTH-1:0] jtag_data_sync;
    logic [DATA_WIDTH-1:0] jtag_data_prev;
    logic                  jtag_data_valid;
    
    logic [14:0] jtag_addr_sync;
    logic [14:0] jtag_addr_prev;
    logic        jtag_addr_valid;
    
    //========================================================
    // Control de visualización con switches y botones
    //========================================================
    logic display_mode;              // 0=JTAG data, 1=Memory data
    logic key0_pressed, key1_pressed;
    logic key0_prev, key1_prev;
    
    assign display_mode = SW[0];
    
    //========================================================
    // Debounce simplificado para botones (~10ms @ 50MHz)
    //========================================================
    localparam DEBOUNCE_CYCLES = 500_000; // 10ms @ 50MHz
    
    logic [19:0] debounce_counter0;
    logic [19:0] debounce_counter1;
    logic        key0_sync1, key0_sync2, key0_stable;
    logic        key1_sync1, key1_sync2, key1_stable;
    logic        key0_edge, key1_edge;
    
    // Sincronizador de 2 flip-flops para KEY[0] (Incrementar dirección)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            key0_sync1 <= 1'b1;
            key0_sync2 <= 1'b1;
        end else begin
            key0_sync1 <= KEY[0];
            key0_sync2 <= key0_sync1;
        end
    end
    
    // Sincronizador de 2 flip-flops para KEY[1] (Decrementar dirección)
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
    
    // Detectar flanco de bajada (botón presionado) - KEY activo bajo
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            key0_prev <= 1'b1;
            key1_prev <= 1'b1;
        end else begin
            key0_prev <= key0_stable;
            key1_prev <= key1_stable;
        end
    end
    
    // Generar pulsos de edge (combinacional)
    always_comb begin
        key0_edge = (key0_prev == 1'b1) && (key0_stable == 1'b0);
        key1_edge = (key1_prev == 1'b1) && (key1_stable == 1'b0);
    end
    
    //========================================================
    // Control de dirección de visualización
    //========================================================
    localparam MAX_ADDR = MEM_SIZE - 1;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            display_address <= '0;
        end else begin
            if (key0_edge) begin
                // Incrementar con límite
                if (display_address < MAX_ADDR)
                    display_address <= display_address + 1;
            end else if (key1_edge) begin
                // Decrementar con límite (nunca menor que 0)
                if (display_address > 0)
                    display_address <= display_address - 1;
            end
        end
    end
    
    //========================================================
    // Sincronización de datos JTAG a dominio de reloj
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            jtag_data_sync <= '0;
            jtag_data_prev <= '0;
            jtag_data_valid <= 1'b0;
            jtag_addr_sync <= '0;
            jtag_addr_prev <= '0;
            jtag_addr_valid <= 1'b0;
        end else begin
            // Detectar cambio en datos WRITE
            jtag_data_prev <= jtag_data_sync;
            jtag_data_sync <= jtag_data_out;
            jtag_data_valid <= (jtag_data_sync != jtag_data_prev);
            
            // Detectar cambio en dirección SETADDR
            jtag_addr_prev <= jtag_addr_sync;
            jtag_addr_sync <= jtag_addr_out;
            jtag_addr_valid <= (jtag_addr_sync != jtag_addr_prev);
        end
    end
    
    //========================================================
    // Control de dirección de memoria
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_address <= '0;
        end else begin
            if (jtag_addr_valid) begin
                // Actualizar dirección cuando cambia vía SETADDR
                mem_address <= {3'b000, jtag_addr_sync};
            end else if (state == ST_WRITE_MEM || state == ST_READ_MEM) begin
                // Auto-incremento después de operación
                mem_address <= mem_address + 1;
            end
        end
    end
    
    //========================================================
    // FSM para control de memoria
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always_comb begin
        next_state = state;
        mem_write_en = 1'b0;
        mem_read_en = 1'b0;
        
        case (state)
            ST_IDLE: begin
                if (jtag_data_valid) begin
                    next_state = ST_WRITE_MEM;
                end
            end
            
            ST_WRITE_MEM: begin
                mem_write_en = 1'b1;
                next_state = ST_WAIT;
            end
            
            ST_WAIT: begin
                next_state = ST_IDLE;
            end
            
            default: next_state = ST_IDLE;
        endcase
    end
    
    //========================================================
    // Registro de datos de escritura
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_data_reg <= '0;
        end else if (jtag_data_valid) begin
            write_data_reg <= jtag_data_sync;
        end
    end
    
    //========================================================
    // Memoria RAM - Lectura continua para display
    //========================================================
    logic [7:0] mem_data_out;
    
    // Puerto de lectura: siempre leyendo la dirección de display
    // Puerto de escritura: controlado por JTAG
    
    dsa_mem_banked #(
        .MEM_SIZE(MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_memory (
        .clk(clk),
        
        // Puerto de lectura (siempre activo en dirección de display)
        .read_en(1'b1),  // Siempre leyendo
        .read_addr(display_address),  // Dirección de display
        .read_data(mem_data_out),
        
        // Puerto de escritura simple
        .write_en(mem_write_en),
        .write_addr(mem_address),
        .write_data(write_data_reg),
        
        // Escritura SIMD deshabilitada
        .simd_write_en(1'b0),
        .simd_base_addr('0),
        .simd_data_0('0),
        .simd_data_1('0),
        .simd_data_2('0),
        .simd_data_3('0)
    );
    
    //========================================================
    // Registro de datos para visualización
    // Se actualiza continuamente con el dato de la dirección actual
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data_reg <= '0;
            display_data_reg <= '0;
        end else begin
            // Actualizar registro de visualización continuamente
            display_data_reg <= mem_data_out;
            
            // Para lectura JTAG (comando READ)
            if (mem_read_en) begin
                read_data_reg <= mem_data_out;
            end
        end
    end
    
    // Salida al JTAG: devuelve el último dato leído
    assign jtag_data_in = read_data_reg;
    
    //========================================================
    // Virtual JTAG IP Core (vjtag_dsa)
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
    // VJTAG Interface
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
        .debug_dr1  (),  // No conectado
        .debug_dr2  ()   // No conectado
    );
    
    //========================================================
    // LEDs indicadores
    //========================================================
    assign LEDR[0] = mem_write_en;
    assign LEDR[1] = key0_edge | key1_edge;  // Pulso cuando cambia dirección
    assign LEDR[2] = jtag_data_valid;
    assign LEDR[3] = display_mode;        // 0=JTAG, 1=Memory
    assign LEDR[4] = key0_edge;           // Pulso incremento
    assign LEDR[5] = key1_edge;           // Pulso decremento
    assign LEDR[7:6] = state[1:0];
    assign LEDR[8] = (display_address == MAX_ADDR);  // En límite superior
    assign LEDR[9] = (display_address == 0);         // En límite inferior
    
    //========================================================
    // 7-Segment Display
    // HEX5-4: Dirección de visualización actual
    // HEX3-0: Dato (JTAG recibido o leído de memoria según SW[0])
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
    
    // Selección de dato a mostrar según SW[0]
    logic [7:0] displayed_value;
    
    always_comb begin
        if (display_mode == 1'b0) begin
            // Modo 0: Mostrar último dato JTAG recibido
            displayed_value = write_data_reg;
        end else begin
            // Modo 1: Mostrar dato leído de memoria
            displayed_value = display_data_reg;
        end
    end
    
    // HEX5-4: Dirección actual de visualización (2 dígitos hex = 8 bits)
    assign HEX5 = hex7seg(display_address[7:4]);    // Nibble alto de dirección
    assign HEX4 = hex7seg(display_address[3:0]);    // Nibble bajo de dirección
    
    // HEX3-0: Dato seleccionado (4 dígitos hex = 2 bytes, mostramos 1 byte)
    assign HEX3 = hex7seg(displayed_value[7:4]);    // Nibble alto de dato
    assign HEX2 = hex7seg(displayed_value[3:0]);    // Nibble bajo de dato
    
    // HEX1-0: Indicador de modo (opcional)
    // Muestra "Jt" en modo JTAG o "EA" (mEmory) en modo memoria
    assign HEX1 = display_mode ? 7'b0000110 : 7'b0001010;  // E o J
    assign HEX0 = display_mode ? 7'b0001000 : 7'b0000111;  // A o t

endmodule
