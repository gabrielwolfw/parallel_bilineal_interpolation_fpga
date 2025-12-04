# Copilot Instructions - Parallel Bilineal Interpolation FPGA

## Project Overview

This is an FPGA-based Domain-Specific Architecture (DSA) for image downscaling using parallel bilinear interpolation, targeting the Intel/Altera DE1-SoC board (Cyclone V 5CSEMA5F31C6). The project implements a PC-to-FPGA communication system via JTAG with a TCP bridge for debugging and memory access.

**Key Architecture**: This is NOT a traditional software project—it's a hardware design with a Python-based PC control interface and TCL JTAG server bridge.

## Project Structure

### Hardware
- **Top-level entity**: `dsa_top` (defined in `project_dsa.qsf`)
- **Main module**: `dsa_top.sv` - Top-level integration (VJTAG + RAM + manual controls) ✅ IMPLEMENTED
- **JTAG Interface**: `vjtag/vjtag_interface.sv` - Custom JTAG wrapper ✅ IMPLEMENTED
- **Future modules**: `dsa_datapath.sv`, `dsa_control_fsm.sv`, `dsa_mem_interface.sv` (for bilinear interpolation)
- **IP cores**: 
  - `vjtag/vjtag/` - Qsys-generated Virtual JTAG IP (sld_virtual_jtag)
  - `ram/ram.v` - Altsyncram dual-port memory (64KB)

### PC Interface (`vjtag_pc/`)
- **`jtag_server.tcl`**: TCL server that bridges TCP sockets to JTAG hardware (runs in Quartus)
- **`jtag_fpga.py`**: Python CLI client for JTAG memory operations (interactive console)
- **`control_gui.py`**: Tkinter GUI for bulk memory writes/reads
- **Test scripts**: `test_memory_debug.py`, `write_sequence.py`

### Quartus Project Files
- **`project_dsa.qpf/.qsf`**: Quartus Prime 18.1 project files
- **Target device**: Cyclone V (DE1-SoC Board)
- **Simulation**: ModelSim-Altera (Verilog/SystemVerilog)

### Testbenches (`testbench/`)
- **`tb_ram.sv`**: Testbench individual para módulo RAM
- **`tb_vjtag_interface.sv`**: Testbench individual para VJTAG Interface
- **`tb_vjtag_ram_integrated.sv`**: Testbench integrado VJTAG+RAM
- **`tb_dsa_top.sv`**: Testbench completo del sistema (VJTAG+RAM+manual control) ✅ NEW
- **`run_tests.ps1`**: Script PowerShell para ejecutar todos los tests
- **`run_testbenches.tcl`**: Script TCL para ModelSim

## Critical Workflows

### JTAG Communication Architecture

**3-tier communication stack**:
```
Python Client (jtag_fpga.py) ←TCP→ TCL Server (jtag_server.tcl) ←JTAG→ FPGA Hardware
```

#### Starting the JTAG Server
```powershell
# In Quartus TCL console or PowerShell with Quartus in PATH:
quartus_stp -t vjtag_pc\jtag_server.tcl [data_width] [port]
# Default: 8-bit data width, port 2540
```

**IMPORTANT**: Server MUST be running before Python clients can connect.

#### JTAG Protocol Details

**IR (Instruction Register) Values**:
- `0`: BYPASS
- `1`: WRITE (8-bit data to current address)
- `2`: READ (8-bit data from current address)  
- `3`: SETADDR (16-bit address - 64KB addressable)

**Data Widths**:
- Data operations: 8 bits (`VJTAG_DATA_WIDTH`)
- Address operations: 16 bits (`VJTAG_ADDR_WIDTH`) - provides 64KB address space

**Binary Protocol** (TCP commands sent to server):
```
SETADDR <16-bit-binary>\n    # Example: SETADDR 0000000000000000\n
WRITE <8-bit-binary>\n       # Example: WRITE 10101010\n
READ\n                       # Returns hex value+ \n
```

### Memory Operations

