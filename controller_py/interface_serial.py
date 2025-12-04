import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext

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
        tk.Button(frame_botones, text="Limpiar logs", command=self.limpiar_logs, width=18).grid(row=0, column=3, padx=5)

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
            
            ruta_out_gris = "interfaz_grises.png"
            ruta_out_txt = "interfaz_pixeles.txt"
            resultado = self.controlador.procesar_imagen_fpga(
                self.imagen_actual, 
                ruta_out_gris, 
                ruta_out_txt
            )
            
            self.log(f"[SUCCESS] Procesamiento completado. Píxeles de salida: {len(resultado)}")
            
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


if __name__ == "__main__":
    root = tk.Tk()
    app = InterfazSerial(root)
    root.mainloop()
