# Guía de Integración DSA - Interpolación Bilineal FPGA

**Versión**: 2.0 - Con Registros Memory-Mapped  
**Última actualización**: 4 de diciembre de 2025

## 📌 Archivo Principal

**`dsa_top_integrated.sv`** - Top-level que integra:

1. ✅ Interfaz VJTAG (comunicación PC-FPGA)
2. ✅ RAM dual-port 64KB (Altsyncram)
3. ✅ DSA completo (interpolación bilineal Q8.8)
4. ✅ **Registros Memory-Mapped** (configuración dinámica)
5. ✅ Control con KEYs y SWITCHes (legacy)
6. ✅ Displays HEX para debug

## ⚠️ Cambio Importante: Configuración Dinámica

**NUEVO**: La configuración del DSA se realiza mediante **registros memory-mapped** (0x00-0x3F) usando `dsa_config.py`.

**Ventajas**:
- ✅ Configuración sin recompilar hardware
- ✅ Parámetros flexibles (width, height, scale, bases de memoria)
- ✅ Monitoreo de estado y performance en tiempo real
- ✅ API Python de alto nivel

Ver **`REGISTER_MAP.md`** para documentación completa de registros.

## Diferencias Principales con el Ejemplo

### 1. **Memoria**

**Ejemplo** (memoria bankeada SIMD):
```systemverilog
dsa_mem_banked #(
    .MEM_SIZE(MEM_SIZE),
    .ADDR_WIDTH(ADDR_WIDTH)
) mem_inst (
    .simd_write_en(simd_parallel_write),
    .simd_base_addr(write_base_addr),
    .simd_data_0(dp_simd_pixel_latched[0]),
    // ...
);
```

**Tu implementación** (RAM dual-port estándar):
```systemverilog
ram ram_inst (
    .clock(clk),
    .data(ram_data),
    .rdaddress(ram_rdaddress),
    .wraddress(ram_wraddress),
    .wren(ram_wren),
    .q(ram_q)
);
```

### 2. **Modos de Operación**

**Ejemplo**: SIMD vs Secuencial seleccionado por `mode_simd`

**Tu versión**: 
- **JTAG Debug Mode** (`SW[0]=0`): Acceso directo a memoria desde PC
- **DSA Processing Mode** (`SW[0]=1`): Interpolación bilineal activa

### 3. **Organización de Memoria**

```
Dirección       Contenido
-----------     ----------------------------------
0x0000-0x7FFF   Imagen de entrada (32KB, primera mitad)
0x8000-0xFFFF   Imagen de salida (32KB, segunda mitad)
```

### 4. **Interfaz de Control**

#### KEYs (activos en bajo):
- **KEY[3]**: Reset general del sistema
- **KEY[2]**: Reset del DSA
- **KEY[1]**: Decrementar dirección manual
- **KEY[0]**: Incrementar dirección manual

#### Switches:
- **SW[0]**: Modo de visualización
  - `0` = JTAG (mostrar dirección/dato JTAG)
  - `1` = Manual (mostrar dirección/dato manual con KEYs)
- **SW[1]**: Start DSA
  - `1` = Activar procesamiento de interpolación
- **SW[9:2]**: Scale factor (0-255)
  - Representa factor de escala en formato Q8.8 dividido por 256
  - Ejemplo: SW[9:2]=192 → scale_factor=0.75 (192/256)

#### LEDs Debug:
- **LEDR[0]**: Modo visualización (SW[0]: 0=JTAG, 1=Manual)
- **LEDR[1]**: DSA enable (SW[1])
- **LEDR[2]**: DSA ready (procesamiento completado)
- **LEDR[3]**: DSA busy (procesando)
- **LEDR[4]**: KEY[0] presionado (incrementar dirección)
- **LEDR[5]**: KEY[1] presionado (decrementar dirección)
- **LEDR[6]**: Escritura a memoria activa
- **LEDR[7]**: Fetch module ocupado
- **LEDR[9:8]**: Estado superior

#### HEX Displays:

**Modo JTAG** (`SW[0]=0`):
```
HEX5 HEX4 HEX3 HEX2 | HEX1 HEX0
Dirección JTAG      | Dato RAM
```

**Modo Manual** (`SW[0]=1`):
```
HEX5 HEX4 HEX3 HEX2 | HEX1 HEX0
Dirección Manual    | Dato RAM
```

*Nota: Se puede navegar la dirección manual con KEY[0] (incrementar) y KEY[1] (decrementar)*

---

## Configuración del Proyecto

### Parámetros Configurables

```systemverilog
parameter int DATA_WIDTH = 8,          // 8 bits por píxel
parameter int ADDR_WIDTH = 16,         // 64KB de memoria
parameter int IMG_WIDTH_MAX = 512,     // Máximo ancho soportado
parameter int IMG_HEIGHT_MAX = 512     // Máximo alto soportado
```