#### Interactive Console
```powershell
python vjtag_pc\jtag_fpga.py [-dw 8|16|32|64] [-q|-v]
# Commands:
#   setaddr <addr>     - Set memory address (hex: 0x0000-0xFFFF)
#   write <value>      - Write 8-bit value (hex: 0x00-0xFF)
#   read               - Read from current address
#   readaddr <addr>    - Atomic SETADDR+READ
#   verbose <level>    - quiet|normal|debug
```

#### Programmatic Access
```python
from vjtag_pc.jtag_fpga import open_connection, set_address_to_fpga, write_value_to_fpga

conn = open_connection('localhost', 2540)
set_address_to_fpga(conn, 0x0100)
write_value_to_fpga(conn, 0xAB)
```

**Critical**: Always send `SETADDR` before `WRITE` or `READ` - address auto-increment behavior depends on hardware FSM implementation.

### Hardware Design Patterns

#### JTAG Interface Module (`vjtag_interface.sv`)

**Architecture**: Custom SystemVerilog wrapper around Intel Virtual JTAG IP

**Parameters**:
- `DW = 8`: Data width for read/write operations (configurable)
- `AW = 16`: Address width for memory operations (configurable, 64KB range)

**Key Registers** (internal shift registers):
- `DR0_bypass_reg`: 1-bit JTAG bypass register
- `DR1`: DW-bit data register for PC→FPGA writes
- `DR_ADDR`: AW-bit address register for SET_ADDR operations (16 bits)
- `DR2`: DW-bit data register for FPGA→PC reads

**IR State Mapping** (2-bit instruction register):
```systemverilog
BYPASS   = 2'b00  // Standard JTAG bypass
WRITE    = 2'b01  // Shift data into DR1, update data_out on UDR
READ     = 2'b10  // Capture data_in into DR2, shift out via TDO
SET_ADDR = 2'b11  // Shift address into DR_ADDR, update addr_out on UDR
```

**JTAG Signals** (from Virtual JTAG IP):
- `v_cdr`: Virtual Capture-DR (loads data into shift register)
- `v_sdr`: Virtual Shift-DR (shifts data through TDI→TDO)
- `udr`: Virtual Update-DR (commits shifted data to output registers)

**Operation Flow**:
1. **WRITE**: Shift DW bits into DR1 → On UDR, copy DR1 to `data_out`
2. **READ**: On CDR, capture `data_in` into DR2 → Shift DR2 out via TDO
3. **SET_ADDR**: Shift AW bits into DR_ADDR → On UDR, copy DR_ADDR to `addr_out`
4. **BYPASS**: Standard 1-bit JTAG bypass (capture 0, shift TDI→TDO)

**TDO Multiplexing**: Output depends on current `ir_state`:
- `WRITE`: `tdo = DR1[0]` (LSB of write data register)
- `READ`: `tdo = DR2[0]` (LSB of read data register)
- `SET_ADDR`: `tdo = DR_ADDR[0]` (LSB of address register)
- `BYPASS`: `tdo = DR0_bypass_reg`

**Debug Ports**:
- `debug_dr1`: Exposes DR1 register for verification
- `debug_dr2`: Exposes DR2 register for verification

**Critical Design Notes**:
- All shift operations are LSB-first: `{tdi, REG[(WIDTH-1):1]}`
- Address width (AW) is independent from data width (DW)
- `data_out` and `addr_out` only update on UDR (Update-DR) pulse
- Asynchronous active-low reset (`aclr`) clears all registers

#### Fixed-Point Arithmetic
- **Format**: Q8.8 (8 integer bits, 8 fractional bits)
- **Usage**: Bilinear interpolation coefficients and pixel calculations

