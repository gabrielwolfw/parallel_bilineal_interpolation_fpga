// ============================================================================
// dsa_register_bank.sv
// 
// Memory-Mapped Register Bank for DSA Control and Status
// 
// Address Map (Aligned 32-bit / 16-bit / 8-bit):
//   0x00000000 - 0x0000003F: Core Configuration and Status (16 registers × 4 bytes)
//   0x00000040 - 0x0000007F: Reserved for future expansion
//   0x00000080 - 0x00007FFF: Input Image Memory (32KB - 512 bytes)
//   0x00008000 - 0x0000FFFF: Output Image Memory (32KB)
//
// Register Map (Word-Aligned):
//   0x00: CFG_WIDTH       [15:0]  - Image input width
//   0x04: CFG_HEIGHT      [15:0]  - Image input height
//   0x08: CFG_SCALE_Q8_8  [15:0]  - Scale factor Q8.8 format
//   0x0C: CFG_MODE        [7:0]   - Control: start, SIMD mode, index
//   0x10: STATUS          [31:0]  - busy, ready, error, progress
//   0x14: SIMD_N          [7:0]   - Number of SIMD lanes
//   0x18: PERF_FLOPS      [31:0]  - Arithmetic operations counter
//   0x1C: PERF_MEM_RD     [31:0]  - BRAM read operations
//   0x20: PERF_MEM_WR     [31:0]  - BRAM write operations
//   0x24: STEP_CTRL       [7:0]   - Stepping mode control
//   0x28: STEP_EXPOSE     [31:0]  - Buffer exposure pointer
//   0x2C: ERR_CODE        [15:0]  - Error diagnostic code
//   0x30: IMG_IN_BASE     [31:0]  - Input image base offset
//   0x34: IMG_OUT_BASE    [31:0]  - Output image base offset
//   0x38: CRC_CTRL        [7:0]   - CRC enable control
//   0x3C: CRC_VALUE       [31:0]  - CRC32 result
//
// Author: DSA Team
// Date: 2025-12-04
// ============================================================================

