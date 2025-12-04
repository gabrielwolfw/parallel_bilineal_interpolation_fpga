# Parallel Bilinear Interpolation FPGA

Proyecto 02: Diseño e Implementación de una Arquitectura de Dominio Específico (DSA) para Downscaling de Imágenes mediante Interpolación Bilineal Paralela en FPGA (Intel/Altera DE1-SoC - Cyclone V).

## Estado Actual del Proyecto

**Implementado** ✅:
- Sistema de comunicación PC-FPGA vía JTAG (Virtual JTAG + TCL Server + Python Client)
- Memoria RAM dual-port de 64KB (16-bit addressing)
- Control manual con botones KEY para navegación de memoria
- Displays HEX para visualización de direcciones y datos
- Testbenches completos para simulación (ModelSim)
- Sincronización de dominios de reloj (JTAG TCK ↔ System Clock)
- **Modelo de referencia C++** con interpolación bilineal Q8.8 (formato PGM)

**En desarrollo** ⚠️:
- Datapath de interpolación bilineal en hardware FPGA
- FSM de control de procesamiento de imágenes
- Integración del algoritmo Q8.8 en hardware

## Estructura del Repositorio

### Hardware Design
```
dsa_top.sv                    # Top-level: VJTAG + RAM + control manual
vjtag/
 ├── vjtag_interface.sv        # Wrapper de Virtual JTAG con sincronización CDC
 └── vjtag/                    # IP core Virtual JTAG (Qsys-generated)
ram/
 └── ram.v                     # Altsyncram 64KB dual-port (M10K blocks)
testbench/
 ├── tb_ram.sv                 # Tests unitarios de RAM
 ├── tb_vjtag_interface.sv     # Tests de protocolo JTAG
 ├── tb_vjtag_ram_integrated.sv # Tests de integración VJTAG+RAM
 ├── tb_dsa_top.sv             # Tests del sistema completo
 └── run_tests.ps1             # Script para ejecutar todos los tests
```

### PC Interface (JTAG Communication)
```
vjtag_pc/
 ├── jtag_server.tcl           # TCL server: TCP ↔ JTAG bridge
 ├── jtag_fpga.py              # Cliente Python CLI (interactivo)
 ├── control_gui.py            # GUI Tkinter para operaciones bulk
 ├── test_memory_debug.py      # Tests automáticos de escritura/lectura
 └── write_sequence.py         # Script de test de patrones
```

### Memory Initialization
```
mem/
 ├── image.mif                 # Archivo MIF para precargar RAM (formato Quartus)
 └── matrix_test.txt           # Datos de prueba (formato texto)
hex_utilities/
 ├── generate_mif.py           # Generador de archivos MIF
 └── hex_generator.py          # Generador de archivos HEX
```

### Quartus Project
```
project_dsa.qpf/.qsf          # Proyecto Quartus Prime 18.1
output_files/
 └── project_dsa.sof           # FPGA bitstream para programación
```

### Reference Model (C++)
```
reference_model/
 ├── src/                      # Código fuente C++
 │   ├── main.cpp              # Programa principal
 │   ├── Image.cpp             # Manejo de imágenes PGM
 │   └── BilinearInterpolator.cpp  # Algoritmo Q8.8
 ├── includes/                 # Headers
 │   ├── FixedPoint.h          # Aritmética de punto fijo Q8.8
 │   ├── Image.h               # Clase para imágenes PGM
 │   ├── BilinearInterpolator.h    # Interface del interpolador
 │   ├── MemoryBank.h          # Simulación de memoria FPGA
 │   └── Registers.h           # Registros de control/estado
 ├── images/                   # Imágenes de prueba (PGM format)
 ├── scripts/                  # Generación de imágenes
 ├── build.ps1                 # Script de compilación para Windows
 ├── Makefile.win              # Makefile para Windows/MinGW
 └── README.md                 # Documentación del modelo
```

## Componentes Principales

### Hardware (SystemVerilog)

- **dsa_top.sv**: Módulo top-level que integra:
  - VJTAG interface para comunicación PC-FPGA
  - RAM dual-port de 64KB (Altsyncram)
  - Control manual con KEY[1:0] (incrementar/decrementar dirección)
  - Modo dual: JTAG (SW[0]=0) vs Manual (SW[0]=1)
  - HEX displays para visualización de dirección y datos
  - LEDs de debug (operaciones JTAG, estado de KEYs)