### Configuración de Imagen (Hardcoded)

En el código:
```systemverilog
assign img_width_in = 16'd256;   // 256x256 píxeles
assign img_height_in = 16'd256;
assign scale_factor = SW[9:2];   // Factor de escala desde switches
assign display_mode = SW[0];     // 0=JTAG, 1=Manual
assign dsa_enable = SW[1] && dsa_start;  // SW[1] habilita DSA
```

**Para cambiar dimensiones**: Modificar `img_width_in` e `img_height_in` según tu imagen de prueba.

### Configuración Dinámica con Registros (Nuevo)

**Sin recompilar hardware**, puedes configurar:

```python
from vjtag_pc.dsa_config import DSAConfig

dsa = DSAConfig('localhost', 2540)

# Configuración flexible
dsa.configure(
    width=180,           # Cualquier tamaño
    height=180,
    scale=0.5,           # 0.0 a 1.0
    img_in_base=0x0080,  # Relocatable
    img_out_base=0x8000,
    simd_lanes=1         # 1, 4, 8 (futuro)
)
```

**Registros disponibles** (ver `REGISTER_MAP.md`):
- `CFG_WIDTH` (0x00): Ancho imagen
- `CFG_HEIGHT` (0x04): Alto imagen
- `CFG_SCALE_Q8_8` (0x08): Factor escala Q8.8
- `CFG_MODE` (0x0C): Control start/mode
- `STATUS` (0x10): Estado idle/busy/done/error
- `PERF_*` (0x18-0x20): Contadores performance

---

## Módulos DSA Requeridos

Asegúrate de tener estos archivos en tu proyecto:

```
fpga/
├── dsa_control_fsm_sequential.sv   ✅ Controla el flujo de procesamiento
├── dsa_pixel_fetch_sequential.sv   ✅ Lee píxeles vecinos de memoria
├── dsa_datapath.sv                 ✅ Calcula interpolación bilineal Q8.8
└── vjtag_interface.sv              ✅ Ya existe (con CDC)
```

---

## Flujo de Operación

### Método 1: API Python (RECOMENDADO)

```python
from vjtag_pc.dsa_config import DSAConfig

# 1. Conectar
dsa = DSAConfig('localhost', 2540)

# 2. Cargar imagen en memoria (0x0080+)
# ... usar jtag_fpga.py o escribir bytes directamente ...

# 3. Configurar parámetros
dsa.configure(
    width=256,
    height=256,
    scale=0.75,
    img_in_base=0x0080,
    img_out_base=0x8000
)

# 4. Iniciar procesamiento
dsa.start(simd_mode=False)

# 5. Esperar completado (con progress)
if dsa.wait_done(timeout=30):
    print("✓ Completado")
    dsa.print_performance()
else:
    print("✗ Error o timeout")
    status = dsa.get_status()
    print(f"Estado: {status}")

# 6. Leer resultado desde 0x8000
```

### Método 2: Control Manual (Legacy)

### 1. Cargar Imagen de Entrada (Modo JTAG)

```powershell
# En Quartus TCL Console
quartus_stp -t vjtag_pc\jtag_server.tcl

# En PowerShell (otra terminal)
python vjtag_pc\jtag_fpga.py

# Cargar imagen desde 0x0000
setaddr 0000
write AA
write BB
# ... (o usar script automatizado)
```

### 2. Configurar Scale Factor

```
SW[9:1] = Factor de escala deseado
Ejemplo: Para 0.75 → SW[9:1] = 192 (decimal) = 0xC0 (hex)
### 3. Ejecutar Procesamiento

**Opción A: Control Legacy con Switches (Hardware)**
```
1. Configurar scale factor con SW[9:2] (ej: 192 para 0.75)
2. SW[1] = 1 (activar DSA)
3. Observar LEDs:
   - LEDR[1] = 1: DSA habilitado
   - LEDR[3] = 1: Procesando
   - LEDR[2] = 1: Terminado
4. Monitorear progreso con LEDR[7] (fetch) y LEDR[6] (write)
```

**Opción B: Control Dinámico con Python (Recomendado)** ✨
```python
from controller_py.serial_controller import SerialController

# Conectar al servidor JTAG
ctrl = SerialController(config_file="controller_py/config.json")
ctrl.connect()

# Configurar DSA
ctrl.configure_dsa(width=256, height=256, scale_q8_8=0x00C0, mode=MODE_SIMD4)

# Iniciar procesamiento
ctrl.start_dsa()

# Esperar completado
if ctrl.wait_done(timeout=30):
    print("Procesamiento completo!")
    
    # Leer performance
    perf = ctrl.get_performance()
    print(f"FLOPS: {perf['flops']}, Reads: {perf['mem_reads']}, Writes: {perf['mem_writes']}")

