from PIL import Image
import numpy as np
import time
from constantes import (
    REG_CONFIG, REG_PIXELS, REG_CMD, REG_STATE, REG_RESULT,
    CMD_START, STATE_DONE
)

class SerialController:
    def __init__(self):
        pass

    def cargar_imagen_grises(self, ruta_imagen, ruta_salida_grises=None, ruta_salida_txt=None):
        imagen = Image.open(ruta_imagen).convert('L')
        pixels = np.array(imagen, dtype=int)
        print(f"Shape de la imagen en grises: {pixels.shape}")

        if ruta_salida_grises:
            imagen.save(ruta_salida_grises)
            print(f"Imagen en grises guardada en: {ruta_salida_grises}")

        if ruta_salida_txt:
            with open(ruta_salida_txt, 'w') as f:
                for valor in pixels.flatten():
                    f.write(f"{valor}\n")
            print(f"Valores de los píxeles guardados en: {ruta_salida_txt}")

        return pixels.flatten().tolist(), pixels.shape  

    def send(self, direccion, datos):
        print(f"[DUMMY SEND] Dirección: {direccion}, Datos: (mostrando hasta 10): {datos[:10]}..." if isinstance(datos, list) and len(datos) > 10 else f"[DUMMY SEND] Dirección: {direccion}, Datos: {datos}")

    def receive(self, direccion):
        print(f"[DUMMY RECEIVE] Dirección: {direccion}")
        if direccion == REG_STATE:
            return STATE_DONE
        elif direccion == REG_RESULT:
            # Supón que la FPGA retorna un pixel reescalado. Aquí solo un dummy ejemplo
            return [128] * 10  # Ajusta según tu caso
        else:
            return 123

    def procesar_imagen_fpga(self, ruta_imagen, ruta_out_gris=None, ruta_out_txt=None):
        # 1. Cargar imagen y preparar datos
        pixeles, shape = self.cargar_imagen_grises(ruta_imagen, ruta_out_gris, ruta_out_txt)
        alto, ancho = shape

        # 2. Enviar configuración
        self.send(REG_CONFIG, [ancho, alto])

        # 3. Enviar los datos de los pixeles (se podría hacer en bloques)
        self.send(REG_PIXELS, pixeles)

        # 4. Iniciar procesamiento
        self.send(REG_CMD, [CMD_START])

        # 5. Esperar a que la FPGA termine
        print("Esperando a que la FPGA termine...")
        while True:
            estado = self.receive(REG_STATE)
            if estado == STATE_DONE:
                print("Procesamiento terminado.")
                break
            time.sleep(0.1)

        # 6. Recibir datos procesados (dummy)
        datos_resultado = self.receive(REG_RESULT)
        print("Datos recibidos de FPGA (dummy):", datos_resultado)
        return datos_resultado

# Ejemplo de uso
if __name__ == "__main__":
    controlador = SerialController()
    ruta_imagen = "images/Super-GT.jpg"
    ruta_grises = "images/grises.png"
    ruta_txt = "grayscale/pixeles_grises.txt"
    
    controlador.procesar_imagen_fpga(ruta_imagen, ruta_grises, ruta_txt)