- **vjtag_interface.sv**: Wrapper auto-contenido del Intel Virtual JTAG IP:
  - Instancia internamente el IP Virtual JTAG (no requiere señales externas)
  - Protocolo JTAG: BYPASS/WRITE/READ/SET_ADDR (2-bit IR)
  - **Sincronización Clock Domain Crossing (CDC)**: doble flip-flop
  - TCK (JTAG clock) → SYS_CLK (50 MHz) crossings seguros
  - Address width: 16 bits (64KB addressable)
  - Data width: 8 bits

- **ram.v**: Altsyncram dual-port (Intel IP):
  - Capacidad: 65,536 words × 8 bits = 64KB
  - Modo: DUAL_PORT (read/write simultáneos)
  - Inicialización: archivo MIF (mem/image.mif)
  - Recursos: ~128 M10K blocks

### Software (Python + TCL)

- **jtag_server.tcl**: Servidor TCP que puente entre sockets y hardware JTAG:
  - Puerto: 2540 (configurable)
  - Comandos: SETADDR (16-bit), WRITE (8-bit), READ
  - Usa Quartus API: `quartus_stp` para acceso USB-Blaster

- **jtag_fpga.py**: Cliente Python interactivo:
  - Comandos: `setaddr`, `write`, `read`, `readaddr`
  - Formato: direcciones hex (0x0000-0xFFFF), datos hex (0x00-0xFF)
  - Modos: quiet/normal/debug (verbosity)

- **control_gui.py**: GUI Tkinter para operaciones bulk:
  - Escritura/lectura de bloques de memoria
  - Visualización en tiempo real

### Reference Model (C++)

- **Modelo de referencia** para validación bit a bit del hardware:
  - Interpolación bilineal con aritmética Q8.8 (8 bits entero, 8 bits fracción)
  - Procesamiento de imágenes PGM (Portable GrayMap) en escala de grises
  - Sin dependencias externas (no requiere libpng)
  - Performance counters: ciclos, FLOPs, lecturas/escrituras de memoria
  - Factores de escala: 0.5 a 1.0 en pasos de 0.05
  - Compilación en Windows: `.\build.ps1 all` (PowerShell) o `mingw32-make -f Makefile.win`
  - Ejecución: `.\bin\bilinear_interpolator.exe <imagen> <factor>`
  - Ver `reference_model/README.md` para más detalles

## Consideraciones Críticas de Diseño

### Clock Domain Crossing (CDC)

**PROBLEMA CRÍTICO RESUELTO**: El Virtual JTAG IP proporciona su propio reloj (TCK) desde el USB-Blaster, que es **asíncrono** al reloj del sistema (50 MHz). Conectar directamente el system clock al puerto `tck` del VJTAG causa:
- Corrupción de datos durante shift register operations
- Valores intermedios visibles en displays (ej: 0x03 en lugar de 0x80)
- Violaciones del protocolo JTAG

**SOLUCIÓN IMPLEMENTADA**:
1. El IP Virtual JTAG **genera** el TCK (no lo recibe como entrada)
2. `vjtag_interface.sv` usa TCK para shift registers internos
3. **Sincronización de 2 etapas** (doble flip-flop) para `data_out` y `addr_out`:
   ```systemverilog
   // Dominio JTAG (tck)
   always_ff @(posedge tck) begin
       if (udr && ir_state == SET_ADDR)
           addr_out_jtag <= DR_ADDR;
   end
   
   // Sincronización a dominio del sistema (sys_clk)
   always_ff @(posedge sys_clk) begin
       addr_sync1 <= addr_out_jtag;  // Etapa 1
       addr_sync2 <= addr_sync1;     // Etapa 2
       addr_out <= addr_sync2;       // Salida estable
   end
   ```
4. Latencia añadida: ~3 ciclos de system clock (aceptable para debug)

### Protocolo JTAG

- **IR (Instruction Register)**: 2 bits
  - `00`: BYPASS
  - `01`: WRITE (8-bit data)
  - `10`: READ (8-bit data)
  - `11`: SET_ADDR (16-bit address)

