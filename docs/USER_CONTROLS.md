# Control y Visualización - Guía de Usuario

## 🎮 Controles de la FPGA

### **SW[0] - Modo de Visualización**

| Estado | Función | 7-Segmentos Muestra |
|--------|---------|-------------------|
| **0** (OFF) | Modo **Read** | Navegación con botones |
| **1** (ON) | Modo **JTAG** | Operaciones desde PC |

### **SW[1] - Contenido a Mostrar**

| Estado | Función | HEX5-2 Muestra |
|--------|---------|----------------|
| **0** (OFF) | Mostrar **Data** | Dato de 8 bits (00-FF) |
| **1** (ON) | Mostrar **Address** | Dirección de 18 bits (4 dígitos hex) |

### **KEY[0] - Incrementar Dirección** ⬆️

- Presionar: Incrementa dirección de lectura en +1
- Con debounce de 10ms (anti-rebote)
- **Límite superior**: Se detiene en dirección máxima (262,143 = 0x3FFFF)
- Solo activo en modo Read (SW[0]=0)

### **KEY[1] - Decrementar Dirección** ⬇️

- Presionar: Decrementa dirección de lectura en -1
- Con debounce de 10ms
- **Límite inferior**: Se detiene en dirección 0
- Solo activo en modo Read (SW[0]=0)

### **KEY[3] - Reset** 🔄

- Presionar: Reset general del sistema (activo bajo)
- Reinicia dirección a 0, FSM JTAG, y todos los registros

### **SW[9] - Reset por Switch** 🔄

- ON (1): Mantiene sistema en reset
- OFF (0): Funcionamiento normal
- Útil para debugging sin presionar botón

## 📺 Displays de 7-Segmentos

### **Configuración de Modos (4 combinaciones)**

| SW[0] | SW[1] | HEX1-0 | HEX5-2 Muestra | Descripción |
|-------|-------|--------|----------------|-------------|
| 0 | 0 | **"rd"** | Dato leído en navegación | Read mode, Data |
| 0 | 1 | **"rA"** | Dirección de navegación | Read mode, Address |
| 1 | 0 | **"Jd"** | Dato JTAG (WRITE/READ) | JTAG mode, Data |
| 1 | 1 | **"JA"** | Dirección JTAG (SETADDR) | JTAG mode, Address |

### **HEX5-2: Valor Principal (16 bits)**
Muestra 4 dígitos hexadecimales según modo:

**Modo Data (SW[1]=0):**
- Muestra byte replicado: `0xAB` → `"ABAB"`
- Ejemplo: Dato 0x5A se muestra como `5A5A`

**Modo Address (SW[1]=1):**
- Muestra 16 bits menos significativos de dirección (18 bits totales)
- Ejemplo: Dirección 0x12345 → `"2345"`
- Ejemplo: Dirección 0x00100 → `"0100"`

### **HEX1-0: Indicador de Modo**
- **"rd"**: Read mode, mostrando Data
- **"rA"**: Read mode, mostrando Address
- **"Jd"**: JTAG mode, mostrando Data
- **"JA"**: JTAG mode, mostrando Address

## 🔴 LEDs Indicadores

| LED | Función | Significado cuando está ON |
|-----|---------|---------------------------|
| **LEDR[0]** | JTAG Write Enable | PC está escribiendo a RAM |
| **LEDR[1]** | FSM SETADDR activo | Procesando comando SETADDR |
| **LEDR[2]** | FSM WRITE activo | Procesando comando WRITE |
| **LEDR[3]** | RAM Write Enable | Escritura real a memoria RAM |
| **LEDR[4]** | RAM Read Enable | Lectura de memoria RAM |
| **LEDR[5]** | (Reservado) | Disponible para expansión |
| **LEDR[6]** | (Reservado) | Disponible para expansión |
| **LEDR[7]** | FSM JTAG Activa | Estado ≠ IDLE (procesando) |
| **LEDR[8]** | LSB Dirección JTAG | Bit menos significativo de dirección |
| **LEDR[9]** | Modo Display | 0=Read, 1=JTAG |

## 📝 Ejemplos de Uso

### Ejemplo 1: Escribir Dirección y Ver en Display

```powershell
# 1. Desde Python client
python jtag_fpga.py

# 2. En la consola interactiva:
JTAG-8bit> setaddr 0x12345
|INFO| Address set to 0x12345

# 3. En FPGA configurar:
#    SW[0] = 1 (Modo JTAG)
#    SW[1] = 1 (Mostrar Address)

# 4. Observar en displays:
#    HEX1-0: "JA" (JTAG mode, Address)
#    HEX5-2: "2345" (16 bits LSB de 0x12345)
#    LEDR[1]: Parpadeará durante SETADDR
```

