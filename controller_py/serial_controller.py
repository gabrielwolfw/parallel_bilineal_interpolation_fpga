from PIL import Image
import numpy as np

class SerialController:
    def __init__(self):
        pass

    def cargar_imagen_grises(self, ruta_imagen, ruta_salida_grises=None, ruta_salida_txt=None):
        """
        Carga la imagen indicada, la convierte en escala de grises y
        devuelve una lista de enteros correspondientes al valor de cada pixel.
        También guarda la imagen resultante en escala de grises y los valores en un archivo txt.
        """
        imagen = Image.open(ruta_imagen).convert('L')  # 'L' es para escala de grises
        pixels = np.array(imagen, dtype=int)
        print(f"Shape de la imagen en grises: {pixels.shape}")

        # Guardar la imagen en escala de grises
        if ruta_salida_grises:
            imagen.save(ruta_salida_grises)
            print(f"Imagen en grises guardada en: {ruta_salida_grises}")

        # Guardar los enteros en archivo txt
        if ruta_salida_txt:
            with open(ruta_salida_txt, 'w') as f:
                for valor in pixels.flatten():
                    f.write(f"{valor}\n")
            print(f"Valores de los píxeles guardados en: {ruta_salida_txt}")

        return pixels.flatten().tolist()

    def send(self, direccion, datos):
        """
        Método dummy para enviar datos a una dirección específica.
        Imprime lo que enviaría.
        """
        print(f"[DUMMY SEND] Dirección: {direccion}, Datos: {datos}")

    def receive(self, direccion):
        """
        Método dummy para recibir datos de una dirección específica.
        Imprime la dirección y retorna un valor dummy.
        """
        print(f"[DUMMY RECEIVE] Dirección: {direccion}")
        return 123  # Valor dummy

# Ejemplo de uso
if __name__ == "__main__":
    controlador = SerialController()
    ruta_imagen = "images/Super-GT.jpg"
    ruta_grises = "images/grises.png"
    ruta_txt = "grayscale/pixeles_grises.txt"
    pixeles = controlador.cargar_imagen_grises(ruta_imagen, ruta_grises, ruta_txt)
    print("Primeros 10 pixeles:", pixeles[:10])
    controlador.send(0x10, pixeles[:5])  # cambiar de "pixeles[:5] a pixeles" para imprimir todo los valores
    recibido = controlador.receive(0x10)
    print("Dato recibido (dummy):", recibido)