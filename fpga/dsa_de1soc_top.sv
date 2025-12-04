//============================================================
// dsa_de1soc_top.sv
// Top-level para DE1-SoC con comunicación JTAG
// 
// Control:
//   SW[9]: Reset general
//   SW[0]: Modo visualización: 0=Modo Read, 1=Modo JTAG
//   SW[1]: Contenido: 0=Data, 1=Address
//   
//   KEY[3]: Reset (activo bajo)
//   KEY[0]: Incrementar dirección de visualización
//   KEY[1]: Decrementar dirección de visualización
//
// HEX Displays:
//   HEX5-2: Data o Address según SW[1]
//   HEX1-0: Indicador de modo (rd/rA/Jd/JA)
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
    logic display_mode;      // SW[0]: 0=Modo Read, 1=Modo JTAG
    logic display_content;   // SW[1]: 0=Mostrar Data, 1=Mostrar Address
    
    assign display_mode = SW[0];       // 0=Modo Read, 1=Modo JTAG
    assign display_content = SW[1];    // 0=Data, 1=Address
    
    //========================================================
    // VIRTUAL JTAG IP CORE SIGNALS
    //========================================================
    wire        vjtag_tdi;
    wire        vjtag_tdo;
    wire [1:0]  vjtag_ir_in;
    wire [1:0]  vjtag_ir_out;
    wire        vjtag_v_cdr;
    wire        vjtag_v_sdr;
    wire        vjtag_v_udr;     // Update-DR: pulso cuando se completa transferencia
    wire        vjtag_tck;       // TCK: reloj JTAG independiente de CLK
    
    //========================================================
    // VJTAG INTERFACE SIGNALS
    //========================================================
    logic [DATA_WIDTH-1:0] jtag_data_out;  // PC → FPGA (WRITE, dominio TCK)
    logic [DATA_WIDTH-1:0] jtag_data_in;   // FPGA → PC (READ, dominio CLK)
    logic [ADDR_WIDTH-1:0] jtag_addr_out;  // Dirección desde SETADDR (dominio TCK, 18 bits)
    
    //========================================================
    // SINCRONIZACIÓN JTAG → CLK DOMAIN CON FSM
    // FSM que maneja sincronización de dominio de reloj y control de memoria
    //========================================================
    
    // Decodificación de instrucciones (mismos valores que vjtag_interface.sv)
    localparam [1:0] IR_BYPASS   = 2'b00;
    localparam [1:0] IR_WRITE    = 2'b01;
    localparam [1:0] IR_READ     = 2'b10;
    localparam [1:0] IR_SET_ADDR = 2'b11;
    
    // FSM de JTAG
    typedef enum logic [2:0] {
        IDLE, 
        SET_ADDR, 
        WAIT_SET_ADDR, 
        WRITE, 
        WAIT_WRITE, 
        READ, 
        WAIT_READ
    } jtag_fsm_t;
    
    jtag_fsm_t jtag_state;
    
    // Señales de sincronización de 2 etapas (metaestabilidad)
    logic [1:0] ir_in_meta, ir_in_sync;
    logic udr_meta, udr_sync, udr_prev;
    logic udr_edge;  // Pulso de flanco ascendente de UDR
    logic [DATA_WIDTH-1:0] jtag_data_meta, jtag_data_sync;
    logic [ADDR_WIDTH-1:0] jtag_addr_meta, jtag_addr_sync;
    
    // Señales sincronizadas para control de memoria
    logic [ADDR_WIDTH-1:0] ram_addr_jtag_internal;
    logic [DATA_WIDTH-1:0] jtag_display_data;
    logic [ADDR_WIDTH-1:0] jtag_display_addr_reg;  // Registro para mostrar dirección completa (18 bits)
    logic ram_wren_jtag_internal;
    
    // FSM con sincronización integrada
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset de sincronizadores
            ir_in_meta <= '0;
            ir_in_sync <= '0;
            udr_meta <= 1'b0;
            udr_sync <= 1'b0;
            udr_prev <= 1'b0;
            jtag_data_meta <= '0;
            jtag_data_sync <= '0;
            jtag_addr_meta <= '0;
            jtag_addr_sync <= '0;
            
            // Reset de señales internas
            ram_addr_jtag_internal <= '0;
            jtag_display_data <= '0;
            jtag_display_addr_reg <= '0;
            ram_wren_jtag_internal <= 1'b0;
            jtag_state <= IDLE;
        end else begin
            // Sincronización de 2 etapas para cruce de dominio TCK → CLK
            ir_in_meta <= vjtag_ir_in;
            ir_in_sync <= ir_in_meta;
            
            udr_meta <= vjtag_v_udr;
            udr_sync <= udr_meta;
            udr_prev <= udr_sync;
            
            jtag_data_meta <= jtag_data_out;
            jtag_data_sync <= jtag_data_meta;
            
            jtag_addr_meta <= jtag_addr_out;
            jtag_addr_sync <= jtag_addr_meta;
            
            // Por defecto, desactiva escritura
            ram_wren_jtag_internal <= 1'b0;

            // FSM de control JTAG
            case (jtag_state)
                IDLE: begin
                        if (ir_in_sync == IR_SET_ADDR) begin
                            // SET_ADDR detectado: actualizar dirección
                            ram_addr_jtag_internal <= jtag_addr_sync;
                            jtag_display_addr_reg <= jtag_addr_sync;  // Guardar dirección completa (18 bits)
                            jtag_state <= SET_ADDR;
                        end else if (ir_in_sync == IR_WRITE) begin
                            // WRITE detectado: preparar escritura
                            jtag_display_data <= jtag_data_sync;  // Guardar dato para display
                            jtag_state <= WRITE;
                        end else if (ir_in_sync == IR_READ) begin
                            // READ detectado
                            jtag_state <= READ;
                        end
                end
                
                SET_ADDR: begin
                    // Esperar 1 ciclo para propagación de dirección al MUX
                    jtag_state <= WAIT_SET_ADDR;
                end
                
                WAIT_SET_ADDR: begin
                    // Esperar otro ciclo para que la RAM responda
                    // (la RAM dual-port tiene latencia de 1 ciclo)
                    jtag_state <= IDLE;
                end
                
                WRITE: begin
                    // Activar escritura en este ciclo
                    ram_wren_jtag_internal <= 1'b1;
                    jtag_state <= WAIT_WRITE;
                end
                
                WAIT_WRITE: begin
                    // Mantener escritura activa un ciclo más
                    ram_wren_jtag_internal <= 1'b0;
                    jtag_state <= IDLE;
                end
                
                READ: begin
                    // Esperar 1 ciclo para propagación
                    jtag_state <= WAIT_READ;
                end
                
                WAIT_READ: begin
                    // Capturar dato leído (después de latencia de RAM)
                    jtag_display_data <= mem_data_out;
                    jtag_state <= IDLE;
                end
                
                default: begin
                    jtag_state <= IDLE;
                end
            endcase
        end
    end
    
    // Detector de flanco ascendente de UDR
    assign udr_edge = udr_sync & ~udr_prev;
    
    //========================================================
    // SEÑALES DE CONTROL DERIVADAS DE LA FSM
    //========================================================
    logic [ADDR_WIDTH-1:0] jtag_mem_address;    // Dirección de memoria JTAG
    logic [7:0]            jtag_write_data_reg; // Dato a escribir
    logic                  jtag_mem_write_en;   // Enable de escritura JTAG
    
    // Asignar señales desde la FSM
    assign jtag_mem_address = ram_addr_jtag_internal;
    assign jtag_write_data_reg = jtag_display_data;
    assign jtag_mem_write_en = ram_wren_jtag_internal;
    
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
    // MULTIPLEXOR DE ACCESO A MEMORIA
    // Prioridad: JTAG > Visualización
    //========================================================
    
    // Señales intermedias del multiplexor
    logic [ADDR_WIDTH-1:0]  ram_addr_jtag;      // ✅ Corregido: debe ser vector
    logic                   ram_we_jtag;
    logic [ADDR_WIDTH-1:0]  ram_addr_mux;
    logic [7:0]             ram_data_in_mux;
    logic                   ram_we_mux;
    
    // Señales finales de memoria
    logic                   mem_read_en;
    logic                   mem_write_en;
    logic [ADDR_WIDTH-1:0]  mem_addr;
    logic [7:0]             mem_data_in;
    logic [7:0]             mem_data_out;
    
    // Señal de lectura para visualización
    logic [7:0] display_data_reg;
    
    // Multiplexor JTAG: Dirección
    assign ram_addr_jtag = jtag_mem_address;
    
    // Multiplexor JTAG: Write Enable
    assign ram_we_jtag = jtag_mem_write_en;
    
    // MULTIPLEXOR PRINCIPAL: Selección entre JTAG y visualización
    assign ram_addr_mux = ram_we_jtag ? ram_addr_jtag : display_address;
    
    assign ram_data_in_mux = jtag_write_data_reg;
    
    assign ram_we_mux = ram_we_jtag;
    
    // Asignación a señales de memoria
    assign mem_addr = ram_addr_mux;
    assign mem_data_in = ram_data_in_mux;
    assign mem_write_en = ram_we_mux;
    assign mem_read_en = ~mem_write_en;  // Siempre leer cuando no se escribe
    
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
        .DW(DATA_WIDTH),
        .AW(ADDR_WIDTH)  // 18 bits de dirección
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
    // INSTANCIA: Memoria RAM Dual-Port (Intel IP)
    // Puerto A (wraddress): Escritura
    // Puerto B (rdaddress): Lectura
    //========================================================
    ram u_memory (
        .clock      (clk),
        
        // Puerto de escritura (Puerto A)
        .wraddress  (mem_addr),
        .data       (mem_data_in),
        .wren       (mem_write_en),
        
        // Puerto de lectura (Puerto B)
        .rdaddress  (mem_addr),
        .q          (mem_data_out)
    );
    
    //========================================================
    // LEDs INDICADORES (DEBUG)
    //========================================================
    assign LEDR[0] = jtag_mem_write_en;       // JTAG escribiendo a RAM
    assign LEDR[1] = (jtag_state == SET_ADDR) || (jtag_state == WAIT_SET_ADDR);  // SETADDR activo
    assign LEDR[2] = (jtag_state == WRITE) || (jtag_state == WAIT_WRITE);        // WRITE activo
    assign LEDR[3] = mem_write_en;            // Escritura real a RAM
    assign LEDR[4] = mem_read_en;             // Lectura de RAM
    assign LEDR[5] = 1'b0;                    // (reservado)
    assign LEDR[6] = 1'b0;                    // (reservado)
    assign LEDR[7] = (jtag_state != IDLE);    // FSM JTAG activa (no en IDLE)
    assign LEDR[8] = jtag_mem_address[0];     // LSB de dirección JTAG
    assign LEDR[9] = display_mode;            // Modo visualización
    
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
    
    logic [ADDR_WIDTH-1:0] current_data;     // Dato actual según modo
    logic [ADDR_WIDTH-1:0] current_address;  // Dirección actual según modo
    logic [ADDR_WIDTH-1:0] display_value;    // Valor a mostrar en HEX5-2
    
    always_comb begin
        // Seleccionar dato y dirección según modo (SW[0])
        if (display_mode == 1'b0) begin
            // Modo Read: datos de navegación normal
            current_data = display_data_reg;
            current_address = display_address;
        end else begin
            // Modo JTAG: datos de operaciones JTAG
            current_data = jtag_display_data;
            current_address = jtag_display_addr_reg;
        end
        
        // Seleccionar qué mostrar en HEX5-2 según SW[1]
        if (display_content == 1'b0) begin
            // Mostrar Data en HEX5-2
            display_value = current_data;
        end else begin
            // Mostrar Address en HEX5-2
            display_value = current_address;
        end
    end
    
    // HEX5-2: Valor seleccionado (Data o Address según SW[1])
    assign HEX5 = hex7seg(display_value[15:12]);
    assign HEX4 = hex7seg(display_value[11:8]);
    assign HEX3 = hex7seg(display_value[7:4]);
    assign HEX2 = hex7seg(display_value[3:0]);
    
    // HEX1-0: Indicador de modo y contenido
    // SW[0]=0, SW[1]=0: "rd" (Read mode, Data)
    // SW[0]=0, SW[1]=1: "rA" (Read mode, Address)
    // SW[0]=1, SW[1]=0: "Jd" (JTAG mode, Data)
    // SW[0]=1, SW[1]=1: "JA" (JTAG mode, Address)
    always_comb begin
        if (display_mode == 1'b0) begin
            // Modo Read
            HEX1 = 7'b0101111;  // 'r'
            if (display_content == 1'b0)
                HEX0 = 7'b0100001;  // 'd'
            else
                HEX0 = 7'b0001000;  // 'A'
        end else begin
            // Modo JTAG
            HEX1 = 7'b0001010;  // 'J'
            if (display_content == 1'b0)
                HEX0 = 7'b0100001;  // 'd'
            else
                HEX0 = 7'b0001000;  // 'A'
        end
    end

endmodule
