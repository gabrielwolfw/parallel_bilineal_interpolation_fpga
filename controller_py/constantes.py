# ============================================================================
# CONSTANTES.PY - Configuración y direcciones de registros para DSA FPGA
# ============================================================================
# Proyecto: Parallel Bilinear Interpolation FPGA
# Descripción: Constantes organizadas para comunicación JTAG y registros
#              memory-mapped del DSA (Domain-Specific Architecture)
# ============================================================================

# ============================================================================
# CONFIGURACIÓN JTAG SERVER
# ============================================================================
JTAG_HOST = 'localhost'
JTAG_PORT = 2540
JTAG_TIMEOUT = 10  # segundos

# ============================================================================
# ANCHOS DE DATOS Y DIRECCIONES
# ============================================================================
VJTAG_DATA_WIDTH = 8   # bits (operaciones individuales)
VJTAG_ADDR_WIDTH = 16  # bits (64KB address space)

# ============================================================================
# DIRECCIONES DE REGISTROS MEMORY-MAPPED (64 bytes: 0x00-0x3F)
# ============================================================================
# Basado en REGISTER_MAP.md - Word-aligned (incrementos de 4 bytes)

# --- Configuración (0x00 - 0x0F) ---
REG_CFG_WIDTH      = 0x00  # [15:0] Ancho de imagen de entrada (píxeles)
REG_CFG_HEIGHT     = 0x04  # [15:0] Alto de imagen de entrada (píxeles)
REG_CFG_SCALE_Q8_8 = 0x08  # [15:0] Factor de escala Q8.8 (ej: 0x0080 = 0.5x)
REG_CFG_MODE       = 0x0C  # [3:0] Modo: 0=scalar, 1=SIMD2, 2=SIMD4, 3=SIMD8

# --- Estado y Control (0x10 - 0x2F) ---
REG_STATUS         = 0x10  # [7:0] Estado: bit0=idle, bit1=busy, bit2=done, bit3=error
REG_SIMD_N         = 0x14  # [3:0] SIMD lanes detectadas por hardware
REG_PERF_FLOPS     = 0x18  # [31:0] Contador de operaciones de punto flotante
REG_PERF_MEM_RD    = 0x1C  # [31:0] Contador de lecturas de memoria
REG_PERF_MEM_WR    = 0x20  # [31:0] Contador de escrituras de memoria
REG_PROGRESS       = 0x24  # [15:0] Progreso: píxeles procesados
REG_FSM_STATE      = 0x28  # [7:0] Estado interno de FSM
REG_ERR_CODE       = 0x2C  # [7:0] Código de error (si STATUS[3]=1)

# --- Control Avanzado (0x30 - 0x3F) ---
REG_IMG_IN_BASE    = 0x30  # [15:0] Dirección base imagen entrada (default: 0x0080)
REG_IMG_OUT_BASE   = 0x34  # [15:0] Dirección base imagen salida (default: 0x8000)
REG_CRC_CTRL       = 0x38  # [31:0] Control CRC: [15:0]=input_crc, [31:16]=output_crc
REG_CRC_VALUE      = 0x3C  # [31:0] Valor CRC calculado (lectura), stepping (escritura)

# ============================================================================
# MÁSCARAS Y BITS DE ESTADO (REG_STATUS @ 0x10)
# ============================================================================
STATUS_IDLE        = 0x01  # bit 0: DSA en reposo
STATUS_BUSY        = 0x02  # bit 1: Procesando
STATUS_DONE        = 0x04  # bit 2: Completado
STATUS_ERROR       = 0x08  # bit 3: Error detectado
STATUS_START       = 0x10  # bit 4: Start trigger (auto-clear)
STATUS_RESET       = 0x20  # bit 5: Reset DSA (auto-clear)

# ============================================================================
# MODOS DE OPERACIÓN (REG_CFG_MODE @ 0x0C)
# ============================================================================
MODE_SCALAR        = 0x00  # Procesamiento secuencial (1 pixel/ciclo)
MODE_SIMD2         = 0x01  # SIMD 2 lanes (2 pixels/ciclo)
MODE_SIMD4         = 0x02  # SIMD 4 lanes (4 pixels/ciclo)
MODE_SIMD8         = 0x03  # SIMD 8 lanes (8 pixels/ciclo)