- **DR (Data Registers)**:
  - DR0: 1-bit bypass register
  - DR1: 8-bit write data (PC → FPGA)
  - DR2: 8-bit read data (FPGA → PC)
  - DR_ADDR: 16-bit address register

- **Estados JTAG**:
  - Capture-DR (CDR): Captura `data_in` en DR2
  - Shift-DR (SDR): Desplaza bits TDI → registro → TDO
  - Update-DR (UDR): Actualiza registros de salida (solo aquí cambia `addr_out`/`data_out`)

### Arquitectura de Memoria

- **Tipo**: Altsyncram (bloques M10K de Cyclone V)
- **Modo**: DUAL_PORT (puertos separados read/write)
- **Limitación**: Cyclone V 5CSEMA5F31C6 tiene 397 M10K blocks
  - Cada M10K: 10 Kbits
  - RAM actual: 64KB × 8 = 512 Kbits ≈ 128 M10K blocks
  - Margen disponible: ~270 M10K para futuras expansiones

## Workflow de Desarrollo

### 1. Compilación Hardware
```powershell
quartus_sh --flow compile project_dsa
```

### 2. Programación FPGA
```powershell
quartus_pgm -c "DE-SoC" -m jtag -o "p;output_files/project_dsa.sof@2"
```

### 3. Comunicación PC-FPGA

**Terminal 1: Iniciar servidor JTAG**
```powershell
cd vjtag_pc
quartus_stp -t jtag_server.tcl 8 2540
# Output esperado: "Started Socket Server on port - 2540"
```

**Terminal 2: Cliente interactivo**
```powershell
cd vjtag_pc
python jtag_fpga.py -v

# Comandos:
JTAG-8bit> setaddr 0x0100
JTAG-8bit> write 0xAB
JTAG-8bit> read
JTAG-8bit> readaddr 0x0200
```

### 4. Tests de Hardware (ModelSim)
```powershell
cd testbench
.\run_tests.ps1
# Ejecuta todos los testbenches y muestra [PASS]/[FAIL]
```

## Troubleshooting

### "Virtual JTAG instance cannot be found"
- **Causa**: `vjtag_interface.sv` no instancia el IP Virtual JTAG internamente
- **Solución**: Verificar que el módulo tenga la instancia `vjtag vjtag_ip(...)`
- **Recompilación requerida** después de cambios en vjtag_interface.sv

### Valores incorrectos en HEX displays
- **Causa**: Clock domain crossing mal implementado (system clock conectado a `tck`)
- **Síntoma**: Valores intermedios durante shift (ej: 0x03 en lugar de 0x80)
- **Solución**: Usar sincronización doble flip-flop entre dominios TCK y SYS_CLK

### Server JTAG no detecta hardware
- Verificar USB-Blaster conectado: `jtagconfig`
- Verificar FPGA programado con .sof correcto
- Reiniciar servidor TCL si hay cambios de hardware

### Errores de compilación VHDL
- No compilar archivos template: `vjtag_inst.vhd` debe estar excluido del .qsf
- Usar solo archivos `.v` y `.sv` para síntesis

## Herramientas y Versiones

- **Quartus Prime**: 18.1.0 Lite Edition
- **Device**: Cyclone V 5CSEMA5F31C6 (DE1-SoC Board)
- **Simulator**: ModelSim-Altera (Verilog/SystemVerilog)
- **Python**: 3.x (tkinter, socket, numpy, Pillow)
- **TCL**: Quartus-embedded shell
- **C++ Compiler**: g++ (MinGW/MSYS2) con soporte C++17
- **Formato de imágenes**: PGM (Portable GrayMap) - sin dependencias externas

## Próximos Pasos

- [ ] Implementar datapath de interpolación bilineal en hardware (Q8.8 fixed-point)
- [ ] Diseñar FSM de control para procesamiento de imágenes
- [ ] Integrar algoritmo del modelo de referencia en RTL
- [ ] Validación bit a bit: modelo C++ vs hardware FPGA
- [ ] Agregar performance counters y optimización
- [ ] Timing constraints (.sdc) para análisis de timing
- [ ] Documentación completa del flujo de validación
