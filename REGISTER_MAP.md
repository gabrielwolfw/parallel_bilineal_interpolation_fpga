# DSA Register Map - Memory-Mapped Configuration

## 📍 Distribución de Memoria (64KB Total)

```
┌──────────────────────────────────────────────────────────────┐
│ 0x0000 - 0x003F │ REGISTROS (64 bytes, 16 words)            │
├──────────────────────────────────────────────────────────────┤
│ 0x0040 - 0x007F │ RESERVADO (64 bytes - expansión futura)   │
├──────────────────────────────────────────────────────────────┤
│ 0x0080 - 0x7FFF │ INPUT IMAGE (32KB - 512 bytes)            │
├──────────────────────────────────────────────────────────────┤
│ 0x8000 - 0xFFFF │ OUTPUT IMAGE (32KB)                       │
└──────────────────────────────────────────────────────────────┘
```

**Optimización de Memoria**:
- ✅ Solo **64 bytes** para registros (vs 128 bytes anterior)
- ✅ **32KB** disponibles para imagen de entrada (suficiente para 180×180 pixels)
- ✅ **32KB** para imagen de salida
- ✅ Alineación word (4 bytes) para acceso eficiente

---

## 📋 Mapa de Registros (Word-Aligned)

| Address | Name | Width | RW | Description |
|---------|------|-------|-------|-------------|
| **0x00** | `CFG_WIDTH` | 16 | RW | Ancho imagen entrada (pixels) |
| **0x04** | `CFG_HEIGHT` | 16 | RW | Alto imagen entrada (pixels) |
| **0x08** | `CFG_SCALE_Q8_8` | 16 | RW | Factor de escala en Q8.8 |
| **0x0C** | `CFG_MODE` | 8 | RW | Bit[0]: start; Bit[1]: SIMD/SEQ; Bits[7:2]: SIMD_N index |
| **0x10** | `STATUS` | 32 | R | Bits: idle, busy, done, error, progress[7:0], fsm_state[15:0] |
| **0x14** | `SIMD_N` | 8 | RW | Número de lanes SIMD (1, 4, 8...) |
| **0x18** | `PERF_FLOPS` | 32 | R | Contador de operaciones aritméticas |
| **0x1C** | `PERF_MEM_RD` | 32 | R | Lecturas a BRAM |
| **0x20** | `PERF_MEM_WR` | 32 | R | Escrituras a BRAM |
| **0x24** | `STEP_CTRL` | 8 | RW | Modo stepping: 0=run, 1=step, 2=pause |
| **0x28** | `STEP_EXPOSE` | 32 | R | Puntero/offset para exponer buffers |
| **0x2C** | `ERR_CODE` | 16 | R | Código de error para diagnóstico |
| **0x30** | `IMG_IN_BASE` | 32 | RW | Base lógica de imagen de entrada (offset BRAM) |
| **0x34** | `IMG_OUT_BASE` | 32 | RW | Base lógica de imagen de salida |
| **0x38** | `CRC_CTRL` | 8 | RW | Bit[0]: CRC input enable; Bit[1]: CRC output enable |
| **0x3C** | `CRC_VALUE` | 32 | R | CRC32 calculado para última transferencia |

---

## 🔧 Detalles de Registros

### CFG_MODE (0x0C) - Control Principal

```
Bit 7 6 5 4 3 2 1 0
    └─────┬─────┘ │ │
          │       │ └─ START: Write 1 to start (auto-clear)
          │       └─── SIMD_MODE: 0=Sequential, 1=SIMD
          └─────────── SIMD_N_INDEX: Index for SIMD lanes
```

**Ejemplo de uso**:
```
0x01 = Start en modo Sequential
0x03 = Start en modo SIMD
0x00 = Idle
```

### STATUS (0x10-0x13) - Estado del DSA

```
Byte 0: [7:4] Reserved | [3] ERROR | [2] DONE | [1] BUSY | [0] IDLE
Byte 1: Progress (0-100%)
Byte 2: FSM State [7:0]
Byte 3: FSM State [15:8]
```

### STEP_CTRL (0x24) - Control de Stepping

```
0x00 = RUN mode (procesamiento continuo)
0x01 = STEP mode (avanzar 1 pixel por comando)
0x02 = PAUSE mode (detener procesamiento)
```

### CRC_CTRL (0x38) - Control de CRC

```
Bit[0]: Enable CRC para input transfers
Bit[1]: Enable CRC para output transfers
Bits[7:2]: Reserved
```

---

## 📝 Ejemplo de Uso desde Python

### Configurar e Iniciar DSA

