import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext
import subprocess
import os
import numpy as np
from PIL import Image

from serial_controller import SerialController
from constantes import *

class InterfazSerial:
    def __init__(self, root):
        self.root = root
        self.root.title("Control de FPGA - DSA Bilinear Interpolation")
        self.root.geometry("700x600")

        # Inicializar controlador con config.json
        self.controlador = SerialController(config_file="config.json")
        self.imagen_actual = None
        self.jtag_connected = False
        self.ultimo_resultado_fpga = None
        self.escala_actual = 0.5

        # --- Frame de Conexión JTAG ---
        frame_conexion = tk.Frame(root)
        frame_conexion.pack(pady=10)

        self.btn_conectar = tk.Button(frame_conexion, text="Conectar JTAG", command=self.conectar_jtag, bg="lightgreen")
        self.btn_conectar.pack(side=tk.LEFT, padx=5)

        self.btn_desconectar = tk.Button(frame_conexion, text="Desconectar JTAG", command=self.desconectar_jtag, bg="lightcoral", state=tk.DISABLED)
        self.btn_desconectar.pack(side=tk.LEFT, padx=5)

        self.label_estado = tk.Label(frame_conexion, text="Estado: Desconectado", fg="red", font=("Arial", 10, "bold"))
        self.label_estado.pack(side=tk.LEFT, padx=10)

        # --- Frame de Configuración DSA ---
        frame_config = tk.LabelFrame(root, text="Configuración DSA", padx=10, pady=10)
        frame_config.pack(pady=10, fill=tk.X, padx=20)

        tk.Label(frame_config, text="Ancho:").grid(row=0, column=0, sticky=tk.W)
        self.entry_width = tk.Entry(frame_config, width=10)
        self.entry_width.grid(row=0, column=1, padx=5)
        self.entry_width.insert(0, "256")

        tk.Label(frame_config, text="Alto:").grid(row=1, column=0, sticky=tk.W)
        self.entry_height = tk.Entry(frame_config, width=10)
        self.entry_height.grid(row=1, column=1, padx=5)
        self.entry_height.insert(0, "256")

        tk.Label(frame_config, text="Scale Factor:").grid(row=2, column=0, sticky=tk.W)
        self.entry_scale = tk.Entry(frame_config, width=10)
        self.entry_scale.grid(row=2, column=1, padx=5)
        self.entry_scale.insert(0, "0.5")

        tk.Label(frame_config, text="Modo:").grid(row=3, column=0, sticky=tk.W)
        self.mode_var = tk.StringVar(value="SCALAR")
        mode_options = ["SCALAR", "SIMD2", "SIMD4", "SIMD8"]
        self.dropdown_mode = tk.OptionMenu(frame_config, self.mode_var, *mode_options)
        self.dropdown_mode.grid(row=3, column=1, padx=5, sticky=tk.W)

        self.btn_configurar = tk.Button(frame_config, text="Configurar DSA", command=self.configurar_dsa)
        self.btn_configurar.grid(row=4, column=0, columnspan=2, pady=10)

        # --- Botones principales ---
        frame_botones = tk.Frame(root)
        frame_botones.pack(pady=10)

        tk.Button(frame_botones, text="Seleccionar imagen", command=self.seleccionar_imagen, width=18).grid(row=0, column=0, padx=5)
        tk.Button(frame_botones, text="Procesar imagen", command=self.procesar_imagen, width=18).grid(row=0, column=1, padx=5)
        tk.Button(frame_botones, text="Ver registros DSA", command=self.ver_registros, width=18).grid(row=0, column=2, padx=5)
        tk.Button(frame_botones, text="Validar vs Referencia", command=self.validar_pixel_a_pixel, width=18, bg="lightyellow").grid(row=1, column=0, padx=5, pady=5)
        tk.Button(frame_botones, text="Limpiar logs", command=self.limpiar_logs, width=18).grid(row=1, column=1, padx=5, pady=5)

        # --- Área para interactuar con direcciones y datos ---
        frame_memoria = tk.LabelFrame(root, text="Acceso Manual a Memoria", padx=10, pady=10)
        frame_memoria.pack(pady=10, fill=tk.X, padx=20)

        tk.Label(frame_memoria, text="Dirección (hex):").grid(row=0, column=0, sticky=tk.W)
        self.entry_dir = tk.Entry(frame_memoria, width=15)
        self.entry_dir.grid(row=0, column=1, padx=5)
        self.entry_dir.insert(0, "0x0080")

        tk.Button(frame_memoria, text="Leer dirección", command=self.leer_direccion).grid(row=0, column=2, padx=5)

        tk.Label(frame_memoria, text="Dato (hex):").grid(row=1, column=0, sticky=tk.W)
        self.entry_dato = tk.Entry(frame_memoria, width=15)
        self.entry_dato.grid(row=1, column=1, padx=5)
        self.entry_dato.insert(0, "0xFF")

        tk.Button(frame_memoria, text="Insertar dato", command=self.insertar_dato).grid(row=1, column=2, padx=5)

        # --- Area de logs (scrollable) ---
        tk.Label(root, text="Log de Operaciones:", font=("Arial", 9, "bold")).pack(anchor=tk.W, padx=20)
        self.log_display = scrolledtext.ScrolledText(root, height=15, width=85, state='normal')
        self.log_display.pack(pady=5, padx=20)

    def conectar_jtag(self):
        """Conecta al servidor JTAG."""
        self.log("[JTAG] Intentando conectar al servidor TCL...")
        
        if self.controlador.connect():
            self.jtag_connected = True
            self.label_estado.config(text="Estado: Conectado", fg="green")
            self.btn_conectar.config(state=tk.DISABLED)
            self.btn_desconectar.config(state=tk.NORMAL)
            self.log(f"[JTAG] Conectado a {self.controlador.host}:{self.controlador.port}")
        else:
            self.log("[ERROR] No se pudo conectar al servidor JTAG")
            self.log("[HINT] Ejecutar: quartus_stp -t vjtag_pc\\jtag_server.tcl")

    def desconectar_jtag(self):
        """Desconecta del servidor JTAG."""
        self.controlador.disconnect()
        self.jtag_connected = False
        self.label_estado.config(text="Estado: Desconectado", fg="red")
        self.btn_conectar.config(state=tk.NORMAL)
        self.btn_desconectar.config(state=tk.DISABLED)
        self.log("[JTAG] Desconectado")

    def configurar_dsa(self):
        """Configura parámetros del DSA."""
        if not self.jtag_connected:
            messagebox.showwarning("Error", "Debe conectar JTAG primero")
            return
        
        try:
            width = int(self.entry_width.get())
            height = int(self.entry_height.get())
            scale_factor = float(self.entry_scale.get())
            scale_q8_8 = int(scale_factor * 256)  # Convert to Q8.8
            
            # Mapear modo string a constante
            mode_map = {
                "SCALAR": MODE_SCALAR,
                "SIMD2": MODE_SIMD2,
                "SIMD4": MODE_SIMD4,
                "SIMD8": MODE_SIMD8
            }
            mode = mode_map[self.mode_var.get()]
            
            self.controlador.configure_dsa(width, height, scale_q8_8, mode)
            self.log(f"[DSA] Configurado: {width}x{height}, scale={scale_factor}, mode={self.mode_var.get()}")
            
        except Exception as e:
            self.log(f"[ERROR] Error al configurar DSA: {e}")

    def log(self, msg):
        """Agrega mensaje al log."""
        self.log_display.insert(tk.END, str(msg) + '\n')
        self.log_display.see(tk.END)
        print(msg)  # También imprimir en consola

    def limpiar_logs(self):
        """Limpia área de logs."""
        self.log_display.delete('1.0', tk.END)

    def seleccionar_imagen(self):
        """Selecciona imagen para procesamiento."""
        archivo = filedialog.askopenfilename(
            title="Selecciona una imagen", 
            filetypes=[("Imágenes", "*.jpg *.png *.bmp"), ("Todos", "*.*")]
        )
        if archivo:
            self.imagen_actual = archivo
            self.log(f"[IMG] Imagen seleccionada: {archivo}")

    def procesar_imagen(self):
        """Procesa imagen completa en FPGA."""
        if not self.jtag_connected:
            messagebox.showwarning("Error", "Debe conectar JTAG primero")
            return
        
        if not self.imagen_actual:
            messagebox.showwarning("Error", "Primero selecciona una imagen")
            return
        
        try:
            self.log(f"[IMG] Procesando imagen: {self.imagen_actual}")
            
            # Obtener parámetros de configuración
            width = int(self.entry_width.get())
            height = int(self.entry_height.get())
            self.escala_actual = float(self.entry_scale.get())
            
            # Mapear modo string a constante
            mode_map = {
                "SCALAR": MODE_SCALAR,
                "SIMD2": MODE_SIMD2,
                "SIMD4": MODE_SIMD4,
                "SIMD8": MODE_SIMD8
            }
            mode = mode_map[self.mode_var.get()]
            
            # Calcular dimensiones de salida
            output_width = int(width * self.escala_actual)
            output_height = int(height * self.escala_actual)
            self.log(f"[IMG] Dimensiones entrada: {width}x{height}")
            self.log(f"[IMG] Dimensiones salida: {output_width}x{output_height}")
            self.log(f"[IMG] Scale: {self.escala_actual}, Modo: {self.mode_var.get()}")
            
            ruta_out_gris = "interfaz_grises.png"
            ruta_out_txt = "interfaz_pixeles.txt"
            resultado = self.controlador.procesar_imagen_fpga(
                self.imagen_actual, 
                ruta_out_gris, 
                ruta_out_txt,
                scale_factor=self.escala_actual,  # Pasar escala de GUI
                mode=mode  # Pasar modo de GUI
            )
            
            # Guardar resultado para validación
            self.ultimo_resultado_fpga = resultado
            
            self.log(f"[SUCCESS] Procesamiento completado. Píxeles de salida: {len(resultado)}")
            
            # Generar imagen PGM del resultado FPGA
            if len(resultado) == output_width * output_height:
                output_pgm_path = "images/99_fpga_output.pgm"
                if self.guardar_resultado_fpga_como_pgm(resultado, output_width, output_height, output_pgm_path):
                    self.log(f"[IMG] Resultado FPGA guardado en: {output_pgm_path}")
                else:
                    self.log(f"[WARNING] No se pudo guardar imagen PGM del resultado FPGA")
            else:
                self.log(f"[WARNING] Cantidad de píxeles no coincide: esperado {output_width*output_height}, obtenido {len(resultado)}")
            
            # Mostrar performance
            perf = self.controlador.get_performance()
            self.log(f"[PERF] FLOPS: {perf['flops']}, MEM_RD: {perf['mem_reads']}, MEM_WR: {perf['mem_writes']}")
            
        except Exception as e:
            self.log(f"[ERROR] Error procesando imagen: {e}")
            messagebox.showerror("Error", f"Error al procesar imagen: {e}")

    def ver_registros(self):
        """Muestra información de registros DSA (lee valores reales)."""
        if not self.jtag_connected:
            messagebox.showwarning("Error", "Debe conectar JTAG primero")
            return
        
        try:
            self.log("=== REGISTROS DSA (Memory-Mapped) ===")
            
            # Configuración (word16)
            self.log("\n--- Configuración ---")
            width = self.controlador.read_word16(REG_CFG_WIDTH)
            self.log(f"REG_CFG_WIDTH     [0x{REG_CFG_WIDTH:04X}] = {width} pixels")
            
            height = self.controlador.read_word16(REG_CFG_HEIGHT)
            self.log(f"REG_CFG_HEIGHT    [0x{REG_CFG_HEIGHT:04X}] = {height} pixels")
            
            scale = self.controlador.read_word16(REG_CFG_SCALE_Q8_8)
            scale_float = scale / 256.0
            self.log(f"REG_CFG_SCALE_Q8_8[0x{REG_CFG_SCALE_Q8_8:04X}] = 0x{scale:04X} ({scale_float:.3f}x)")
            
            mode = self.controlador.read_word16(REG_CFG_MODE)
            mode_str = {0: "SCALAR", 1: "SIMD2", 2: "SIMD4", 3: "SIMD8"}.get(mode, f"Unknown({mode})")
            self.log(f"REG_CFG_MODE      [0x{REG_CFG_MODE:04X}] = {mode} ({mode_str})")
            
            # Estado (bytes)
            self.log("\n--- Estado ---")
            status = self.controlador.read_byte_from_address(REG_STATUS)
            status_bits = []
            if status & STATUS_IDLE: status_bits.append("IDLE")
            if status & STATUS_BUSY: status_bits.append("BUSY")
            if status & STATUS_DONE: status_bits.append("DONE")
            if status & STATUS_ERROR: status_bits.append("ERROR")
            status_str = " | ".join(status_bits) if status_bits else "None"
            self.log(f"REG_STATUS        [0x{REG_STATUS:04X}] = 0x{status:02X} ({status_str})")
            
            simd_n = self.controlador.read_byte_from_address(REG_SIMD_N)
            self.log(f"REG_SIMD_N        [0x{REG_SIMD_N:04X}] = {simd_n} lanes")
            
            err_code = self.controlador.read_byte_from_address(REG_ERR_CODE)
            err_str = {0: "NONE", 1: "INVALID_DIM", 2: "INVALID_SCALE", 3: "MEM_OVERFLOW", 4: "TIMEOUT"}.get(err_code, f"Unknown({err_code})")
            self.log(f"REG_ERR_CODE      [0x{REG_ERR_CODE:04X}] = 0x{err_code:02X} ({err_str})")
            
            # Performance (word32)
            self.log("\n--- Performance ---")
            flops = self.controlador.read_word32(REG_PERF_FLOPS)
            self.log(f"REG_PERF_FLOPS    [0x{REG_PERF_FLOPS:04X}] = {flops:,} ops")
            
            mem_rd = self.controlador.read_word32(REG_PERF_MEM_RD)
            self.log(f"REG_PERF_MEM_RD   [0x{REG_PERF_MEM_RD:04X}] = {mem_rd:,} reads")
            
            mem_wr = self.controlador.read_word32(REG_PERF_MEM_WR)
            self.log(f"REG_PERF_MEM_WR   [0x{REG_PERF_MEM_WR:04X}] = {mem_wr:,} writes")
            
            # Control avanzado (word16)
            self.log("\n--- Control Avanzado ---")
            img_in_base = self.controlador.read_word16(REG_IMG_IN_BASE)
            self.log(f"REG_IMG_IN_BASE   [0x{REG_IMG_IN_BASE:04X}] = 0x{img_in_base:04X}")
            
            img_out_base = self.controlador.read_word16(REG_IMG_OUT_BASE)
            self.log(f"REG_IMG_OUT_BASE  [0x{REG_IMG_OUT_BASE:04X}] = 0x{img_out_base:04X}")
            
            self.log("\n--- Regiones de Memoria ---")
            self.log(f"MEM_INPUT_START   = 0x{MEM_INPUT_START:04X}")
            self.log(f"MEM_OUTPUT_START  = 0x{MEM_OUTPUT_START:04X}")
            self.log("=" * 50)
            
        except Exception as e:
            self.log(f"[ERROR] Error leyendo registros: {e}")
            messagebox.showerror("Error", f"Error al leer registros: {e}")

    def leer_direccion(self):
        """Lee byte de dirección especificada."""
        if not self.jtag_connected:
            messagebox.showwarning("Error", "Debe conectar JTAG primero")
            return
        
        try:
            direccion_str = self.entry_dir.get()
            direccion = int(direccion_str, 16) if direccion_str.startswith("0x") else int(direccion_str)
            
            valor = self.controlador.read_byte_from_address(direccion)
            
            self.log(f"[MEM READ] Addr 0x{direccion:04X} = 0x{valor:02X} ({valor})")
            
        except ValueError:
            messagebox.showwarning("Error", "Dirección no válida")
        except Exception as e:
            self.log(f"[ERROR] Error leyendo memoria: {e}")
            messagebox.showerror("Error", f"Error al leer: {e}")

    def insertar_dato(self):
        """Escribe byte a dirección especificada."""
        if not self.jtag_connected:
            messagebox.showwarning("Error", "Debe conectar JTAG primero")
            return
        
        try:
            direccion_str = self.entry_dir.get()
            direccion = int(direccion_str, 16) if direccion_str.startswith("0x") else int(direccion_str)
            
            dato_str = self.entry_dato.get()
            dato = int(dato_str, 16) if dato_str.startswith("0x") else int(dato_str)
            
            self.controlador.write_byte_to_address(direccion, dato)
            
            self.log(f"[MEM WRITE] Addr 0x{direccion:04X} <- 0x{dato:02X} ({dato})")
            
        except ValueError:
            messagebox.showwarning("Error", "Valores no válidos")
        except Exception as e:
            self.log(f"[ERROR] Error escribiendo memoria: {e}")
            messagebox.showerror("Error", f"Error al escribir: {e}")

    def convertir_a_pgm(self, imagen_path, destino_path):
        """Convierte cualquier imagen a PGM 8-bit gris usando Pillow."""
        try:
            img = Image.open(imagen_path).convert('L')
            np_img = np.array(img, dtype=np.uint8)
            with open(destino_path, 'wb') as f:
                # Header PGM P5 (binary grayscale)
                f.write(f"P5\n{np_img.shape[1]} {np_img.shape[0]}\n255\n".encode())
                f.write(np_img.tobytes())
            self.log(f"[PGM] Imagen convertida a: {destino_path}")
            return True
        except Exception as e:
            self.log(f"[ERROR] Error convirtiendo a PGM: {e}")
            return False

    def guardar_resultado_fpga_como_pgm(self, pixel_data, width, height, output_path):
        """
        Guarda resultado de FPGA como imagen PGM.
        
        Args:
            pixel_data: Lista de píxeles (bytes 0-255)
            width: Ancho de imagen
            height: Alto de imagen
            output_path: Ruta donde guardar PGM
        
        Returns:
            True si se guardó correctamente, False en caso contrario
        """
        try:
            # Crear directorio images si no existe
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            
            # Convertir lista a numpy array
            np_img = np.array(pixel_data, dtype=np.uint8)
            
            # Verificar dimensiones
            if len(np_img) != width * height:
                self.log(f"[ERROR] Dimensiones inconsistentes: {len(np_img)} píxeles != {width}x{height}")
                return False
            
            # Reshape a matriz 2D
            np_img = np_img.reshape((height, width))
            
            # Escribir archivo PGM P5 (formato binario)
            with open(output_path, 'wb') as f:
                # Header: magic number, dimensiones, max value
                f.write(f"P5\n{width} {height}\n255\n".encode())
                # Datos binarios
                f.write(np_img.tobytes())
            
            self.log(f"[PGM] Resultado FPGA guardado: {output_path} ({width}x{height})")
            return True
            
        except Exception as e:
            self.log(f"[ERROR] Error guardando PGM del resultado FPGA: {e}")
            return False

    def correr_modelo_referencia(self, escala):
        """
        Ejecuta el binario de referencia sobre la imagen seleccionada y lee el resultado.
        
        Args:
            escala: Factor de escala (float, ej: 0.5, 0.75)
        
        Returns:
            Lista de píxeles de la imagen escalada o lista vacía si falla
        """
        # Crear directorio images si no existe
        if not os.path.exists("images"):
            os.makedirs("images")

        # Usar número arbitrario para la imagen (99)
        input_pgm_path = "images/99.pgm"

        # Convertir/copiar la imagen seleccionada a formato PGM
        if self.imagen_actual.lower().endswith('.pgm'):
            # Copia directa
            import shutil
            shutil.copy2(self.imagen_actual, input_pgm_path)
            self.log(f"[REF] Copiada imagen PGM: {input_pgm_path}")
        else:
            # Convertir a PGM
            if not self.convertir_a_pgm(self.imagen_actual, input_pgm_path):
                return []

        # Calcular nombre de archivo de salida (sin padding, igual que C++)
        escala_int = int(escala * 100)
        salida_pgm_path = f"images/99_output_{escala_int}.pgm"

        # Ruta al binario del modelo de referencia
        bin_path = os.path.join("..", "reference_model", "bin", "bilinear_interpolator.exe")
        
        if not os.path.exists(bin_path):
            self.log(f"[ERROR] No se encontró el binario: {bin_path}")
            self.log(f"[HINT] Compilar modelo de referencia: cd reference_model; .\\build.ps1 all")
            return []

        # Ejecutar modelo C++ bin/bilinear_interpolator.exe 99 <escala>
        cmd = [bin_path, "99", str(escala)]
        self.log(f"[REF] Ejecutando: {' '.join(cmd)}")
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True, cwd=".")
            self.log("[REF] Modelo de referencia ejecutado correctamente.")
            
            # Verificar que se generó el archivo de salida
            if not os.path.exists(salida_pgm_path):
                self.log(f"[ERROR] No se encontró resultado: {salida_pgm_path}")
                return []
            
            # Leer archivo PGM de salida
            with open(salida_pgm_path, "rb") as f:
                # Leer header PGM
                magic = f.readline().strip()
                if magic != b'P5':
                    self.log(f"[ERROR] Formato PGM inválido en {salida_pgm_path} (magic={magic})")
                    return []
                
                # Leer dimensiones (ignorar comentarios)
                dim_line = b''
                while True:
                    dim_line = f.readline()
                    if not dim_line.startswith(b'#'):
                        break
                
                width, height = [int(x) for x in dim_line.strip().split()]
                maxval = int(f.readline().strip())
                
                # Leer datos binarios de píxeles
                raw = f.read()
                pixel_data = np.frombuffer(raw, dtype=np.uint8)
                
                if len(pixel_data) != width * height:
                    self.log(f"[ERROR] Cantidad de datos no coincide: esperado {width*height}, obtenido {len(pixel_data)}")
                    return []
                
                self.log(f"[REF] Salida leída correctamente: {salida_pgm_path} ({width}x{height})")
                return pixel_data.tolist()
                
        except subprocess.CalledProcessError as e:
            self.log(f"[ERROR] Error ejecutando modelo de referencia: {e}")
            self.log(f"[ERROR] Stdout: {e.stdout}")
            self.log(f"[ERROR] Stderr: {e.stderr}")
            return []
        except Exception as e:
            self.log(f"[ERROR] Error procesando modelo de referencia: {e}")
            return []

    def validar_pixel_a_pixel(self):
        """Valida resultado de FPGA contra modelo de referencia C++."""
        if not self.imagen_actual:
            messagebox.showwarning("Advertencia", "Primero selecciona una imagen.")
            return
        
        if not self.ultimo_resultado_fpga:
            messagebox.showwarning("Advertencia", "Primero procesa la imagen en FPGA.")
            return

        self.log("\n" + "="*60)
        self.log("[VALIDACIÓN] Comparando FPGA vs Modelo de Referencia C++")
        self.log("="*60)
        
        # Ejecutar modelo de referencia
        escala = self.escala_actual
        self.log(f"[VALIDACIÓN] Escala: {escala}")
        resultado_ref = self.correr_modelo_referencia(escala)
        resultado_fpga = self.ultimo_resultado_fpga

        if not resultado_ref:
            self.log("[ERROR] No se obtuvo resultado del modelo de referencia.")
            messagebox.showerror("Error", "No se pudo ejecutar el modelo de referencia")
            return

        # Comparar longitudes
        self.log(f"[VALIDACIÓN] Píxeles FPGA: {len(resultado_fpga)}")
        self.log(f"[VALIDACIÓN] Píxeles Referencia: {len(resultado_ref)}")
        
        if len(resultado_fpga) != len(resultado_ref):
            self.log(f"[WARNING] Cantidad de píxeles diferente: FPGA={len(resultado_fpga)}, REF={len(resultado_ref)}")
        
        min_len = min(len(resultado_ref), len(resultado_fpga))
        errores = 0
        detalles_error = []
        max_diff = 0

        # Comparar pixel a pixel
        for i in range(min_len):
            diff = abs(resultado_ref[i] - resultado_fpga[i])
            if diff > 0:
                errores += 1
                max_diff = max(max_diff, diff)
                if errores <= 10:
                    detalles_error.append(
                        f"Pixel {i}: REF={resultado_ref[i]}, FPGA={resultado_fpga[i]}, DIFF={diff}"
                    )

        # Mostrar resultados
        self.log(f"\n[VALIDACIÓN] Resultados:")
        self.log(f"  Píxeles comparados: {min_len}")
        self.log(f"  Píxeles correctos: {min_len - errores}")
        self.log(f"  Píxeles con error: {errores}")
        
        if errores > 0:
            self.log(f"  Diferencia máxima: {max_diff}")
            self.log(f"  Tasa de error: {(errores/min_len)*100:.2f}%")
            self.log(f"\n[VALIDACIÓN] Primeros errores:")
            for detalle in detalles_error:
                self.log(f"  {detalle}")
            if errores > 10:
                self.log(f"  ... y {errores - 10} errores más.")
        else:
            self.log(f"  ✅ ¡Todos los píxeles coinciden correctamente!")
            messagebox.showinfo("Éxito", "Validación completa: Todos los píxeles coinciden")
        
        self.log("="*60 + "\n")


if __name__ == "__main__":
    root = tk.Tk()
    app = InterfazSerial(root)
    root.mainloop()
