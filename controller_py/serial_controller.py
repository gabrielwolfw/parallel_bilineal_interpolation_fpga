# ============================================================================
# SERIAL_CONTROLLER.PY - Controlador JTAG para DSA FPGA
# ============================================================================
# Proyecto: Parallel Bilinear Interpolation FPGA
# Descripción: Implementación real de comunicación JTAG para control del DSA
#              mediante socket TCP al servidor JTAG TCL (jtag_server.tcl)
# ============================================================================

from PIL import Image
import numpy as np
import time
import socket
import json
import os
from constantes import *

class SerialController:
    """
    Controlador JTAG para comunicación con FPGA DSA.
    
    Arquitectura de comunicación:
    Python Client ←TCP→ TCL Server (jtag_server.tcl) ←JTAG→ FPGA Hardware
    
    Protocolo binario:
    - SETADDR <16-bit-binary>\n  # Establece dirección (0x0000-0xFFFF)
    - WRITE <8-bit-binary>\n     # Escribe byte a dirección actual
    - READ\n                     # Lee byte de dirección actual
    """
    
    def __init__(self, host=None, port=None, timeout=None, config_file=None):
        """
        Inicializa controlador JTAG.
        
        Args:
            host: Dirección del servidor JTAG (default: localhost)
            port: Puerto del servidor JTAG (default: 2540)
            timeout: Timeout de socket en segundos (default: 10)
            config_file: Ruta a archivo config.json (opcional)
        """
        # Cargar configuración desde JSON si se proporciona
        self.config = self._load_config(config_file) if config_file else {}
        
        # Configuración JTAG con prioridad: args > config > constantes
        self.host = host or self.config.get('jtag', {}).get('host', JTAG_HOST)
        self.port = port or self.config.get('jtag', {}).get('port', JTAG_PORT)
        self.timeout = timeout or self.config.get('jtag', {}).get('timeout', JTAG_TIMEOUT)
        
        # Conexión
        self.connection = None
        self.verbose = self.config.get('debug', {}).get('verbose', False)
        
    def _load_config(self, config_file):
        """Carga configuración desde archivo JSON."""
        if not os.path.exists(config_file):
            print(f"[WARNING] Config file not found: {config_file}")
            return {}
        
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            print(f"[INFO] Configuration loaded from {config_file}")
            return config
        except Exception as e:
            print(f"[ERROR] Failed to load config: {e}")
            return {}
    
    def connect(self):
        """Establece conexión TCP con servidor JTAG."""
        try:
            self.connection = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            # Sin timeout para operaciones lentas (escrituras grandes)
            self.connection.settimeout(None)
            self.connection.connect((self.host, self.port))
            print(f"[JTAG CONNECTED] {self.host}:{self.port}")
            return True
        except Exception as e:
            print(f"[ERROR] JTAG connection failed: {e}")
            print(f"[HINT] Ensure jtag_server.tcl is running: quartus_stp -t vjtag_pc\\jtag_server.tcl")
            self.connection = None
            return False
    
    def disconnect(self):
        """Cierra conexión JTAG."""
        if self.connection:
            self.connection.close()
            self.connection = None
            print("[JTAG DISCONNECTED]")
    
    def _send_command(self, command):
        """Envía comando al servidor JTAG y recibe respuesta."""
        if not self.connection:
            raise Exception("JTAG not connected. Call connect() first.")
        
        try:
            # Enviar comando
            self.connection.sendall(command.encode('utf-8'))
            
            # Recibir respuesta (solo para READ)
            if command.startswith("READ"):
                response = self.connection.recv(1024).decode('utf-8').strip()
                return response
            return None
            
        except socket.timeout:
            raise Exception(f"JTAG timeout on command: {command}")
        except Exception as e:
            raise Exception(f"JTAG communication error: {e}")
    
    def set_address(self, address):
        """
        Establece dirección de memoria (16 bits).
        
        Args:
            address: Dirección 0x0000-0xFFFF
        """
        if address < 0 or address > 0xFFFF:
            raise ValueError(f"Invalid address: 0x{address:04X} (must be 0x0000-0xFFFF)")
        
        # Convertir a binario de 16 bits (sin prefijo 0b)
        binary_addr = format(address, '016b')
        command = f"SETADDR {binary_addr}\n"
        
        if self.verbose:
            print(f"[JTAG] SETADDR 0x{address:04X} -> {binary_addr}")
        
        self._send_command(command)
    
    def write_byte(self, value):
        """
        Escribe byte a dirección actual (8 bits).
        
        Args:
            value: Byte 0x00-0xFF
        """
        if value < 0 or value > 0xFF:
            raise ValueError(f"Invalid byte: 0x{value:02X} (must be 0x00-0xFF)")
        
        # Convertir a binario de 8 bits (sin prefijo 0b)
        binary_val = format(value, '08b')
        command = f"WRITE {binary_val}\n"
        
        if self.verbose:
            print(f"[JTAG] WRITE 0x{value:02X} -> {binary_val}")
        
        self._send_command(command)
    
    def read_byte(self):
        """
        Lee byte de dirección actual.
        
        Returns:
            Byte leído (0x00-0xFF)
        """
        command = "READ\n"
        response = self._send_command(command)
        
        # Servidor retorna valor hexadecimal (ej: "AB\n")
        value = int(response, 16)
        
        if self.verbose:
            print(f"[JTAG] READ -> 0x{value:02X}")
        
        return value
    
    def write_word16(self, address, value):
        """
        Escribe word de 16 bits (little-endian).
        
        Args:
            address: Dirección base
            value: Valor 16-bit (0x0000-0xFFFF)
        """
        if value < 0 or value > 0xFFFF:
            raise ValueError(f"Invalid word16: 0x{value:04X}")
        
        # Little-endian: LSB primero
        lsb = value & 0xFF
        msb = (value >> 8) & 0xFF
        
        self.set_address(address)
        self.write_byte(lsb)
        self.set_address(address + 1)
        self.write_byte(msb)
    
    def read_word16(self, address):
        """
        Lee word de 16 bits (little-endian).
        
        Args:
            address: Dirección base
        
        Returns:
            Valor 16-bit (0x0000-0xFFFF)
        """
        self.set_address(address)
        lsb = self.read_byte()
        self.set_address(address + 1)
        msb = self.read_byte()
        
        return (msb << 8) | lsb
    
    def write_word32(self, address, value):
        """
        Escribe word de 32 bits (little-endian).
        
        Args:
            address: Dirección base (word-aligned)
            value: Valor 32-bit (0x00000000-0xFFFFFFFF)
        """
        if value < 0 or value > 0xFFFFFFFF:
            raise ValueError(f"Invalid word32: 0x{value:08X}")
        
        # Little-endian: 4 bytes
        for i in range(4):
            byte_val = (value >> (i * 8)) & 0xFF
            self.set_address(address + i)
            self.write_byte(byte_val)
    
    def read_word32(self, address):
        """
        Lee word de 32 bits (little-endian).
        
        Args:
            address: Dirección base (word-aligned)
        
        Returns:
            Valor 32-bit (0x00000000-0xFFFFFFFF)
        """
        value = 0
        for i in range(4):
            self.set_address(address + i)
            byte_val = self.read_byte()
            value |= (byte_val << (i * 8))
        
        return value
    
    # ========================================================================
    # DSA-SPECIFIC FUNCTIONS
    # ========================================================================
    
    def configure_dsa(self, width, height, scale_q8_8, mode=MODE_SCALAR):
        """
        Configura parámetros del DSA.
        
        Args:
            width: Ancho de imagen (píxeles)
            height: Alto de imagen (píxeles)
            scale_q8_8: Factor de escala Q8.8 (ej: 0x0080 = 0.5x)
            mode: Modo de procesamiento (MODE_SCALAR, MODE_SIMD2, MODE_SIMD4, MODE_SIMD8)
        """
        print(f"[DSA CONFIG] Width={width}, Height={height}, Scale=0x{scale_q8_8:04X}, Mode={mode}")
        
        # Validaciones
        if width <= 0 or width > MAX_IMAGE_WIDTH:
            raise ValueError(f"Invalid width: {width} (must be 1-{MAX_IMAGE_WIDTH})")
        if height <= 0 or height > MAX_IMAGE_HEIGHT:
            raise ValueError(f"Invalid height: {height} (must be 1-{MAX_IMAGE_HEIGHT})")
        if scale_q8_8 <= 0 or scale_q8_8 >= 0x0200:  # 0.0 - 2.0
            raise ValueError(f"Invalid scale: 0x{scale_q8_8:04X} (must be 0x0001-0x01FF)")
        
        # Escribir registros de configuración
        self.write_word16(REG_CFG_WIDTH, width)
        self.write_word16(REG_CFG_HEIGHT, height)
        self.write_word16(REG_CFG_SCALE_Q8_8, scale_q8_8)
        self.write_word16(REG_CFG_MODE, mode)
        
        print(f"[DSA CONFIG] Configuration written to FPGA registers")
    
    def start_dsa(self):
        """Inicia procesamiento del DSA (pulsa bit START)."""
        # Leer estado actual
        status = self.read_byte_from_address(REG_STATUS)
        
        # Set START bit (auto-clear en hardware)
        new_status = status | STATUS_START
        self.write_byte_to_address(REG_STATUS, new_status)
        
        print(f"[DSA START] Processing started (STATUS: 0x{new_status:02X})")
    
    def get_status(self):
        """
        Lee estado del DSA.
        
        Returns:
            dict con flags: idle, busy, done, error
        """
        status = self.read_byte_from_address(REG_STATUS)
        
        return {
            'idle': bool(status & STATUS_IDLE),
            'busy': bool(status & STATUS_BUSY),
            'done': bool(status & STATUS_DONE),
            'error': bool(status & STATUS_ERROR),
            'raw': status
        }
    
    def wait_done(self, timeout=DSA_PROCESSING_TIMEOUT):
        """
        Espera a que DSA complete procesamiento.
        
        Args:
            timeout: Timeout en segundos
        
        Returns:
            True si completó, False si timeout
        """
        print(f"[DSA WAIT] Waiting for processing to complete (timeout={timeout}s)...")
        start_time = time.time()
        
        while (time.time() - start_time) < timeout:
            status = self.get_status()
            
            if status['error']:
                error_code = self.read_byte_from_address(REG_ERR_CODE)
                raise Exception(f"DSA error: code=0x{error_code:02X}")
            
            if status['done']:
                elapsed = time.time() - start_time
                print(f"[DSA DONE] Processing completed in {elapsed:.2f}s")
                return True
            
            time.sleep(0.1)  # Poll cada 100ms
        
        print(f"[DSA TIMEOUT] Processing did not complete in {timeout}s")
        return False
    
    def get_performance(self):
        """
        Lee contadores de performance.
        
        Returns:
            dict con: flops, mem_reads, mem_writes
        """
        return {
            'flops': self.read_word32(REG_PERF_FLOPS),
            'mem_reads': self.read_word32(REG_PERF_MEM_RD),
            'mem_writes': self.read_word32(REG_PERF_MEM_WR)
        }
    
    # ========================================================================
    # CONVENIENCE FUNCTIONS
    # ========================================================================
    
    def write_byte_to_address(self, address, value):
        """Escribe byte a dirección específica (SETADDR + WRITE)."""
        self.set_address(address)
        self.write_byte(value)
    
    def read_byte_from_address(self, address):
        """Lee byte de dirección específica (SETADDR + READ)."""
        self.set_address(address)
        return self.read_byte()
    
    def write_buffer(self, start_address, data, batch_size=256):
        """
        Escribe buffer de bytes a memoria contigua (optimizado con batch).
        
        Args:
            start_address: Dirección inicial
            data: Lista/array de bytes
            batch_size: Bytes a escribir antes de enviar (default: 256)
        """
        print(f"[JTAG] Writing {len(data)} bytes to 0x{start_address:04X}... (batch={batch_size})")
        
        # Buffer de comandos para envío en batch
        command_buffer = []
        
        for i, byte_val in enumerate(data):
            addr = start_address + i
            
            # Agregar comandos al buffer
            binary_addr = format(addr, '016b')
            binary_val = format(byte_val, '08b')
            command_buffer.append(f"SETADDR {binary_addr}\n")
            command_buffer.append(f"WRITE {binary_val}\n")
            
            # Enviar batch cuando se alcanza el tamaño o al final
            if len(command_buffer) >= batch_size * 2 or i == len(data) - 1:
                batch_commands = ''.join(command_buffer)
                self.connection.sendall(batch_commands.encode('utf-8'))
                command_buffer = []
                
                # Progreso cada 1024 bytes
                if (i + 1) % 1024 == 0:
                    print(f"[JTAG] Written {i + 1}/{len(data)} bytes...")
        
        print(f"[JTAG] Buffer write complete")
    
    def read_buffer(self, start_address, length, batch_size=256):
        """
        Lee buffer de bytes desde memoria contigua (optimizado con batch).
        
        Args:
            start_address: Dirección inicial
            length: Cantidad de bytes a leer
            batch_size: Comandos a enviar antes de leer (default: 256)
        
        Returns:
            Lista de bytes
        """
        print(f"[JTAG] Reading {length} bytes from 0x{start_address:04X}... (batch={batch_size})")
        
        data = []
        command_buffer = []
        
        for i in range(length):
            addr = start_address + i
            
            # Agregar comandos SETADDR + READ al buffer
            binary_addr = format(addr, '016b')
            command_buffer.append(f"SETADDR {binary_addr}\n")
            command_buffer.append(f"READ\n")
            
            # Enviar batch y leer respuestas
            if len(command_buffer) >= batch_size * 2 or i == length - 1:
                # Enviar comandos
                batch_commands = ''.join(command_buffer)
                self.connection.sendall(batch_commands.encode('utf-8'))
                
                # Leer respuestas (cada READ genera una respuesta)
                reads_in_batch = len(command_buffer) // 2
                for _ in range(reads_in_batch):
                    response = self.connection.recv(1024).decode('utf-8').strip()
                    value = int(response, 16)
                    data.append(value)
                
                command_buffer = []
                
                # Progreso cada 1024 bytes
                if (i + 1) % 1024 == 0:
                    print(f"[JTAG] Read {i + 1}/{length} bytes...")
        
        print(f"[JTAG] Buffer read complete")
        return data
    
    # ========================================================================
    # IMAGE PROCESSING FUNCTIONS (Legacy compatibility)
    # ========================================================================
    
    def cargar_imagen_grises(self, ruta_imagen, ruta_salida_grises=None, ruta_salida_txt=None):
        """
        Carga imagen y convierte a escala de grises.
        
        Args:
            ruta_imagen: Ruta a imagen de entrada
            ruta_salida_grises: (Opcional) Guardar imagen en grises
            ruta_salida_txt: (Opcional) Guardar valores de píxeles en txt
        
        Returns:
            (pixeles_list, shape_tuple)
        """
        imagen = Image.open(ruta_imagen).convert('L')
        pixels = np.array(imagen, dtype=int)
        print(f"[IMAGE] Loaded grayscale image: {pixels.shape}")

        if ruta_salida_grises:
            imagen.save(ruta_salida_grises)
            print(f"[IMAGE] Grayscale saved to: {ruta_salida_grises}")

        if ruta_salida_txt:
            with open(ruta_salida_txt, 'w') as f:
                for valor in pixels.flatten():
                    f.write(f"{valor}\n")
            print(f"[IMAGE] Pixel values saved to: {ruta_salida_txt}")

        return pixels.flatten().tolist(), pixels.shape
    
    def send(self, direccion, datos):
        """
        Legacy function: Envía datos a dirección (compatibilidad).
        
        Args:
            direccion: Dirección de registro
            datos: Valor o lista de valores
        """
        if isinstance(datos, list):
            # Múltiples datos: buffer write
            self.write_buffer(direccion, datos)
        else:
            # Dato único: write word16/byte
            if isinstance(datos, int):
                if datos <= 0xFF:
                    self.write_byte_to_address(direccion, datos)
                else:
                    self.write_word16(direccion, datos)
    
    def receive(self, direccion):
        """
        Legacy function: Recibe datos de dirección (compatibilidad).
        
        Args:
            direccion: Dirección de registro
        
        Returns:
            Valor leído
        """
        return self.read_byte_from_address(direccion)
    
    def procesar_imagen_fpga(self, ruta_imagen, ruta_out_gris=None, ruta_out_txt=None):
        """
        Procesa imagen completa en FPGA (workflow completo).
        
        Args:
            ruta_imagen: Ruta a imagen de entrada
            ruta_out_gris: (Opcional) Guardar imagen en grises
            ruta_out_txt: (Opcional) Guardar valores de píxeles
        
        Returns:
            Lista de píxeles procesados
        """
        # 1. Cargar imagen
        pixeles, shape = self.cargar_imagen_grises(ruta_imagen, ruta_out_gris, ruta_out_txt)
        alto, ancho = shape
        
        # 2. Conectar JTAG
        if not self.connection:
            if not self.connect():
                raise Exception("Failed to connect to JTAG server")
        
        # 3. Configurar DSA
        scale_factor = self.config.get('image', {}).get('scale_factor', 0.5)
        scale_q8_8 = int(scale_factor * 256)  # Convert to Q8.8
        mode = MODE_SCALAR  # Default mode
        
        self.configure_dsa(ancho, alto, scale_q8_8, mode)
        
        # 4. Enviar píxeles a memoria de entrada
        input_base = int(self.config.get('memory', {}).get('input_base_address', '0x0080'), 16)
        self.write_buffer(input_base, pixeles)
        
        # 5. Iniciar procesamiento
        self.start_dsa()
        
        # 6. Esperar completado
        timeout = self.config.get('processing', {}).get('timeout', DSA_PROCESSING_TIMEOUT)
        if not self.wait_done(timeout):
            raise Exception("DSA processing timeout")
        
        # 7. Leer resultados
        output_base = int(self.config.get('memory', {}).get('output_base_address', '0x8000'), 16)
        output_size = int((ancho * scale_factor) * (alto * scale_factor))
        datos_resultado = self.read_buffer(output_base, output_size)
        
        # 8. Mostrar performance
        perf = self.get_performance()
        print(f"[PERFORMANCE] FLOPS: {perf['flops']}, MEM_RD: {perf['mem_reads']}, MEM_WR: {perf['mem_writes']}")
        
        return datos_resultado


# ============================================================================
# EJEMPLO DE USO
# ============================================================================
if __name__ == "__main__":
    # Inicializar con config.json
    controlador = SerialController(config_file="config.json")
    
    # Conectar a servidor JTAG
    if controlador.connect():
        try:
            # Procesar imagen
            ruta_imagen = "images/Super-GT.jpg"
            ruta_grises = "images/grises.png"
            ruta_txt = "grayscale/pixeles_grises.txt"
            
            resultado = controlador.procesar_imagen_fpga(ruta_imagen, ruta_grises, ruta_txt)
            print(f"[SUCCESS] Processing complete. Output pixels: {len(resultado)}")
            
        except Exception as e:
            print(f"[ERROR] {e}")
        finally:
            # Desconectar
            controlador.disconnect()
    else:
        print("[FAILED] Could not connect to JTAG server")
