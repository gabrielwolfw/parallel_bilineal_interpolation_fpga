# Constantes para las direcciones de los registros en la FPGA

# Cambiarlos según el diseño del hardware
REG_CONFIG   = 0x01  # Dirección para tamaño/configuración de la imagen
REG_PIXELS   = 0x10  # Dirección para enviar los datos de la imagen
REG_CMD      = 0x20  # Dirección para comandos (iniciar procesamiento, etc.)
REG_STATE    = 0x21  # Dirección para estado/Ejecución FPGA
REG_RESULT   = 0x30  # Dirección para recibir los datos procesados

CMD_START    = 1     # Comando para iniciar procesamiento
STATE_IDLE   = 0     # FPGA en reposo
STATE_BUSY   = 1     # FPGA procesando
STATE_DONE   = 2     # FPGA ha terminado el proceso