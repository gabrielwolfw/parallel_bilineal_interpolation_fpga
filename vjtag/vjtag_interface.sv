module vjtag_interface #(
    parameter int DW = 8,
    parameter int AW = 16  // Ancho de dirección configurable (16 bits para 64KB)
) (
    input  wire        sys_clk,  // System clock para sincronización de salidas
    input  wire        aclr,
    output logic [(DW-1):0] data_out,   // Output data written from PC to FPGA
    input  wire  [(DW-1):0] data_in,    // Input data from FPGA to be read by PC
    output logic [(AW-1):0] addr_out,   // Dirección de AW bits (configurable)
    output logic [(DW-1):0] debug_dr2,  // debug port for reg DR2
    output logic [(DW-1):0] debug_dr1   // debug port for reg DR1
);

    // Señales del IP Virtual JTAG
    wire        tck;     // JTAG clock desde el IP
    wire        tdi;
    wire        tdo;
    wire [1:0]  ir_in;
    wire        v_cdr;
    wire        v_sdr;
    wire        udr;

    // Instancia del IP Virtual JTAG de Intel
    vjtag vjtag_ip (
        .tck(tck),       // TCK es SALIDA del IP, no entrada
        .tdi(tdi),
        .tdo(tdo),
        .ir_in(ir_in),
        .virtual_state_cdr(v_cdr),
        .virtual_state_sdr(v_sdr),
        .virtual_state_udr(udr)
    );

typedef enum logic [1:0] {
    BYPASS      = 2'b00,
    WRITE       = 2'b01,
    READ        = 2'b10,
    SET_ADDR    = 2'b11
} jtag_ir_state_t;

jtag_ir_state_t ir_state;

logic             DR0_bypass_reg; // 1-bit bypass register
logic [(DW-1):0]  DR1;            // Data Register 1: For writing data from PC to FPGA
logic [(AW-1):0]  DR_ADDR;        // Address Register: AW-bit address for SET_ADDR
logic [(DW-1):0]  DR2;            // Data Register 2: For reading data from FPGA to PC

//----------------------------------------------------------
// Bypass Register Logic (DR0)
//----------------------------------------------------------
always_ff @(posedge tck or negedge aclr) begin
    if (~aclr) begin
        DR0_bypass_reg <= 1'b0;
    end 
    else begin
        // Standard JTAG bypass register: captures '0', shifts TDI to TDO
        if (v_cdr && (ir_state == BYPASS)) begin
            DR0_bypass_reg <= 1'b0; // Capture '0'
        end 
        else if (v_sdr && (ir_state == BYPASS)) begin
            DR0_bypass_reg <= tdi;  // Shift
        end
    end
end

//----------------------------------------------------------
// Write Logic (DR1: PC → FPGA)
//----------------------------------------------------------
always_ff @(posedge tck or negedge aclr) begin
    if (~aclr) begin
        DR1 <= '0;
    end 
    else begin
        // Shift DR1 if WRITE instruction is active and in Shift-DR state
        if (v_sdr && (ir_state == WRITE)) begin
            DR1 <= {tdi, DR1[(DW-1):1]}; // Shifting in data from TDI
        end
    end
end

//----------------------------------------------------------
// Address Logic (DR_ADDR: PC → FPGA, AW bits)
//----------------------------------------------------------
always_ff @(posedge tck or negedge aclr) begin
    if (~aclr) begin
        DR_ADDR <= '0;
    end 
    else begin
        // Shift DR_ADDR if SET_ADDR instruction is active and in Shift-DR state
        if (v_sdr && (ir_state == SET_ADDR)) begin
            DR_ADDR <= {tdi, DR_ADDR[(AW-1):1]}; // Shifting in AW-bit address from TDI
        end
    end
end

//----------------------------------------------------------
// Read Logic (DR2: FPGA → PC)
//----------------------------------------------------------
always_ff @(posedge tck or negedge aclr) begin
    if (~aclr) begin
        DR2 <= '0;
    end else begin
        // Capture data_in into DR2 during Capture-DR state if READ instruction is active
        if (ir_state == READ) begin
            if (v_cdr) begin
                DR2 <= data_in;
            end
            else if (v_sdr) begin
                DR2 <= {tdi, DR2[(DW-1):1]}; // TDI is shifted in
            end
        end
    end
end

//----------------------------------------------------------
// Update Output Register (data_out) - Sincronizado a dominio del sistema
//----------------------------------------------------------
logic [(DW-1):0] data_out_jtag;  // Registro en dominio JTAG
logic [(AW-1):0] addr_out_jtag;  // Registro en dominio JTAG

// Captura en dominio JTAG
always_ff @(posedge tck or negedge aclr) begin
    if (~aclr) begin
        data_out_jtag <= '0;
    end else if (udr && (ir_state == WRITE)) begin
        data_out_jtag <= DR1;
    end
end

always_ff @(posedge tck or negedge aclr) begin
    if (~aclr) begin
        addr_out_jtag <= '0;
    end else if (udr && (ir_state == SET_ADDR)) begin
        addr_out_jtag <= DR_ADDR;
    end
end

// Sincronización a dominio del sistema (doble flip-flop)
logic [(DW-1):0] data_sync1, data_sync2;
logic [(AW-1):0] addr_sync1, addr_sync2;

always_ff @(posedge sys_clk or negedge aclr) begin
    if (~aclr) begin
        data_sync1 <= '0;
        data_sync2 <= '0;
        data_out <= '0;
        addr_sync1 <= '0;
        addr_sync2 <= '0;
        addr_out <= '0;
    end else begin
        // Primer etapa de sincronización
        data_sync1 <= data_out_jtag;
        addr_sync1 <= addr_out_jtag;
        // Segunda etapa de sincronización
        data_sync2 <= data_sync1;
        addr_sync2 <= addr_sync1;
        // Salida final
        data_out <= data_sync2;
        addr_out <= addr_sync2;
    end
end

//----------------------------------------------------------
// TDO Output Logic
//----------------------------------------------------------
always_comb begin
    case (ir_state)
        WRITE:   tdo = DR1[0];         // Output LSB of DR1 during write shift
        SET_ADDR:tdo = DR_ADDR[0];     // Output LSB of DR_ADDR during set_addr shift
        READ:    tdo = DR2[0];         // Output LSB of DR2 during read shift
        BYPASS:  tdo = DR0_bypass_reg; // Output bypass register during bypass shift
        default: tdo = DR0_bypass_reg; // Default to bypass
    endcase
end

assign debug_dr2 = DR2;
assign debug_dr1 = DR1;
assign ir_state = jtag_ir_state_t'(ir_in); // Cast ir_in to enum type

endmodule