ctrl.disconnect()
```

**Opción C: GUI Completa** 🖥️
```powershell
# Ejecutar interfaz gráfica
cd controller_py
python interface_serial.py
```

La GUI permite:
- Conectar/desconectar JTAG
- Configurar parámetros DSA (width, height, scale, modo SIMD)
- Cargar y procesar imágenes completas
- Ver registros DSA con valores reales de FPGA
- Acceso manual a memoria (lectura/escritura hex)

### 4. Leer Resultado

**Opción A: Modo Manual (con KEYs)**
```
1. SW[0] = 1 (modo manual)
2. SW[1] = 0 (desactivar DSA)
3. Usar KEY[0]/KEY[1] para navegar desde dirección 0x8000
4. HEX muestra dirección y dato actual
```

**Opción B: Modo JTAG (desde PC)**
```
1. SW[0] = 0 (modo JTAG)
2. Usar jtag_fpga.py para leer desde 0x8000 en adelante
```

---

## Diferencias de Implementación

| Característica | Ejemplo Proporcionado | Tu Implementación |
|----------------|----------------------|-------------------|
| **Memoria** | Bancos SIMD (4 escrituras paralelas) | RAM dual-port (1 escritura/ciclo) |
| **Modos** | SIMD + Secuencial | Solo Secuencial |
| **Control** | Señales genéricas | KEYs + Switches DE1-SoC |
| **Debug** | Minimal | VJTAG + HEX displays + LEDs |
| **Addressing** | Parámetro genérico | 16-bit fijo (64KB) |
| **Image Load** | External interface | JTAG PC communication |

---

## Performance Esperado

Para imagen **256×256 → 192×192** (scale=0.75):

```
Píxeles de salida: 192 × 192 = 36,864
Ciclos por píxel: ~10-15 (fetch + interpolate + write)
Total ciclos: ~450,000 ciclos
A 50MHz: ~9ms de procesamiento
```

---

## Siguiente Paso: Actualizar Quartus

### Reemplazar dsa_top.sv

```powershell
# Backup del archivo original
Copy-Item dsa_top.sv dsa_top_jtag_only.sv

# Usar versión integrada
Copy-Item dsa_top_integrated.sv dsa_top.sv
```

### Actualizar project_dsa.qsf

Agregar archivos DSA:

```tcl
set_global_assignment -name SYSTEMVERILOG_FILE fpga/dsa_control_fsm_sequential.sv
set_global_assignment -name SYSTEMVERILOG_FILE fpga/dsa_pixel_fetch_sequential.sv
set_global_assignment -name SYSTEMVERILOG_FILE fpga/dsa_datapath.sv
```

### Recompilar

```powershell
quartus_sh --flow compile project_dsa
```

---

## Troubleshooting

### Error: "Module not found"
- Verificar que archivos `fpga/dsa_*.sv` estén en el .qsf
- Revisar que nombres de módulos coincidan

### DSA no arranca (LEDR[3] no enciende)
- Verificar que `SW[1]=1` (DSA enable)
- Presionar `KEY[2]` para reset DSA
- Verificar LEDR[1]=1 (DSA habilitado)
- Verificar que scale_factor (SW[9:2]) no sea 0

### Resultado incorrecto
- Verificar que imagen de entrada esté en direcciones 0x0000-0x7FFF
- Confirmar dimensiones configuradas (256×256)
- Revisar scale_factor calculado desde SW[9:1]

### VJTAG no conecta
- Asegurarse que FPGA esté programado con nuevo .sof
- Verificar que TCL server esté corriendo
- Probar con `python vjtag_pc\jtag_fpga.py -v`

---

## Mejoras Futuras

1. **Configuración dinámica de imagen** vía registros VJTAG
2. **Modo SIMD** para acelerar 4x (requiere memoria bankeada)
3. **Performance counters** visibles en HEX displays
4. **Auto-start** al detectar carga de imagen completa
5. **Status register** accesible vía JTAG

---

## Notas Importantes

⚠️ **Memoria limitada**: RAM de 64KB permite máximo 256×256 entrada + salida simultáneas

⚠️ **Scale factor**: Valores muy pequeños (<0.5) pueden causar overflow en direccionamiento

⚠️ **Timing**: Asegurarse que design cumple timing constraints a 50MHz

✅ **Ventaja**: Sistema completamente auto-contenido - no requiere interfaces externas

✅ **Debug**: VJTAG permite verificar cada paso sin necesidad de UART/VGA

---

## Contacto y Soporte

Para problemas específicos, revisar:
- `testbench/tb_dsa_top.sv` - Testbench de simulación
- `reference_model/` - Modelo C++ de referencia
- `.github/copilot-instructions.md` - Documentación del proyecto
