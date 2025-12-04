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
- **DSA integrado**: Módulos de interpolación bilineal (`dsa_top_integrated.sv`)
  - Control FSM secuencial
  - Pixel fetch secuencial (1 pixel/ciclo)
  - Datapath con aritmética Q8.8
- **Registros Memory-Mapped** (`dsa_register_bank.sv`)
  - 64 bytes de registros (0x00-0x3F) con alineación word
  - Configuración dinámica: width, height, scale factor, bases de memoria
  - Registros de estado: STATUS, performance counters, error codes
  - Soporte para SIMD, CRC, stepping mode
- **API Python de alto nivel** (`dsa_config.py`)
  - Configuración simplificada del DSA
  - Monitoreo de estado y performance
  - Funciones helper para acceso a registros
- **Controller Python optimizado** (`controller_py/`)
  - Comunicación JTAG con batch I/O (100-500x más rápido)
  - GUI completa con conexión JTAG, configuración DSA y lectura de registros
  - Configuración JSON para parámetros de imagen y procesamiento
  - Socket sin timeout para operaciones de memoria grandes

**En desarrollo** ⚠️:
- Integración de register_bank en dsa_top_integrated.sv
- Testing físico de DSA en FPGA
- Validación bit a bit: modelo C++ vs hardware FPGA
- Medición de performance (ciclos por pixel)

## Estructura del Repositorio

