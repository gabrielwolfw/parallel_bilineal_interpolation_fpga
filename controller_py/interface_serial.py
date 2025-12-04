import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext

from serial_controller import SerialController
from constantes import *

class InterfazSerial:
    def __init__(self, root):
        self.root = root
        self.root.title("Interfaz Serial FPGA")
        self.controlador = SerialController()
        self.imagen_actual = None

        # Area de logs (scrollable)
        self.log_display = scrolledtext.ScrolledText(root, height=20, width=80, state='normal')
        self.log_display.grid(row=0, column=0, columnspan=4, pady=10, padx=5)

        # Botones principales
        tk.Button(root, text="Seleccionar imagen", command=self.seleccionar_imagen).grid(row=1, column=0)
        tk.Button(root, text="Procesar imagen", command=self.procesar_imagen).grid(row=1, column=1)
        tk.Button(root, text="Ver registros", command=self.ver_registros).grid(row=1, column=2)
        tk.Button(root, text="Limpiar logs", command=self.limpiar_logs).grid(row=1, column=3)

        # Área para interactuar con direcciones y datos
        tk.Label(root, text="Dirección:").grid(row=2, column=0)
        self.entry_dir = tk.Entry(root)
        self.entry_dir.grid(row=2, column=1)

        tk.Button(root, text="Leer dirección", command=self.leer_direccion).grid(row=2, column=2)
        tk.Button(root, text="Insertar dato", command=self.insertar_dato).grid(row=2, column=3)

        tk.Label(root, text="Dato (insertar):").grid(row=3, column=0)
        self.entry_dato = tk.Entry(root)
        self.entry_dato.grid(row=3, column=1)

    def log(self, msg):
        self.log_display.insert(tk.END, str(msg) + '\n')
        self.log_display.see(tk.END)

    def limpiar_logs(self):
        self.log_display.delete('1.0', tk.END)

    def seleccionar_imagen(self):
        archivo = filedialog.askopenfilename(title="Selecciona una imagen", filetypes=[("Imágenes", "*.jpg *.png *.bmp")])
        if archivo:
            self.imagen_actual = archivo
            self.log(f"Imagen seleccionada: {archivo}")

    def procesar_imagen(self):
        if not self.imagen_actual:
            messagebox.showwarning("Advertencia", "Primero selecciona una imagen.")
            return
        ruta_out_gris = "interfaz_grises.png"
        ruta_out_txt = "interfaz_pixeles.txt"
        resultado = self.controlador.procesar_imagen_fpga(self.imagen_actual, ruta_out_gris, ruta_out_txt)
        self.log(f"Imagen procesada. Resultado dummy: {resultado[:10]}...")

    def ver_registros(self):
        # Esto solo muestra los nombres y sus direcciones (puedes expandirlo con más información si lo conectas a hardware real)
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

if __name__ == "__main__":
    root = tk.Tk()
    app = InterfazSerial(root)
    root.mainloop()