#### Memory Architecture
- **Type**: Altsyncram (Intel M10K blocks)
- **Interface**: DUAL_PORT mode (`ram/ram.v`) - separate read/write addresses
- **Capacity**: 65,536 words × 8 bits = 64 KB (16-bit addressing)
- **Addressing**: 16-bit addresses (0x0000 to 0xFFFF)
- **Port Names**: `.wraddress`, `.rdaddress`, `.data`, `.wren`, `.q`, `.clock`
- **Resource Usage**: ~128 M10K blocks (fits in Cyclone V's 397 available blocks)

#### DSA Top Module (`dsa_top.sv`) - IMPLEMENTED ✅

**Architecture**: Complete system integration with dual control modes

**Features**:
- VJTAG interface for PC-controlled memory access
- Manual address control via KEY buttons (increment/decrement)
- Dual-mode operation: JTAG mode (SW[0]=0) vs Manual mode (SW[0]=1)
- HEX display multiplexing showing address+data per mode
- LED debug indicators for operations and KEY states

**Pin Mapping** (DE1-SoC):
- `clk`: AF14 (50 MHz system clock)
- `KEY[3]`: Y16 - Used as reset_n (active low)
- `KEY[0]`: AA14 - Increment manual address
- `KEY[1]`: AA15 - Decrement manual address
- `SW[0]`: AB12 - Mode selector (0=JTAG, 1=Manual)
- `LEDR[9:0]`: Debug LEDs
- `HEX[5:0]`: 7-segment displays (address + data)

**Control Logic**:
- Simple edge detection for KEY presses (no complex debounce)
- `key_prev[1:0]` register tracks KEY state for falling edge detection
- Manual address increments/decrements on KEY press

**LED Indicators**:
- `LEDR[0]`: Current mode (0=JTAG, 1=Manual)
- `LEDR[4]`: KEY[0] state (increment)
- `LEDR[5]`: KEY[1] state (decrement)

## Development Conventions

### File Naming
- Hardware: SystemVerilog (`.sv`) preferred, Verilog (`.v`) for IP cores
- Use `_bb.v` suffix for black-box stubs (auto-generated by Quartus)
- Python: snake_case
- TCL: lowercase with underscores

### Debugging Approach

**Hardware Simulation (ModelSim)**:
- Testbenches usan formato `[PASS]`/`[FAIL]` con valores esperados vs obtenidos
- Cada testbench tiene timeout de seguridad (100-200 µs)
- Testbench integrado incluye monitor de escrituras a RAM
- Ver `testbench/README.md` para detalles de ejecución

**LED Indicators** (expected from test scripts):
- `LEDR[1]`: SETADDR operation pulse
- `LEDR[2]`: WRITE operation pulse  
- `LEDR[3]`: RAM write strobe
- `LEDR[7]`: FSM in WRITE state

**HEX Display Modes** (controlled by `SW[0]`):
- `SW[0]=0` ("rd" mode): Display current read address and data
- `SW[0]=1` ("Ar" mode): Display last JTAG address and data

**Verification Steps** (from `test_memory_debug.py`):
1. Write sequential data to addresses 0x00-0x05
2. Read back and verify
3. Test auto-increment by writing consecutive values from 0x10
4. Verify with HEX displays and LEDs

### Tools & Versions

- **Quartus Prime**: 18.1.0 Lite Edition (CRITICAL: version sensitive for IP cores)
- **Device**: Cyclone V 5CSEMA5F31C6
- **Simulator**: ModelSim-Altera (Verilog)
- **Python**: 3.x (uses `socket`, `tkinter` for GUI)
- **TCL**: Quartus-embedded TCL shell

### Common Pitfalls

1. **Binary String Format**: TCL server expects pure binary strings WITHOUT `0b` prefix
2. **Address Width**: `SETADDR` uses 16 bits (64KB RAM range), data uses 8 bits - DO NOT confuse
3. **Server Not Running**: Python client will hang/timeout if `jtag_server.tcl` isn't active
4. **Quartus Version**: IP cores (vjtag, ram) generated for 18.1 - regenerate if using different version
5. **Windows Path Handling**: Use raw strings or forward slashes in Python for file paths
6. **Testbenches are for ModelSim ONLY**: DO NOT compile testbenches with Quartus - use ModelSim for simulation
7. **Loop Variables in Testbenches**: Use `integer` instead of `int` for loop variables to avoid Quartus elaboration errors
8. **RAM Size Limitation**: Cyclone V 5CSEMA5F31C6 has only 397 M10K blocks - max practical RAM is ~64KB for DUAL_PORT mode
9. **Reset Pin**: `reset_n` is connected to `KEY[3]` internally in `dsa_top.sv` - no separate reset pin in QSF

### Testing Strategy

#### Hardware Simulation (ModelSim)

```powershell
# En el directorio testbench/
.\run_tests.ps1  # Ejecuta todos los testbenches

# O individual con GUI
vsim work.tb_ram
vsim work.tb_vjtag_interface
vsim work.tb_vjtag_ram_integrated
```

**Testbenches disponibles**:
- `tb_ram.sv`: Verifica operaciones dual-port de altsyncram (~25 pruebas)
- `tb_vjtag_interface.sv`: Verifica protocolo JTAG (BYPASS/WRITE/READ/SET_ADDR) (~25 pruebas)
- `tb_vjtag_ram_integrated.sv`: Integración completa VJTAG+RAM (~35 pruebas)
- `tb_dsa_top.sv`: Sistema completo con JTAG, RAM, control manual, HEX displays ✅ NEW

**Formato de salida**: Cada test imprime `[PASS]`/`[FAIL]` con valores esperados vs obtenidos.

**JTAG Simulation Workaround**: Virtual JTAG IP no se puede simular completamente - usar `force`/`release`:
```systemverilog
force dut.jtag_addr_out = addr;
repeat(2) @(posedge clk);
release dut.jtag_addr_out;
```

#### Software Tests (Python + JTAG Server)

```powershell
# 1. Start server (in Quartus TCL console)
quartus_stp -t vjtag_pc\jtag_server.tcl

# 2. Run automated tests
python vjtag_pc\test_memory_debug.py

# 3. Write test patterns
python vjtag_pc\write_sequence.py

# 4. Interactive debugging
python vjtag_pc\jtag_fpga.py -v  # verbose mode
```

**Expected Test Outputs**: All scripts print verification steps with ✓/✗ indicators.

## Current State

**Implemented** ✅:
- JTAG communication infrastructure (`vjtag_interface.sv`, `jtag_server.tcl`)
- Python client tools (`jtag_fpga.py`, `control_gui.py`)
- Software test suite (`test_memory_debug.py`, `write_sequence.py`)
- Hardware testbenches (`tb_ram.sv`, `tb_vjtag_interface.sv`, `tb_vjtag_ram_integrated.sv`, `tb_dsa_top.sv`)
- IP cores (Virtual JTAG, RAM - 64KB dual-port)
- **Top-level system** (`dsa_top.sv`):
  - VJTAG + RAM integration
  - Manual address control with KEY buttons
  - Dual-mode operation (JTAG/Manual)
  - HEX display multiplexing
  - LED debug indicators
  - Complete DE1-SoC pin assignments

**Pending** ⚠️:
- Bilinear interpolation datapath (`dsa_datapath.sv`)
- Image processing control FSM
- Fixed-point arithmetic units (Q8.8)
- Performance counters and optimization

**Ready for**:
- Physical FPGA programming and testing
- PC-to-FPGA communication verification via JTAG
- Manual memory browsing with KEY buttons
- Next phase: Implement image processing pipeline

## Quick Reference

| Task | Command/File |
|------|--------------|
| Run all hardware testbenches | `cd testbench; .\run_tests.ps1` |
| Simulate dsa_top (full system) | `vsim work.tb_dsa_top` |
| Simulate VJTAG+RAM integration | `vsim work.tb_vjtag_ram_integrated` |
| Start JTAG server | `quartus_stp -t vjtag_pc\jtag_server.tcl` |
| Interactive console | `python vjtag_pc\jtag_fpga.py` |
| Run software tests | `python vjtag_pc\test_memory_debug.py` |
| Open Quartus project | Open `project_dsa.qpf` in Quartus Prime 18.1 |
| Compile hardware | `quartus_sh --flow compile project_dsa` |
| Program FPGA | Quartus Programmer: Tools → Programmer |
| Check resource usage | After compilation, view Fitter Report |