### Hardware Design
```
dsa_top.sv                    # Top-level original: VJTAG + RAM + control manual
dsa_top_integrated.sv         # Top-level con DSA: VJTAG + RAM + DSA + control
dsa_register_bank.sv          # Banco de registros memory-mapped (64 bytes)
vjtag/
 ├── vjtag_interface.sv        # Wrapper de Virtual JTAG con sincronización CDC
 └── vjtag/                    # IP core Virtual JTAG (Qsys-generated)
ram/
 └── ram.v                     # Altsyncram 64KB dual-port (M10K blocks)
fpga/
 ├── dsa_control_fsm_sequential.sv  # FSM de control de procesamiento
 ├── dsa_pixel_fetch_sequential.sv  # Fetch de píxeles vecinos
 └── dsa_datapath.sv                # Interpolación bilineal Q8.8
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
 ├── dsa_config.py             # API de alto nivel para configurar DSA
 ├── control_gui.py            # GUI Tkinter para operaciones bulk
 ├── test_memory_debug.py      # Tests automáticos de escritura/lectura
 └── write_sequence.py         # Script de test de patrones

controller_py/
 ├── serial_controller.py      # Controlador JTAG optimizado (batch I/O)
 ├── interface_serial.py       # GUI completa para control DSA
 ├── constantes.py             # Definiciones de registros y configuración
 └── config.json               # Configuración JSON para parámetros DSA
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

### Documentation
```
README.md                     # Este archivo - overview del proyecto
REGISTER_MAP.md               # Mapa de registros memory-mapped (64 bytes)
DSA_INTEGRATION_GUIDE.md      # Guía de uso del DSA integrado
.github/copilot-instructions.md # Instrucciones técnicas para desarrollo
```

## Componentes Principales

### Hardware (SystemVerilog)

- **dsa_top_integrated.sv**: Módulo top-level con DSA que integra:
  - VJTAG interface para comunicación PC-FPGA
  - RAM dual-port de 64KB (Altsyncram)
  - DSA para interpolación bilineal (FSM + Pixel Fetch + Datapath)
  - Control manual con KEY[3:0]:
    - KEY[3]: Reset general
    - KEY[2]: Reset DSA
    - KEY[1]: Decrementar dirección manual
    - KEY[0]: Incrementar dirección manual
  - Modo dual: JTAG (SW[0]=0) vs Manual (SW[0]=1)
  - DSA control: SW[1] enable, SW[9:2] scale factor (Q8.8)
  - HEX displays para visualización de dirección y datos
  - LEDs de debug (modo, DSA state, operaciones, KEYs)

- **dsa_top.sv**: Módulo original sin DSA (solo VJTAG + RAM + control manual)

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

#### Módulos DSA (fpga/)

- **dsa_control_fsm_sequential.sv**: FSM de control de procesamiento:
  - Estados: IDLE → INIT → REQUEST_FETCH → WAIT_FETCH → INTERPOLATE → WRITE → NEXT_PIXEL → DONE
  - Procesamiento pixel por pixel (1 pixel/ciclo)
  - Señales de control para fetch y datapath
  - Contadores de progreso (x_out, y_out)

- **dsa_pixel_fetch_sequential.sv**: Fetch de píxeles vecinos:
  - Lee 4 píxeles vecinos de memoria (p00, p01, p10, p11)
  - Calcula coordenadas fraccionales (a, b) en Q8.8
  - Secuencial: 4 ciclos por fetch
  - Interfaz con RAM para lectura

- **dsa_datapath.sv**: Interpolación bilineal:
  - Aritmética Q8.8 (8 bits entero, 8 bits fracción)
  - Cálculo de pesos: w00, w01, w10, w11
  - Interpolación: `result = (p00*w00 + p01*w01 + p10*w10 + p11*w11) >> 16`
  - 1 ciclo de latencia

#### Banco de Registros Memory-Mapped

- **dsa_register_bank.sv**: Registros de configuración y estado (64 bytes, 0x00-0x3F):
  - **Configuración (RW)**: CFG_WIDTH, CFG_HEIGHT, CFG_SCALE_Q8_8, CFG_MODE
  - **Estado (R)**: STATUS (idle/busy/done/error), progress, fsm_state
  - **Performance (R)**: PERF_FLOPS, PERF_MEM_RD, PERF_MEM_WR
  - **Control avanzado**: SIMD_N, STEP_CTRL, IMG_IN_BASE, IMG_OUT_BASE
  - **Verificación**: CRC_CTRL, CRC_VALUE, ERR_CODE
  - Ver `REGISTER_MAP.md` para detalles completos

**Distribución de Memoria**:
```
0x0000-0x003F: Registros de control/estado (64 bytes)
0x0040-0x007F: Reservado para expansión (64 bytes)
0x0080-0x7FFF: Imagen de entrada (32KB - 512 bytes)
0x8000-0xFFFF: Imagen de salida (32KB)
```

### Software (Python + TCL)

- **jtag_server.tcl**: Servidor TCP que puente entre sockets y hardware JTAG:
  - Puerto: 2540 (configurable)
  - Comandos: SETADDR (16-bit), WRITE (8-bit), READ
  - Usa Quartus API: `quartus_stp` para acceso USB-Blaster

- **jtag_fpga.py**: Cliente Python interactivo (bajo nivel):
  - Comandos: `setaddr`, `write`, `read`, `readaddr`
  - Formato: direcciones hex (0x0000-0xFFFF), datos hex (0x00-0xFF)
  - Modos: quiet/normal/debug (verbosity)

- **dsa_config.py**: API Python de alto nivel para DSA:
  - Clase `DSAConfig`: interfaz simplificada para configurar DSA
  - Métodos principales:
    - `configure(width, height, scale, ...)`: Configurar parámetros
    - `start(simd_mode)`: Iniciar procesamiento
    - `wait_done(timeout)`: Esperar completado con polling
    - `get_status()`: Leer estado (idle/busy/done/error)
    - `get_performance()`: Leer contadores de performance
    - `enable_crc()`: Habilitar verificación CRC
    - `set_stepping_mode()`: Control paso a paso (debug)
  - Acceso transparente a registros memory-mapped (0x00-0x3F)
  - Ejemplo:
    ```python
    dsa = DSAConfig('localhost', 2540)
    dsa.configure(width=256, height=256, scale=0.75)
    dsa.start()
    if dsa.wait_done():
        dsa.print_performance()
    ```

- **control_gui.py**: GUI Tkinter para operaciones bulk:
  - Escritura/lectura de bloques de memoria
  - Visualización en tiempo real

- **controller_py/** - Controlador DSA optimizado con GUI completa:
  - **serial_controller.py**: Clase SerialController con comunicación JTAG:
    - **Batch I/O optimizado**: Agrupa comandos TCP (100-500x más rápido)
    - `batch_size` configurable (default: 256 bytes por batch)
    - Socket sin timeout para operaciones grandes
    - Funciones DSA específicas: `configure_dsa()`, `start_dsa()`, `wait_done()`, `get_performance()`
    - Acceso a memoria: `write_buffer()`, `read_buffer()` con progreso en tiempo real
    - Soporte word16/word32 little-endian
    - Carga de configuración desde JSON
  - **interface_serial.py**: GUI Tkinter completa:
    - Conexión/desconexión JTAG con indicador de estado
    - Panel de configuración DSA (width, height, scale, modo SIMD)
    - Procesamiento de imágenes con workflow automático
    - Acceso manual a memoria (lectura/escritura hex)
    - Visualización de registros DSA con valores reales leídos de FPGA
    - Log detallado de operaciones con prefijos `[JTAG]`, `[DSA]`, `[ERROR]`
  - **constantes.py**: Definiciones centralizadas:
    - Direcciones de registros memory-mapped (0x00-0x3F)
    - Configuración JTAG (host, port, timeout)
    - Máscaras de bits, modos SIMD, códigos de error
    - Regiones de memoria, constantes Q8.8
    - Compatibilidad legacy con nombres antiguos
  - **config.json**: Configuración JSON para parámetros DSA:
    - Dimensiones de imagen, scale factor, direcciones base
    - Configuración JTAG y timeouts
    - Modo de procesamiento (SCALAR/SIMD2/SIMD4/SIMD8)
    - Performance counters, debug options, CRC
  - **Ejemplo de uso**:
    ```python
    from serial_controller import SerialController
    ctrl = SerialController(config_file="config.json")
    ctrl.connect()
    ctrl.configure_dsa(256, 256, 0x0080, MODE_SIMD4)
    resultado = ctrl.procesar_imagen_fpga("imagen.jpg")
    perf = ctrl.get_performance()
    ctrl.disconnect()
    ```

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
- **Capacidad**: 64KB total (65,536 bytes)
- **Distribución optimizada**:
  ```
  0x0000-0x003F: Registros DSA (64 bytes) - Memory-Mapped I/O
  0x0040-0x007F: Reservado (64 bytes) - Expansión futura
  0x0080-0x7FFF: Imagen INPUT (32KB - 512 bytes = 32,256 bytes)
  0x8000-0xFFFF: Imagen OUTPUT (32KB = 32,768 bytes)
  ```
- **Limitación**: Cyclone V 5CSEMA5F31C6 tiene 397 M10K blocks
  - Cada M10K: 10 Kbits
  - RAM actual: 64KB × 8 = 512 Kbits ≈ 128 M10K blocks
  - Margen disponible: ~270 M10K para futuras expansiones

### Registros Memory-Mapped (0x00-0x3F)

Ver `REGISTER_MAP.md` para documentación completa. Registros principales:

| Dirección | Registro | Ancho | RW | Descripción |
|----------|----------|-------|-----|-------------|
| 0x00 | CFG_WIDTH | 16 | RW | Ancho imagen entrada |
| 0x04 | CFG_HEIGHT | 16 | RW | Alto imagen entrada |
| 0x08 | CFG_SCALE_Q8_8 | 16 | RW | Factor de escala Q8.8 |
| 0x0C | CFG_MODE | 8 | RW | Control: start, SIMD mode |
| 0x10 | STATUS | 32 | R | Estado: idle/busy/done/error |
| 0x14 | SIMD_N | 8 | RW | Número de lanes SIMD |
| 0x18 | PERF_FLOPS | 32 | R | Contador operaciones |
| 0x1C | PERF_MEM_RD | 32 | R | Lecturas BRAM |
| 0x20 | PERF_MEM_WR | 32 | R | Escrituras BRAM |
| 0x30 | IMG_IN_BASE | 32 | RW | Base imagen entrada |
| 0x34 | IMG_OUT_BASE | 32 | RW | Base imagen salida |
| 0x38 | CRC_CTRL | 8 | RW | Control CRC |
| 0x3C | CRC_VALUE | 32 | R | CRC32 calculado |

**Ventajas**:
- ✅ Configuración dinámica sin recompilar hardware
- ✅ Solo 64 bytes de overhead (0.09% de memoria total)
- ✅ 32KB disponibles para imágenes (180×180 @ 8bpp)
- ✅ Alineación word (4 bytes) para acceso eficiente
- ✅ Soporte para features avanzadas (SIMD, CRC, stepping)

## Controles (dsa_top_integrated.sv)

**Nota**: Los switches actuales son para compatibilidad de hardware. La configuración dinámica se realiza mediante **registros memory-mapped** (0x00-0x3F) usando `dsa_config.py`.

### Botones (KEYs) - Activos en bajo
- **KEY[3]**: Reset general del sistema
- **KEY[2]**: Reset del DSA (procesador de interpolación)
- **KEY[1]**: Decrementar dirección manual
- **KEY[0]**: Incrementar dirección manual

### Switches
- **SW[0]**: Modo de visualización
  - `0` = Modo JTAG (mostrar dirección/dato desde PC)
  - `1` = Modo Manual (mostrar dirección/dato navegable con KEYs)
- **SW[1]**: Start DSA
  - `1` = Activar procesamiento de interpolación bilineal
- **SW[9:2]**: Scale factor (0-255)
  - Factor de escala para interpolación en formato Q8.8
  - Ejemplo: 192 = 0.75 (imagen 256×256 → 192×192)

### LEDs de Debug
- **LEDR[0]**: Modo visualización (0=JTAG, 1=Manual)
- **LEDR[1]**: DSA enable (SW[1])
- **LEDR[2]**: DSA ready (procesamiento completado)
- **LEDR[3]**: DSA busy (procesando imagen)
- **LEDR[4]**: KEY[0] presionado (incrementar)
- **LEDR[5]**: KEY[1] presionado (decrementar)
- **LEDR[6]**: Escritura a memoria activa
- **LEDR[7]**: Fetch module ocupado
- **LEDR[9:8]**: Estado superior del procesamiento

### Displays HEX

**Modo JTAG** (`SW[0]=0`):
```
HEX5-HEX2: Dirección JTAG desde PC (16 bits)
HEX1-HEX0: Dato leído de RAM (8 bits)
```

**Modo Manual** (`SW[0]=1`):
```
HEX5-HEX2: Dirección manual navegable (KEY[0]/KEY[1])
HEX1-HEX0: Dato leído de RAM (8 bits)
```

*Permite verificar el contenido de memoria sin necesidad de conexión PC*

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

**Terminal 2: Usar API de alto nivel (RECOMENDADO)**
```powershell
cd vjtag_pc
python
```
```python
from dsa_config import DSAConfig