### Ejemplo 2: Escribir Dato y Verificar

```powershell
# 1. Configurar dirección
JTAG-8bit> setaddr 0x100

# 2. Escribir dato
JTAG-8bit> write 0xAB
|INFO| Successfully wrote 0xAB to memory

# 3. Ver dato escrito:
#    SW[0] = 1 (Modo JTAG)
#    SW[1] = 0 (Mostrar Data)
#    HEX5-2 muestra: "ABAB"
#    LEDR[0] y LEDR[2] parpadean

# 4. Leer de vuelta:
JTAG-8bit> read
|RESULT| Read value: 171 (0xAB)
```

### Ejemplo 3: Navegar Memoria con Botones

```powershell
# 1. Escribir patrón desde PC
JTAG-8bit> setaddr 0
JTAG-8bit> write 0x11
JTAG-8bit> write 0x22
JTAG-8bit> write 0x33
JTAG-8bit> write 0x44

# 2. En FPGA:
#    SW[0] = 0 (Modo Read)
#    SW[1] = 0 (Mostrar Data)
#    HEX1-0: "rd"
#    HEX5-2: "1111" (dato en dir 0)

# 3. Presionar KEY[0] (incrementar):
#    - HEX5-2 cambia a "2222" (dato en dir 1)
#    - Presionar de nuevo → "3333" (dir 2)
#    - Presionar de nuevo → "4444" (dir 3)

# 4. Cambiar SW[1] = 1 para ver direcciones:
#    HEX1-0: "rA"
#    HEX5-2: "0003" (dirección actual)
#    Presionar KEY[1] → "0002", "0001", "0000"
```

### Ejemplo 4: Usar readaddr (Comando Combinado)

```powershell
# Lee desde dirección específica sin cambiar dirección actual
JTAG-8bit> readaddr 0x12345
|INFO| Setting address to: 74565 (0x12345)
|INFO| Address set to 0x12345
|INFO| Reading value at current address
|RESULT| Read value: 0 (0x00)

# El comando hace SETADDR + READ automáticamente
# Útil para lectura rápida sin afectar estado
```

## 🔧 Troubleshooting

### No veo cambios en HEX5-2

**Modo Read (SW[0]=0):**
- ✓ Verifica que hay datos en memoria
- ✓ Presiona KEY[0] o KEY[1] para cambiar dirección
- ✓ Con SW[1]=0 verás dato, con SW[1]=1 verás dirección

**Modo JTAG (SW[0]=1):**
- ✓ Ejecuta comando SETADDR o WRITE desde PC
- ✓ Observa LEDR[1] o LEDR[2] - deben parpadear
- ✓ Con SW[1]=0 ves último dato, con SW[1]=1 ves última dirección

### Los displays muestran valores extraños

- ✓ Verifica HEX1-0 para confirmar modo activo
- ✓ En modo Address, solo ves 16 bits de 18 (bits [15:0])
- ✓ En modo Data, byte se replica: 0xAB → "ABAB"
- ✓ Presiona KEY[3] para reset completo

### LEDs no parpadean durante operaciones JTAG

- ✓ Verifica que servidor TCL está corriendo
- ✓ Confirma que cliente Python está conectado
- ✓ Revisa comandos: setaddr, write, read
- ✓ LEDR[7] debe estar ON cuando FSM no está en IDLE

### Los botones KEY[0]/KEY[1] no funcionan

- ✓ Solo funcionan en modo Read (SW[0]=0)
- ✓ Espera ~10ms entre presiones (debounce)
- ✓ En límites (0 o MAX), botón se desactiva
- ✓ Verifica que no estés en modo JTAG

## 🎯 Flujo de Trabajo Recomendado

### Para Debugging de Comunicación JTAG:

1. Iniciar servidor TCL: `.\start_jtag_server.ps1`
2. Ejecutar cliente Python: `python jtag_fpga.py`
3. **SW[0] = 1, SW[1] = 1** (Modo JTAG, ver Address)
4. Ejecutar `setaddr 0x12345` → Ver dirección en HEX5-2
5. **SW[1] = 0** (cambiar a ver Data)
6. Ejecutar `write 0xAB` → Ver dato en HEX5-2
7. Verificar LEDs parpadean (LEDR[0-2, 7])

### Para Verificación de Datos en Memoria:

