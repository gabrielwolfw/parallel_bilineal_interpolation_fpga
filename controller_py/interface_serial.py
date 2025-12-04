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
        self.root.title("Interfaz Serial FPGA")
        self.controlador = SerialController()
        self.imagen_actual = None
        self.ultimo_resultado_fpga = None
        self.escala_actual = 0.75  # Valor por defecto

        # Area de logs (scrollable)
        self.log_display = scrolledtext.ScrolledText(root, height=20, width=80, state='normal')
        self.log_display.grid(row=0, column=0, columnspan=5, pady=10, padx=5)

        # Botones principales
        tk.Button(root, text="Seleccionar imagen", command=self.seleccionar_imagen).grid(row=1, column=0)
        tk.Button(root, text="Procesar imagen", command=self.procesar_imagen).grid(row=1, column=1)
        tk.Button(root, text="Ver registros", command=self.ver_registros).grid(row=1, column=2)
        tk.Button(root, text="Limpiar logs", command=self.limpiar_logs).grid(row=1, column=3)
        tk.Button(root, text="Validar pixel a pixel", command=self.validar_pixel_a_pixel).grid(row=1, column=4)

        # Selección de escala
        tk.Label(root, text="Escala:").grid(row=2, column=0)
        self.entry_escala = tk.Entry(root)
        self.entry_escala.insert(0, "0.75")
        self.entry_escala.grid(row=2, column=1)

        tk.Label(root, text="Dirección:").grid(row=3, column=0)
        self.entry_dir = tk.Entry(root)
        self.entry_dir.grid(row=3, column=1)

        tk.Button(root, text="Leer dirección", command=self.leer_direccion).grid(row=3, column=2)
        tk.Button(root, text="Insertar dato", command=self.insertar_dato).grid(row=3, column=3)

        tk.Label(root, text="Dato (insertar):").grid(row=4, column=0)
        self.entry_dato = tk.Entry(root)
        self.entry_dato.grid(row=4, column=1)

    def log(self, msg):
        self.log_display.insert(tk.END, str(msg) + '\n')
        self.log_display.see(tk.END)

    def limpiar_logs(self):
        self.log_display.delete('1.0', tk.END)

    def seleccionar_imagen(self):
        archivo = filedialog.askopenfilename(title="Selecciona una imagen", filetypes=[("Imágenes", "*.jpg *.png *.bmp *.pgm")])
        if archivo:
            self.imagen_actual = archivo
            self.log(f"Imagen seleccionada: {archivo}")

    def procesar_imagen(self):
        if not self.imagen_actual:
            messagebox.showwarning("Advertencia", "Primero selecciona una imagen.")
            return
        escala = self.leer_escala()
        ruta_out_gris = "interfaz_grises.png"
        ruta_out_txt = "interfaz_pixeles.txt"
        resultado = self.controlador.procesar_imagen_fpga(self.imagen_actual, ruta_out_gris, ruta_out_txt)
        self.ultimo_resultado_fpga = resultado
        self.escala_actual = escala
        self.log(f"Imagen procesada. Resultado dummy FPGA: {resultado[:10]}...")

    def leer_escala(self):
        try:
            escala = float(self.entry_escala.get())
            if escala < 0.5 or escala > 1.0:
                messagebox.showwarning("Error", "Escala debe estar entre 0.5 y 1.0")
                return 0.75
            return round(escala / 0.05) * 0.05
        except Exception:
            return 0.75

    def ver_registros(self):
        registros = [
            f"REG_CONFIG: {REG_CONFIG}",
            f"REG_PIXELS: {REG_PIXELS}",
            f"REG_CMD: {REG_CMD}",
            f"REG_STATE: {REG_STATE}",
            f"REG_RESULT: {REG_RESULT}"
        ]
        for reg in registros:
            self.log(reg)

    def leer_direccion(self):
        try:
            direccion = int(self.entry_dir.get(), 0)
        except ValueError:
            messagebox.showwarning("Error", "Dirección no válida.")
            return
        valor = self.controlador.receive(direccion)
        self.log(f"Lectura dirección {direccion}: {valor}")

    def insertar_dato(self):
        try:
            direccion = int(self.entry_dir.get(), 0)
            dato = int(self.entry_dato.get())
        except ValueError:
            messagebox.showwarning("Error", "Valores no válidos.")
            return
        self.controlador.send(direccion, [dato])
        self.log(f"Se insertó el dato {dato} en la dirección {direccion}")

    def convertir_a_pgm(self, imagen_path, destino_path):
        """Convierte cualquier imagen a PGM 8-bit gris usando Pillow"""
        img = Image.open(imagen_path).convert('L')
        np_img = np.array(img, dtype=np.uint8)
        with open(destino_path, 'wb') as f:
            # Header
            f.write(f"P5\n{np_img.shape[1]} {np_img.shape[0]}\n255\n".encode())
            f.write(np_img.tobytes())

    def correr_modelo_referencia(self, escala):
        """
        Ejecuta el binario de referencia sobre la imagen seleccionada y lee el resultado como vector de píxeles.
        """
        # Usar número arbitrario para la imagen (99), copiar/covnertir y correr interpolación
        input_pgm_path = "images/99.pgm"
        if not os.path.exists("images"):
            os.makedirs("images")

        # Convertir/copiar la imagen seleccionada a .pgm formato correcto
        if self.imagen_actual.lower().endswith('.pgm'):
            # Copia directa
            import shutil
            shutil.copy2(self.imagen_actual, input_pgm_path)
        else:
            self.convertir_a_pgm(self.imagen_actual, input_pgm_path)

        escala_str = str(int(escala * 100)).zfill(3)
        salida_pgm_path = f"images/99_output_{escala_str}.pgm"

        # Ejecutar modelo C++ bin/bilinear_interpolator
        cmd = [os.path.join("..", "reference_model", "bin", "bilinear_interpolator.exe"), "99", str(escala)]
        try:
            result = subprocess.run(cmd, capture_output=True, check=True)
            self.log("Modelo de referencia ejecutado correctamente.")
            if os.path.exists(salida_pgm_path):
                with open(salida_pgm_path, "rb") as f:
                    # Leer header PGM
                    magic = f.readline().strip()
                    if magic != b'P5':
                        self.log(f"Error: archivo PGM inesperado en {salida_pgm_path}")
                        return []
                    # Ignorar comentarios
                    dim_line = b''
                    while True:
                        dim_line = f.readline()
                        if not dim_line.startswith(b'#'):
                            break
                    width, height = [int(x) for x in dim_line.strip().split()]
                    maxval = int(f.readline().strip())
                    # Leer datos binarios de pixels
                    raw = f.read()
                    pixel_data = np.frombuffer(raw, dtype=np.uint8)
                    if len(pixel_data) != width * height:
                        self.log("Error: cantidad de datos pixel no coincide con dimensiones.")
                        return []
                    self.log(f"Salida correcta: {salida_pgm_path} ({width}x{height})")
                    return pixel_data.tolist()
            else:
                self.log(f"No se encontró resultado: {salida_pgm_path}")
                return []
        except Exception as e:
            self.log(f"Error ejecutando modelo de referencia: {e}")
            return []

    def validar_pixel_a_pixel(self):
        if not self.imagen_actual:
            messagebox.showwarning("Advertencia", "Primero selecciona una imagen.")
            return
        if not self.ultimo_resultado_fpga:
            messagebox.showwarning("Advertencia", "Primero procesa la imagen y ejecuta la FPGA.")
            return

        escala = self.escala_actual
        resultado_ref = self.correr_modelo_referencia(escala)
        resultado_fpga = self.ultimo_resultado_fpga

        if not resultado_ref:
            self.log("No se obtuvo resultado del modelo de referencia.")
            return

        min_len = min(len(resultado_ref), len(resultado_fpga))
        errores = 0
        detalles_error = []

        for i in range(min_len):
            if resultado_ref[i] != resultado_fpga[i]:
                errores += 1
                if errores <= 10:
                    detalles_error.append(f"Pixel {i}: ref={resultado_ref[i]}, fpga={resultado_fpga[i]}")

        self.log(f"Comparación pixel a pixel:")
        self.log(f"Pixels comparados: {min_len}")
        self.log(f"Errores encontrados: {errores}")
        for detalle in detalles_error:
            self.log(detalle)
        if errores > 10:
            self.log(".... y más errores. Muestra sólo los 10 primeros.")
        if errores == 0:
            self.log("¡Todos los píxeles coinciden correctamente!")

if __name__ == "__main__":
    root = tk.Tk()
    app = InterfazSerial(root)
    root.mainloop()