# Conectar al DSA
dsa = DSAConfig('localhost', 2540)

# Configurar parámetros
dsa.configure(
    width=256,
    height=256,
    scale=0.75,
    img_in_base=0x0080,
    img_out_base=0x8000
)

# Iniciar procesamiento
dsa.start(simd_mode=False)

# Esperar completado
if dsa.wait_done(timeout=30):
    # Leer performance
    dsa.print_performance()
    
    # Verificar CRC
    dsa.enable_crc(output_crc=True)
    crc = dsa.get_crc()
    print(f"CRC32: 0x{crc:08X}")
```

**Opción B: Cliente interactivo (bajo nivel)**
```powershell
python jtag_fpga.py -v

# Comandos:
JTAG-8bit> setaddr 0x0000    # Acceder registro CFG_WIDTH
JTAG-8bit> write 0x00        # Width LOW byte
JTAG-8bit> setaddr 0x0001
JTAG-8bit> write 0x01        # Width HIGH byte (256)
JTAG-8bit> setaddr 0x0C      # Registro CFG_MODE
JTAG-8bit> write 0x01        # START bit
```

### 4. Tests de Hardware (ModelSim)
```powershell
cd testbench
.\run_tests.ps1
# Ejecuta todos los testbenches y muestra [PASS]/[FAIL]
```

### 5. Uso del DSA (Interpolación Bilineal con Registros)

**RECOMENDADO: Usar API Python de alto nivel**

```python
from dsa_config import DSAConfig