module dsa_register_bank (
    input  wire        clk,
    input  wire        reset_n,
    
    // Memory interface (8-bit bus)
    input  wire [15:0] addr,
    input  wire [7:0]  wdata,
    input  wire        wr_en,
    input  wire        rd_en,
    output logic [7:0] rdata,
    output logic       reg_hit,      // 1 if addr is register, 0 if RAM
    
    // Configuration Outputs (to DSA modules)
    output logic [15:0] cfg_width,
    output logic [15:0] cfg_height,
    output logic [15:0] cfg_scale_q8_8,
    output logic        cfg_start,        // Pulse
    output logic        cfg_mode_simd,    // 1=SIMD, 0=SEQ
    output logic [5:0]  cfg_simd_idx,     // SIMD_N index
    output logic [7:0]  cfg_simd_n,       // Number of lanes
    output logic [31:0] cfg_img_in_base,
    output logic [31:0] cfg_img_out_base,
    output logic        cfg_crc_in_en,
    output logic        cfg_crc_out_en,
    output logic [7:0]  cfg_step_ctrl,
    output logic        cfg_soft_reset,   // Pulse
    output logic        cfg_clear_errors, // Pulse
    
    // Status Inputs (from DSA modules)
    input  wire        status_idle,
    input  wire        status_busy,
    input  wire        status_done,
    input  wire        status_error,
    input  wire [7:0]  status_progress,   // 0-100%
    input  wire [15:0] status_fsm_state,
    input  wire [15:0] err_code,
    input  wire [15:0] out_width,
    input  wire [15:0] out_height,
    input  wire [15:0] progress_x,
    input  wire [15:0] progress_y,
    
    // Performance Counters (from DSA modules)
    input  wire [31:0] perf_flops,
    input  wire [31:0] perf_mem_rd,
    input  wire [31:0] perf_mem_wr,
    input  wire [31:0] cycle_count,
    input  wire [31:0] pixels_done,
    input  wire [15:0] fetch_latency,
    input  wire [15:0] interp_latency,
    
    // Debug Inputs
    input  wire [7:0]  dbg_state,
    input  wire [15:0] dbg_last_addr,
    input  wire [31:0] step_expose,
    input  wire [31:0] crc_value
);

    // ========================================================================
    // Register Definitions (Word-Aligned, matches provided table exactly)
    // ========================================================================
    
    // Configuration Registers (RW)
    logic [15:0] reg_cfg_width;           // 0x00-0x01 (0x00000000)
    logic [15:0] reg_cfg_height;          // 0x04-0x05 (0x00000004)
    logic [15:0] reg_cfg_scale_q8_8;      // 0x08-0x09 (0x00000008)
    logic [7:0]  reg_cfg_mode;            // 0x0C      (0x0000000C)
    logic [7:0]  reg_simd_n;              // 0x14      (0x00000014)
    logic [7:0]  reg_step_ctrl;           // 0x24      (0x00000024)
    logic [31:0] reg_img_in_base;         // 0x30-0x33 (0x00000030)
    logic [31:0] reg_img_out_base;        // 0x34-0x37 (0x00000034)
    logic [7:0]  reg_crc_ctrl;            // 0x38      (0x00000038)
    
    // Start pulse generation
    logic cfg_start_prev;
    
    // ========================================================================
    // Version and Capabilities (Read-Only Constants)
    // ========================================================================
    
    localparam [31:0] VERSION      = 32'h01_00_0001;  // v1.0.1
    localparam [31:0] CAPABILITIES = 32'h00000007;    // [0]=SIMD, [1]=CRC, [2]=Stepping
    
    // ========================================================================
    // Address Decoder (Optimized for Word-Aligned Access)
    // ========================================================================
    
    // Register space: 0x00000000 - 0x0000003F (64 bytes, 16 words)
    wire is_reg_space = (addr[15:6] == 10'h000);  // First 64 bytes only
    assign reg_hit = is_reg_space;
    
    wire [5:0] reg_addr = addr[5:0];  // Byte offset 0-63 within register space
    
    // ========================================================================
    // Register Write Logic (Word-Aligned Addresses)
    // ========================================================================
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Reset to safe defaults
            reg_cfg_width       <= 16'd256;
            reg_cfg_height      <= 16'd256;
            reg_cfg_scale_q8_8  <= 16'h00C0;  // 0.75 (192/256)
            reg_cfg_mode        <= 8'h00;
            reg_simd_n          <= 8'd1;      // Sequential mode default
            reg_step_ctrl       <= 8'h00;     // Run mode
            reg_img_in_base     <= 32'h0000_0080;  // Start after registers
            reg_img_out_base    <= 32'h0000_8000;  // Second half of memory
            reg_crc_ctrl        <= 8'h00;
        end else begin
            // Auto-clear start bit after 1 cycle (pulse behavior)
            if (reg_cfg_mode[0]) begin
                reg_cfg_mode[0] <= 1'b0;
            end
            
            // Register writes (byte-addressable with word alignment)
            if (wr_en && is_reg_space) begin
                case (reg_addr)
                    // CFG_WIDTH (0x00-0x03) - only [15:0] used
                    6'h00: reg_cfg_width[7:0]   <= wdata;
                    6'h01: reg_cfg_width[15:8]  <= wdata;
                    
                    // CFG_HEIGHT (0x04-0x07) - only [15:0] used
                    6'h04: reg_cfg_height[7:0]  <= wdata;
                    6'h05: reg_cfg_height[15:8] <= wdata;
                    
                    // CFG_SCALE_Q8_8 (0x08-0x0B) - only [15:0] used
                    6'h08: reg_cfg_scale_q8_8[7:0]  <= wdata;
                    6'h09: reg_cfg_scale_q8_8[15:8] <= wdata;
                    
                    // CFG_MODE (0x0C-0x0F) - only [7:0] used
                    6'h0C: reg_cfg_mode <= wdata;
                    
                    // SIMD_N (0x14-0x17) - only [7:0] used
                    6'h14: reg_simd_n <= wdata;
                    
                    // STEP_CTRL (0x24-0x27) - only [7:0] used
                    6'h24: reg_step_ctrl <= wdata;
                    
                    // IMG_IN_BASE (0x30-0x33) - full [31:0]
                    6'h30: reg_img_in_base[7:0]   <= wdata;
                    6'h31: reg_img_in_base[15:8]  <= wdata;
                    6'h32: reg_img_in_base[23:16] <= wdata;
                    6'h33: reg_img_in_base[31:24] <= wdata;
                    
                    // IMG_OUT_BASE (0x34-0x37) - full [31:0]
                    6'h34: reg_img_out_base[7:0]   <= wdata;
                    6'h35: reg_img_out_base[15:8]  <= wdata;
                    6'h36: reg_img_out_base[23:16] <= wdata;
                    6'h37: reg_img_out_base[31:24] <= wdata;
                    
                    // CRC_CTRL (0x38-0x3B) - only [7:0] used
                    6'h38: reg_crc_ctrl <= wdata;
                    
                    default: ; // Ignore writes to read-only or reserved
                endcase
            end
        end
    end
    
    // ========================================================================
    // Register Read Logic (Optimized for Word-Aligned Access)
    // ========================================================================
    
    always_comb begin
        rdata = 8'h00;
        
        if (rd_en && is_reg_space) begin
            case (reg_addr)
                // CFG_WIDTH (0x00-0x03)
                6'h00: rdata = reg_cfg_width[7:0];
                6'h01: rdata = reg_cfg_width[15:8];
                6'h02: rdata = 8'h00;  // Upper 16 bits reserved
                6'h03: rdata = 8'h00;
                
                // CFG_HEIGHT (0x04-0x07)
                6'h04: rdata = reg_cfg_height[7:0];
                6'h05: rdata = reg_cfg_height[15:8];
                6'h06: rdata = 8'h00;
                6'h07: rdata = 8'h00;
                
                // CFG_SCALE_Q8_8 (0x08-0x0B)
                6'h08: rdata = reg_cfg_scale_q8_8[7:0];
                6'h09: rdata = reg_cfg_scale_q8_8[15:8];
                6'h0A: rdata = 8'h00;
                6'h0B: rdata = 8'h00;
                
                // CFG_MODE (0x0C-0x0F)
                6'h0C: rdata = reg_cfg_mode;
                6'h0D: rdata = 8'h00;
                6'h0E: rdata = 8'h00;
                6'h0F: rdata = 8'h00;
                
                // STATUS (0x10-0x13) - Read-Only
                6'h10: rdata = {4'h0, status_error, status_done, status_busy, status_idle};
                6'h11: rdata = status_progress;
                6'h12: rdata = status_fsm_state[7:0];
                6'h13: rdata = status_fsm_state[15:8];
                
                // SIMD_N (0x14-0x17)
                6'h14: rdata = reg_simd_n;
                6'h15: rdata = 8'h00;
                6'h16: rdata = 8'h00;
                6'h17: rdata = 8'h00;
                
                // PERF_FLOPS (0x18-0x1B) - Read-Only
                6'h18: rdata = perf_flops[7:0];
                6'h19: rdata = perf_flops[15:8];
                6'h1A: rdata = perf_flops[23:16];
                6'h1B: rdata = perf_flops[31:24];
                
                // PERF_MEM_RD (0x1C-0x1F) - Read-Only
                6'h1C: rdata = perf_mem_rd[7:0];
                6'h1D: rdata = perf_mem_rd[15:8];
                6'h1E: rdata = perf_mem_rd[23:16];
                6'h1F: rdata = perf_mem_rd[31:24];
                
                // PERF_MEM_WR (0x20-0x23) - Read-Only
                6'h20: rdata = perf_mem_wr[7:0];
                6'h21: rdata = perf_mem_wr[15:8];
                6'h22: rdata = perf_mem_wr[23:16];
                6'h23: rdata = perf_mem_wr[31:24];
                
                // STEP_CTRL (0x24-0x27)
                6'h24: rdata = reg_step_ctrl;
                6'h25: rdata = 8'h00;
                6'h26: rdata = 8'h00;
                6'h27: rdata = 8'h00;
                
                // STEP_EXPOSE (0x28-0x2B) - Read-Only
                6'h28: rdata = step_expose[7:0];
                6'h29: rdata = step_expose[15:8];
                6'h2A: rdata = step_expose[23:16];
                6'h2B: rdata = step_expose[31:24];
                
                // ERR_CODE (0x2C-0x2F) - Read-Only
                6'h2C: rdata = err_code[7:0];
                6'h2D: rdata = err_code[15:8];
                6'h2E: rdata = 8'h00;
                6'h2F: rdata = 8'h00;
                
                // IMG_IN_BASE (0x30-0x33)
                6'h30: rdata = reg_img_in_base[7:0];
                6'h31: rdata = reg_img_in_base[15:8];
                6'h32: rdata = reg_img_in_base[23:16];
                6'h33: rdata = reg_img_in_base[31:24];
                
                // IMG_OUT_BASE (0x34-0x37)
                6'h34: rdata = reg_img_out_base[7:0];
                6'h35: rdata = reg_img_out_base[15:8];
                6'h36: rdata = reg_img_out_base[23:16];
                6'h37: rdata = reg_img_out_base[31:24];
                
                // CRC_CTRL (0x38-0x3B)
                6'h38: rdata = reg_crc_ctrl;
                6'h39: rdata = 8'h00;
                6'h3A: rdata = 8'h00;
                6'h3B: rdata = 8'h00;
                
                // CRC_VALUE (0x3C-0x3F) - Read-Only
                6'h3C: rdata = crc_value[7:0];
                6'h3D: rdata = crc_value[15:8];
                6'h3E: rdata = crc_value[23:16];
                6'h3F: rdata = crc_value[31:24];
                
                default: rdata = 8'h00;  // Reserved registers return 0
            endcase
        end
    end
    
    // ========================================================================
    // Output Assignments
    // ========================================================================
    
    assign cfg_width        = reg_cfg_width;
    assign cfg_height       = reg_cfg_height;
    assign cfg_scale_q8_8   = reg_cfg_scale_q8_8;
    assign cfg_mode_simd    = reg_cfg_mode[1];
    assign cfg_simd_idx     = reg_cfg_mode[7:2];
    assign cfg_simd_n       = reg_simd_n;
    assign cfg_img_in_base  = reg_img_in_base;
    assign cfg_img_out_base = reg_img_out_base;
    assign cfg_crc_in_en    = reg_crc_ctrl[0];
    assign cfg_crc_out_en   = reg_crc_ctrl[1];
    assign cfg_step_ctrl    = reg_step_ctrl;
    
    // Pulse generation for start signal (rising edge detection)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cfg_start_prev <= 1'b0;
        end else begin
            cfg_start_prev <= reg_cfg_mode[0];
        end
    end
    assign cfg_start = reg_cfg_mode[0] && !cfg_start_prev;
    
    // Removed: soft reset and clear errors (not in provided register table)
    assign cfg_soft_reset = 1'b0;
    assign cfg_clear_errors = 1'b0;

endmodule
