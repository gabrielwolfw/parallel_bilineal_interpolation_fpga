# Comunicación PC ↔ FPGA vía JTAG - Inicio Rápido

Este es el sistema simplificado para escribir y leer memoria RAM de la FPGA mediante Virtual JTAG.

## 🚀 Inicio Rápido (3 pasos)

### 1. Compilar y programar FPGA

```powershell
cd fpga
quartus_sh --flow compile parallel_fpga
quartus_pgm -c "DE-SoC" -m jtag -o "p;output_files/parallel_fpga.sof@2"
```

### 2. Iniciar servidor JTAG

En una terminal de PowerShell:

```powershell
.\scripts\start_jtag_server.ps1
```

Deberías ver:
```
|INFO| VJTAG_DATA_WIDTH=8, TCP PORT=2540
Started Socket Server on port - 2540
```

### 3. Probar escritura/lectura

En **otra terminal**:

```powershell
# Escribir bytes individuales
python scripts/jtag_mem_writer.py --addr 0 --data 0xFF 0xAA 0x55

# Ejecutar test automático (256 bytes)
.\scripts\quick_test_jtag.ps1 -Verify
```

## 📁 Archivos Principales

### Hardware (FPGA)
- **`fpga/dsa_vjtag_mem_top.sv`**: Top-level con JTAG + Memoria RAM
- **`fpga/vjtag_interface.sv`**: Interfaz de protocolo JTAG
- **`fpga/vjtag_dsa/`**: IP Virtual JTAG generado por Quartus

### Software (PC)
- **`scripts/jtag_mem_writer.py`**: Cliente Python para escribir memoria
- **`scripts/start_jtag_server.ps1`**: Inicia servidor TCL
- **`scripts/quick_test_jtag.ps1`**: Test automatizado
- **`fpga/vjtag_pc/jtag_server.tcl`**: Servidor TCL JTAG
- **`fpga/vjtag_pc/jtag_fpga.py`**: Cliente interactivo

## 🎯 Uso Básico

### Escribir datos específicos

```powershell
# Escribir 4 bytes a partir de dirección 0x10
python scripts/jtag_mem_writer.py --addr 0x10 --data 0x12 0x34 0x56 0x78

# Con verificación
python scripts/jtag_mem_writer.py --addr 0 --data 0xFF 0xAA --verify

# Modo verbose (debug)
python scripts/jtag_mem_writer.py --addr 0 --data 0xFF -v
```

### Cargar archivo binario

```powershell
# Crear archivo de prueba
python -c "open('test.bin', 'wb').write(bytes(range(256)))"

# Cargar a FPGA
python scripts/jtag_mem_writer.py --addr 0 --file test.bin --verify
```

### Cliente interactivo

```powershell
cd fpga/vjtag_pc
python jtag_fpga.py -dw 8
```

```
JTAG-8bit> setaddr 0x00
JTAG-8bit> write 0xFF
JTAG-8bit> read
|RESULT| Read value: 255 (0xFF)
JTAG-8bit> exit
```

## 🔍 Debugging con LEDs

| LED | Señal |
|-----|-------|
| LEDR[0] | Escritura activa |
| LEDR[1] | Lectura display activa |
| LEDR[2] | Dato JTAG válido |
| LEDR[3] | Modo display (0=JTAG, 1=Memoria) |
| LEDR[4] | Pulso KEY[0] (incremento) |
| LEDR[5] | Pulso KEY[1] (decremento) |
| LEDR[7:6] | Estado FSM |
| LEDR[8] | En límite superior (addr=MAX) |
| LEDR[9] | En límite inferior (addr=0) |

| Display | Contenido |
|---------|-----------|
| HEX5-4 | Dirección de lectura actual |
| HEX3-2 | Dato (JTAG o Memoria según SW[0]) |
| HEX1-0 | Modo: "Jt"=JTAG, "EA"=Memoria |

## 🎮 Controles Físicos

### **SW[0] - Modo de Visualización**
- **OFF (0)**: Muestra último dato recibido de JTAG
- **ON (1)**: Muestra dato leído de memoria en dirección actual

### **KEY[0] - Incrementar Dirección**
- Incrementa dirección de lectura (+1)
- Debounce de 20ms
- Se detiene en dirección máxima

### **KEY[1] - Decrementar Dirección**
- Decrementa dirección de lectura (-1)
- Debounce de 20ms
- Se detiene en dirección 0

**Ejemplo de uso:**
```
1. Escribir datos: python scripts/jtag_mem_writer.py --addr 0 --data 0xFF 0xAA 0x55
2. SW[0] = OFF → Ver último byte escrito (0x55) en HEX3-2
3. SW[0] = ON → Ver datos en memoria
4. Presionar KEY[0] varias veces → Navegar por 0xFF, 0xAA, 0x55...
```

## 📖 Documentación Completa

Ver **[docs/JTAG_SETUP.md](docs/JTAG_SETUP.md)** para:
- Detalles del protocolo JTAG
- Arquitectura del sistema
- Troubleshooting
- Ejemplos avanzados

## ⚠️ Limitaciones

- **Dirección**: Solo 15 bits usables (0x0000 - 0x7FFF)
- **Ancho**: 8 bits por transferencia
- **Velocidad**: ~1KB/s típico

## 🔧 Troubleshooting

### "Connection refused"
→ Servidor TCL no está corriendo. Ejecuta `start_jtag_server.ps1`

### "No USB-Blaster found"
→ Verifica conexión USB y drivers. Ejecuta `jtagconfig`

### "No JTAG device found"
→ Programa el `.sof` primero

### Datos incorrectos
→ Verifica LEDs, usa modo verbose (`-v`)

## 🎓 Arquitectura

```
┌─────────────┐
│     PC      │
│  (Python)   │
└──────┬──────┘
       │ TCP Socket (port 2540)
       ↓
┌─────────────┐
│ TCL Server  │
│(jtag_server)│
└──────┬──────┘
       │ Quartus JTAG API
       ↓
┌─────────────┐
│ USB-Blaster │
└──────┬──────┘
       │ JTAG
       ↓
┌─────────────────────────────┐
│         FPGA                │
│  ┌──────────────────────┐   │
│  │  Virtual JTAG IP     │   │
│  │  (vjtag_dsa)         │   │
│  └──────┬───────────────┘   │
│         │                   │
│  ┌──────▼───────────────┐   │
│  │  vjtag_interface.sv  │   │
│  │  (Protocolo)         │   │
│  └──────┬───────────────┘   │
│         │                   │
│  ┌──────▼───────────────┐   │
│  │ dsa_vjtag_mem_top.sv │   │
│  │ (Control + FSM)      │   │
│  └──────┬───────────────┘   │
│         │                   │
│  ┌──────▼───────────────┐   │
│  │ dsa_mem_banked.sv    │   │
│  │ (256KB RAM)          │   │
│  └──────────────────────┘   │
└─────────────────────────────┘
```

## 📝 Siguiente: Integrar con DSA

Para usar este sistema con el acelerador de interpolación bilineal (`dsa_top.sv`):

1. Cargar imagen de entrada a memoria (dirección 0x00000)
2. Configurar parámetros del DSA
3. Ejecutar interpolación
4. Leer imagen de salida (dirección mitad de memoria)

Ver ejemplo completo en `examples/` (próximamente).