# 1. Conectar
dsa = DSAConfig('localhost', 2540)

# 2. Cargar imagen a memoria (0x0080+)
# (usar jtag_fpga.py o escribir directamente bytes)

# 3. Configurar DSA
dsa.configure(
    width=256,
    height=256,
    scale=0.75,          # Factor de escala
    img_in_base=0x0080,  # Después de registros
    img_out_base=0x8000  # Segunda mitad
)

# 4. Iniciar procesamiento
dsa.start(simd_mode=False)

# 5. Esperar completado (con progress)
if dsa.wait_done(timeout=30):
    print("✓ Procesamiento completado")
    
    # 6. Leer performance
    dsa.print_performance()
    
    # 7. Leer resultado desde 0x8000
    # (usar jtag_fpga.py para leer memoria)
else:
    print("✗ Error o timeout")
    status = dsa.get_status()
    print(f"Estado: {status}")
```

**Alternativa: Control manual con switches (legacy)**
```
# Paso 1: Cargar imagen vía JTAG en 0x0080+
# Paso 2: SW[0]=1 para verificar con KEY[0]/KEY[1]
# Paso 3: SW[9:2]=192 (scale 0.75), SW[1]=1 (start)
# Paso 4: Esperar LEDR[2]=1 (done)
# Paso 5: Leer desde 0x8000 con modo manual o JTAG
```

## Troubleshooting

### DSA no inicia o no responde
- **Verificar conexión JTAG**: `jtagconfig` debe mostrar USB-Blaster
- **Verificar servidor**: `quartus_stp -t jtag_server.tcl` debe estar corriendo
- **Leer registro STATUS (0x10)**:
  ```python
  dsa = DSAConfig('localhost', 2540)
  status = dsa.get_status()
  print(status)  # Verificar 'idle', 'busy', 'error'
  ```
- **Si error activo**: Leer `ERR_CODE` (0x2C) para diagnóstico

### Registros no se actualizan
- **Causa**: Address decoder puede estar mal configurado
- **Verificar**: Leer registro inmediatamente después de escribir
  ```python
  dsa.write_word16(0x00, 256)  # CFG_WIDTH
  width = dsa.read_word16(0x00)
  print(f"Width: {width}")  # Debe ser 256
  ```
- **Solución**: Verificar señal `reg_hit` en `dsa_register_bank.sv`

### Performance counters en 0
- **Causa**: Módulos DSA no están conectados a señales de contadores
- **Verificar**: Implementación de contadores en FSM y datapath
- **Temporal**: Usar progreso de STATUS[1] (progress) como indicador

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

- [x] Implementar datapath de interpolación bilineal en hardware (Q8.8 fixed-point) ✅
- [x] Diseñar FSM de control para procesamiento de imágenes ✅
- [x] Integrar algoritmo del modelo de referencia en RTL ✅
- [x] **Diseñar banco de registros memory-mapped** (64 bytes optimizados) ✅
- [x] **Crear API Python de alto nivel** (`dsa_config.py`) ✅
- [ ] **Integrar register_bank en dsa_top_integrated.sv**
  - Instanciar `dsa_register_bank`
  - Implementar address decoder (Registros vs RAM)
  - Conectar señales de configuración/estado
- [ ] **Implementar performance counters en módulos DSA**
  - Contador de FLOPs en datapath
  - Contador de lecturas/escrituras en pixel_fetch
  - Contador de ciclos en FSM
- [ ] **Recompilar y programar FPGA** con nueva arquitectura
- [ ] **Testing físico completo**:
  - Verificar lectura/escritura de registros
  - Configurar DSA desde Python
  - Procesar imagen de prueba
  - Validar performance counters
- [ ] Validación bit a bit: modelo C++ vs hardware FPGA
- [ ] Optimización de performance (pipeline, SIMD)
- [ ] Timing constraints (.sdc) para análisis de timing
- [ ] Documentación completa del flujo de validación

## Documentación Adicional

- **`REGISTER_MAP.md`**: Mapa completo de registros memory-mapped (0x00-0x3F)
  - Tabla detallada de todos los registros
  - Distribución de memoria optimizada
  - Ejemplos Python de acceso a registros
  - Casos de uso: stepping, CRC, performance monitoring

- **`DSA_INTEGRATION_GUIDE.md`**: Guía de uso del DSA integrado
  - Controles físicos (KEYs, switches, LEDs, HEX)
  - Flujos de trabajo completos
  - Troubleshooting específico del DSA

- **`.github/copilot-instructions.md`**: Instrucciones técnicas para desarrollo
  - Arquitectura completa del proyecto
  - Patrones de diseño y convenciones
  - Workflows de compilación y testing
  - Problemas conocidos y soluciones

- **`reference_model/README.md`**: Documentación del modelo C++
  - Compilación y ejecución
  - Formato de imágenes PGM
  - Validación de algoritmo Q8.8
