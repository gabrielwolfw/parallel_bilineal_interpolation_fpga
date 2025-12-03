# Comunicación JTAG PC ↔ FPGA

Este sistema permite escribir y leer datos en la memoria RAM de la FPGA mediante JTAG (Virtual JTAG).

## Arquitectura

```
PC (Python) ←→ TCL Server ←→ Quartus JTAG ←→ FPGA (Virtual JTAG)
```

### Componentes

1. **FPGA (`dsa_vjtag_mem_top.sv`)**: Top-level con Virtual JTAG + Memoria RAM
2. **TCL Server (`jtag_server.tcl`)**: Servidor que traduce comandos TCP a comandos JTAG
3. **Python Client (`jtag_mem_writer.py`)**: Script para escribir/leer memoria desde PC

## Configuración Inicial

### 1. Generar el IP Virtual JTAG (ya hecho)

El directorio `vjtag_dsa/` contiene el IP generado con:
- **IR Width**: 2 bits (4 instrucciones)
- **Instance Index**: 0 (auto)

### 2. Compilar el diseño FPGA

```powershell
cd fpga
quartus_sh --flow compile parallel_fpga
```

O usar el script de build:

```powershell
.\build_and_program.ps1
```

### 3. Programar la FPGA

```powershell
quartus_pgm -c "DE-SoC" -m jtag -o "p;output_files/parallel_fpga.sof@2"
```

## Uso del Sistema

### Paso 1: Iniciar el servidor TCL JTAG

Desde la carpeta `fpga/vjtag_pc/`:

```powershell
quartus_stp -t jtag_server.tcl 8
```

**Parámetros**:
- `8`: Ancho de datos en bits (8 bits para este diseño)
- Puerto TCP: 2540 (por defecto)

Deberías ver:
```
|INFO| VJTAG_DATA_WIDTH=8, TCP PORT=2540
|INFO| Select JTAG chain connected to DE-SoC...
|INFO| Selected device: @2...
Started Socket Server on port - 2540
```

### Paso 2: Usar el cliente Python

#### Opción A: Script automatizado (Recomendado)

```powershell
# Escribir bytes individuales
python scripts/jtag_mem_writer.py --addr 0x00 --data 0xFF 0xAA 0x55 0x33

# Escribir desde archivo binario
python scripts/jtag_mem_writer.py --addr 0x00 --file image.bin

# Escribir y verificar
python scripts/jtag_mem_writer.py --addr 0x00 --data 0x12 0x34 --verify

# Modo verbose
python scripts/jtag_mem_writer.py --addr 0x00 --data 0xFF -v
```

#### Opción B: Cliente interactivo

```powershell
cd fpga/vjtag_pc
python jtag_fpga.py -dw 8
```

Comandos disponibles:
```
JTAG-8bit> setaddr 0x00      # Setear dirección de memoria
JTAG-8bit> write 0xFF         # Escribir byte
JTAG-8bit> read               # Leer byte actual
JTAG-8bit> readaddr 0x10      # Leer dirección específica
JTAG-8bit> exit
```

## Protocolo JTAG

### Instrucciones IR (2 bits)

| IR   | Nombre   | Función                              |
|------|----------|--------------------------------------|
| 0b00 | BYPASS   | Bypass estándar JTAG                 |
| 0b01 | WRITE    | Escribir dato a memoria actual       |
| 0b10 | READ     | Leer dato de memoria actual          |
| 0b11 | SET_ADDR | Setear dirección de memoria (15 bits)|

### Flujo de escritura

```
1. SETADDR 0x0000  → IR=11, DR=15 bits de dirección
2. WRITE 0xFF      → IR=01, DR=8 bits de dato
3. (auto-incremento de dirección)
4. WRITE 0xAA      → IR=01, DR=8 bits de dato
...
```

### Flujo de lectura

```
1. SETADDR 0x0000  → IR=11, DR=15 bits de dirección
2. READ            → IR=10, captura 8 bits de dato
```

## Señales de Debug

### LEDs (LEDR[9:0])

| LED    | Función                |
|--------|------------------------|
| LEDR[0]| Escritura a memoria    |
| LEDR[1]| Lectura de memoria     |
| LEDR[2]| Dato JTAG válido       |
| LEDR[3]| Dirección JTAG válida  |
| LEDR[7:4]| Dirección[3:0]       |
| LEDR[9:8]| Estado FSM           |

### 7-Segmentos

| Display | Contenido                    |
|---------|------------------------------|
| HEX0    | Dirección memoria [3:0]      |
| HEX1    | Dirección memoria [7:4]      |
| HEX2    | Dato escrito [3:0]           |
| HEX3    | Dato escrito [7:4]           |

## Ejemplos de Uso

### Ejemplo 1: Escribir patrón de prueba

```python
python scripts/jtag_mem_writer.py --addr 0 --data \
  0x00 0x11 0x22 0x33 0x44 0x55 0x66 0x77 \
  0x88 0x99 0xAA 0xBB 0xCC 0xDD 0xEE 0xFF \
  --verify
```

### Ejemplo 2: Cargar imagen pequeña

```python
# Crear archivo de prueba
python -c "open('test.bin', 'wb').write(bytes(range(256)))"

# Cargar a FPGA
python scripts/jtag_mem_writer.py --addr 0 --file test.bin --verify
```

### Ejemplo 3: Verificación manual

```powershell
python fpga/vjtag_pc/jtag_fpga.py -dw 8

JTAG-8bit> setaddr 0
JTAG-8bit> write 0xFF
JTAG-8bit> setaddr 0
JTAG-8bit> read
|RESULT| Read value: 255 (0xFF)
```

## Troubleshooting

### Error: "Connection refused"

- Verifica que el servidor TCL esté corriendo
- Comprueba que el puerto 2540 no esté en uso
- Asegúrate de estar en la red correcta (localhost)

### Error: "No USB-Blaster found"

- Verifica que la FPGA esté conectada por USB
- Instala los drivers USB-Blaster de Intel
- Ejecuta `jtagconfig` para ver dispositivos

### Error: "No JTAG device found"

- Programa el archivo `.sof` primero
- Verifica que el diseño incluya Virtual JTAG
- Revisa que el instance index sea 0

### Los datos no se escriben correctamente

- Verifica las señales en LEDs
- Revisa el dominio de reloj (sincronización tck → clk)
- Usa el modo verbose (`-v`) para debug

## Arquitectura del Sistema

### vjtag_interface.sv

- Maneja el protocolo JTAG de bajo nivel
- 3 registros DR: DR0 (bypass), DR1 (write/setaddr), DR2 (read)
- Genera señales `data_out`, `addr_out` hacia el dominio del sistema

### dsa_vjtag_mem_top.sv

- Sincroniza señales de JTAG (tck) a sistema (clk)
- FSM simple: IDLE → WRITE_MEM → WAIT
- Auto-incremento de dirección después de cada operación
- Instancia memoria bankeada de 256KB

### Limitaciones actuales

- **Dirección**: Solo se usan 15 bits (32KB direccionables vía SETADDR)
- **Ancho**: 8 bits por transferencia
- **Velocidad**: ~1KB/s (limitado por JTAG y sincronización)

Para direcciones completas de 18 bits, necesitarías:
- Enviar dirección en múltiples comandos SETADDR
- O implementar un protocolo de dirección extendida

## Próximos pasos

1. **Integrar con DSA**: Conectar este sistema con `dsa_top.sv` para cargar imágenes
2. **Dirección extendida**: Soportar 18 bits completos de dirección
3. **DMA**: Implementar transferencias más rápidas
4. **GUI**: Crear interfaz gráfica para operaciones comunes