# ============================================================================
# CÓDIGOS DE ERROR (REG_ERR_CODE @ 0x2C)
# ============================================================================
ERR_NONE           = 0x00  # Sin error
ERR_INVALID_DIM    = 0x01  # Dimensiones inválidas (0 o > 512)
ERR_INVALID_SCALE  = 0x02  # Factor de escala inválido (0 o >= 256)
ERR_MEM_OVERFLOW   = 0x03  # Overflow en memoria de salida
ERR_TIMEOUT        = 0x04  # Timeout en procesamiento

# ============================================================================
# REGIONES DE MEMORIA (64KB total: 0x0000 - 0xFFFF)
# ============================================================================
MEM_REGISTERS_START = 0x0000  # Inicio de registros
MEM_REGISTERS_END   = 0x003F  # Fin de registros (64 bytes)
MEM_RESERVED_START  = 0x0040  # Reservado para expansión
MEM_RESERVED_END    = 0x007F  # Fin de reserva (64 bytes)
MEM_INPUT_START     = 0x0080  # Inicio de imagen de entrada
MEM_INPUT_END       = 0x7FFF  # Fin de entrada (32KB - 512 bytes)
MEM_OUTPUT_START    = 0x8000  # Inicio de imagen de salida
MEM_OUTPUT_END      = 0xFFFF  # Fin de salida (32KB)

# ============================================================================
# CONSTANTES DE IMAGEN
# ============================================================================
MAX_IMAGE_WIDTH    = 512   # Máximo ancho de imagen (píxeles)
MAX_IMAGE_HEIGHT   = 512   # Máximo alto de imagen (píxeles)
MAX_INPUT_SIZE     = 32256 # Bytes máximos para imagen de entrada (0x0080-0x7FFF)
MAX_OUTPUT_SIZE    = 32768 # Bytes máximos para imagen de salida (0x8000-0xFFFF)

# ============================================================================
# FORMATO FIXED-POINT Q8.8
# ============================================================================
Q8_8_SCALE_050 = 0x0080  # 0.5x (128 en decimal)
Q8_8_SCALE_075 = 0x00C0  # 0.75x (192 en decimal)
Q8_8_SCALE_100 = 0x0100  # 1.0x (256 en decimal)
Q8_8_SCALE_150 = 0x0180  # 1.5x (384 en decimal)
Q8_8_SCALE_200 = 0x0200  # 2.0x (512 en decimal)

# ============================================================================
# COMANDOS LEGACY (compatibilidad con código anterior)
# ============================================================================
# NOTA: Estos nombres antiguos se mantienen para compatibilidad,
#       pero apuntan a los registros correctos del nuevo sistema
REG_CONFIG  = REG_CFG_WIDTH   # Legacy: registro de configuración
REG_PIXELS  = MEM_INPUT_START # Legacy: inicio de datos de píxeles
REG_CMD     = REG_STATUS      # Legacy: registro de comandos
REG_STATE   = REG_STATUS      # Legacy: registro de estado
REG_RESULT  = MEM_OUTPUT_START # Legacy: inicio de resultados

CMD_START   = STATUS_START    # Legacy: comando de inicio
STATE_IDLE  = STATUS_IDLE     # Legacy: estado en reposo
STATE_BUSY  = STATUS_BUSY     # Legacy: estado procesando
STATE_DONE  = STATUS_DONE     # Legacy: estado completado

# ============================================================================
# CONFIGURACIÓN DE TIMEOUT
# ============================================================================
DSA_PROCESSING_TIMEOUT = 30  # segundos (máximo tiempo de procesamiento)
JTAG_READ_TIMEOUT      = 5   # segundos (timeout para operaciones de lectura)
JTAG_WRITE_TIMEOUT     = 5   # segundos (timeout para operaciones de escritura)