```python
from jtag_fpga import *

conn = open_connection('localhost', 2540)

def write_word16(addr, value):
    """Write 16-bit value at word-aligned address"""
    set_address_to_fpga(conn, addr)
    write_value_to_fpga(conn, value & 0xFF)
    set_address_to_fpga(conn, addr + 1)
    write_value_to_fpga(conn, (value >> 8) & 0xFF)

def write_word32(addr, value):
    """Write 32-bit value at word-aligned address"""
    for i in range(4):
        set_address_to_fpga(conn, addr + i)
        write_value_to_fpga(conn, (value >> (8*i)) & 0xFF)

def read_word32(addr):
    """Read 32-bit value from word-aligned address"""
    value = 0
    for i in range(4):
        set_address_to_fpga(conn, addr + i)
        byte_val = read_value_from_fpga(conn)
        value |= (byte_val << (8*i))
    return value

# Configuración básica
write_word16(0x00, 256)           # CFG_WIDTH = 256
write_word16(0x04, 256)           # CFG_HEIGHT = 256
write_word16(0x08, 192)           # CFG_SCALE_Q8_8 = 0.75 (192/256)
write_word32(0x30, 0x00000080)    # IMG_IN_BASE = 0x80 (después de registros)
write_word32(0x34, 0x00008000)    # IMG_OUT_BASE = 0x8000

# Configurar SIMD (opcional)
set_address_to_fpga(conn, 0x14)
write_value_to_fpga(conn, 4)      # SIMD_N = 4 lanes

# Iniciar procesamiento en modo Sequential
set_address_to_fpga(conn, 0x0C)
write_value_to_fpga(conn, 0x01)   # CFG_MODE: START=1, SIMD=0

# Monitorear estado
while True:
    set_address_to_fpga(conn, 0x10)
    status = read_value_from_fpga(conn)
    
    idle  = bool(status & 0x01)
    busy  = bool(status & 0x02)
    done  = bool(status & 0x04)
    error = bool(status & 0x08)
    
    if done:
        print("✓ Procesamiento completado")
        break
    if error:
        # Leer código de error
        set_address_to_fpga(conn, 0x2C)
        err_low = read_value_from_fpga(conn)
        set_address_to_fpga(conn, 0x2D)
        err_high = read_value_from_fpga(conn)
        err_code = (err_high << 8) | err_low
        print(f"✗ Error: 0x{err_code:04X}")
        break
    
    time.sleep(0.1)

# Leer contadores de performance
flops = read_word32(0x18)
mem_rd = read_word32(0x1C)
mem_wr = read_word32(0x20)

print(f"Performance:")
print(f"  FLOPs: {flops}")
print(f"  Memory Reads: {mem_rd}")
print(f"  Memory Writes: {mem_wr}")
```

### Modo Stepping (Debug Paso a Paso)

```python
# Habilitar stepping mode
set_address_to_fpga(conn, 0x24)
write_value_to_fpga(conn, 0x01)  # STEP mode

# Iniciar procesamiento
set_address_to_fpga(conn, 0x0C)
write_value_to_fpga(conn, 0x01)  # START

# Avanzar pixel por pixel
for i in range(10):
    # Escribir 0x01 nuevamente para avanzar 1 step
    set_address_to_fpga(conn, 0x24)
    write_value_to_fpga(conn, 0x01)
    
    # Leer STEP_EXPOSE para ver estado intermedio
    expose_val = read_word32(0x28)
    print(f"Step {i}: Expose = 0x{expose_val:08X}")
    
    time.sleep(0.05)

# Volver a modo continuo
set_address_to_fpga(conn, 0x24)
write_value_to_fpga(conn, 0x00)  # RUN mode
```

### Verificación con CRC

```python
# Habilitar CRC para output
set_address_to_fpga(conn, 0x38)
write_value_to_fpga(conn, 0x02)  # CRC_CTRL: enable output CRC

# Iniciar procesamiento
set_address_to_fpga(conn, 0x0C)
write_value_to_fpga(conn, 0x01)

# Esperar completado...
# (polling STATUS como antes)

# Leer CRC calculado
crc = read_word32(0x3C)
print(f"Output CRC32: 0x{crc:08X}")
```

---

## 🎯 Ventajas de esta Distribución

1. **Uso Eficiente de Memoria**:
   - Solo 64 bytes para registros (vs 128-256 en diseño anterior)
   - 32KB completos para imágenes (suficiente para 180×180 @ 8bpp)

2. **Alineación Word**:
   - Todos los registros en offsets múltiplos de 4
   - Acceso más eficiente desde buses de 32 bits

3. **Escalabilidad**:
   - 64 bytes reservados (0x40-0x7F) para futuros registros
   - IMG_IN_BASE y IMG_OUT_BASE permiten reubicación dinámica

4. **Debug**:
   - Contadores de performance integrados
   - Modo stepping para análisis paso a paso
   - CRC para verificación de integridad

5. **Compatibilidad**:
   - Compatible con acceso byte a byte (JTAG actual)
   - Preparado para buses word-aligned (DMA futuro)

---

## 📐 Capacidad de Imágenes

Con 32KB por región:

| Formato | Tamaño Máximo |
|---------|---------------|
| 8 bpp (escala grises) | 181×181 pixels (~32.7KB) |
| 8 bpp (escala grises) | 180×180 pixels (32.4KB) ✓ |
| 8 bpp (escala grises) | 128×256 pixels (32KB) ✓ |

**Recomendación**: Usar imágenes de 180×180 o 128×256 para aprovechar al máximo el espacio sin overflow.