1. Escribir datos desde PC con comandos JTAG
2. **SW[0] = 0** (Modo Read)
3. **SW[1] = 0** (Ver Data)
4. Usar KEY[0]/KEY[1] para navegar
5. Cambiar **SW[1] = 1** para ver direcciones
6. Confirmar consistencia de datos

### Para Test Completo de Sistema:

1. **Test de escritura**:
   - SW[0]=1, SW[1]=0
   - `setaddr 0x100`
   - `write 0xDE`, `write 0xAD`, `write 0xBE`, `write 0xEF`
   
2. **Test de lectura JTAG**:
   - `readaddr 0x100` → Debe retornar 0xDE
   - `readaddr 0x101` → Debe retornar 0xAD
   
3. **Test de navegación**:
   - SW[0]=0, SW[1]=0
   - KEY[0] hasta ver dirección deseada
   - Verificar datos en HEX5-2

4. **Test de modo Address**:
   - SW[0]=0, SW[1]=1
   - Navegar con KEY[0]/KEY[1]
   - Ver direcciones en HEX5-2

## 📊 Tabla de Referencia Rápida

| Quiero... | Configuración | Hacer... |
|-----------|---------------|----------|
| Ver dirección SETADDR desde PC | SW[0]=1, SW[1]=1 | Ejecutar `setaddr <addr>`, ver HEX5-2 |
| Ver dato WRITE desde PC | SW[0]=1, SW[1]=0 | Ejecutar `write <data>`, ver HEX5-2 |
| Ver dato en memoria navegando | SW[0]=0, SW[1]=0 | Usar KEY[0]/KEY[1], ver HEX5-2 |
| Ver dirección actual navegando | SW[0]=0, SW[1]=1 | Usar KEY[0]/KEY[1], ver HEX5-2 |
| Incrementar dirección de navegación | SW[0]=0 | Presionar KEY[0] |
| Decrementar dirección de navegación | SW[0]=0 | Presionar KEY[1] |
| Verificar comando SETADDR activo | - | LEDR[1] debe parpadear |
| Verificar comando WRITE activo | - | LEDR[2] debe parpadear |
| Saber si FSM está procesando | - | LEDR[7]=ON (no IDLE) |
| Reset completo del sistema | - | Presionar KEY[3] o SW[9]=ON |

## 🎓 Notas Técnicas

### Arquitectura del Sistema

- **FSM de JTAG**: 7 estados (IDLE, SET_ADDR, WAIT_SET_ADDR, WRITE, WAIT_WRITE, READ, WAIT_READ)
- **Sincronización de dominios**: TCK (JTAG) → CLK (50MHz) con 2-stage synchronizer
- **Edge detection**: UDR usa detector de flanco, no nivel
- **Wait states**: RAM tiene latencia de 1 ciclo, FSM espera apropiadamente

### Especificaciones Técnicas

- **Debounce**: 10ms (500,000 ciclos @ 50MHz)
- **Dirección máxima**: 262,143 (0x3FFFF) = 256KB - 1
- **Ancho de dirección**: 18 bits (completos en JTAG chain)
- **Ancho de dato**: 8 bits (0x00 - 0xFF)
- **Memoria RAM**: Dual-port Intel IP, 262,144 × 8 bits
- **Displays**: HEX5-2 muestran 16 bits (4 dígitos hex)
- **Clock**: 50MHz (CLOCK_50)

### Comandos JTAG Disponibles

| Comando | IR | DR Width | Función |
|---------|----|----|---------|
| BYPASS | 0x0 | 1 bit | Bypass estándar JTAG |
| WRITE | 0x1 | 8 bits | Escribir dato a memoria |
| READ | 0x2 | 8 bits | Leer dato de memoria |
| SETADDR | 0x3 | 18 bits | Establecer dirección |

### Flujo de Datos JTAG

```
Python Client (18-bit addr, 8-bit data)
    ↓
TCL Server (formatea binary strings)
    ↓
Quartus JTAG API (device_virtual_dr_shift)
    ↓
Virtual JTAG IP (sld_virtual_jtag)
    ↓
vjtag_interface.sv (DR_ADDR[17:0], DR1[7:0])
    ↓
dsa_de1soc_top.sv (FSM + sincronización)
    ↓
RAM (256KB dual-port)
```

### Multiplexor de Memoria

**Prioridad**: JTAG (cuando escribe) > Visualización (navegación)

```systemverilog
ram_addr_mux = ram_we_jtag ? ram_addr_jtag : display_address;
```

- Cuando JTAG escribe: usa dirección JTAG
- Caso contrario: usa dirección de navegación
- Sin conflictos porque JTAG tiene prioridad absoluta en escrituras
