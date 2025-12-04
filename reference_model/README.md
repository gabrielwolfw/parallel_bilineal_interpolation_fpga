# Interpolación Bilineal con Punto Fijo Q8.8

Modelo de referencia en C++ para validación de un acelerador DSA (Domain-Specific Architecture) de interpolación bilineal en FPGA.

## Descripción

Este proyecto implementa la **interpolación bilineal** para downscaling de imágenes en escala de grises utilizando **aritmética de punto fijo Q8.8**. El algoritmo está diseñado para ser bit a bit idéntico a la implementación en hardware FPGA.

### Características Principales

- **Formato numérico**: Q8.8 (8 bits entero, 8 bits fracción) solo para coeficientes de interpolación
- **Coordenadas**: Punto flotante para mapeo preciso de píxeles
- **Píxeles**: Enteros sin signo de 8 bits (0-255)
- **Factor de escala**: 0.5 a 1.0 en pasos de 0.05
- **Imágenes**: PGM (Portable GrayMap) en escala de grises, hasta 512×512 píxeles
- **Modo**: Secuencial (1 píxel por ciclo)
- **Sin dependencias externas**: Solo usa C++ estándar (no requiere libpng)

## Algoritmo de Interpolación Bilineal

```
Para cada píxel (x, y) en la imagen de salida:

1. Calcular coordenadas en imagen de entrada:
   src_x = x * ratio_x
   src_y = y * ratio_y
   
   donde ratio = (input_size - 1) / (output_size - 1)

2. Obtener píxeles vecinos:
   p00 = pixel(floor(src_x), floor(src_y))
   p10 = pixel(ceil(src_x),  floor(src_y))
   p01 = pixel(floor(src_x), ceil(src_y))
   p11 = pixel(ceil(src_x),  ceil(src_y))

3. Calcular pesos en Q8.8:
   a = fracción(src_x)  // Convertir a Q8.8
   b = fracción(src_y)  // Convertir a Q8.8
   
   w00 = (1-a) * (1-b)  // Q8.8 * Q8.8 >> 8
   w10 = a * (1-b)
   w01 = (1-a) * b
   w11 = a * b

4. Interpolación:
   resultado = (p00*w00 + p10*w10 + p01*w01 + p11*w11) >> 8
   
5. Saturar a 0-255
```

## Estructura del Proyecto

```
.
├── src/                          # Código fuente
│   ├── main.cpp                  # Programa principal
│   ├── Image.cpp                 # Manejo de imágenes PGM
│   └── BilinearInterpolator.cpp  # Algoritmo de interpolación Q8.8
├── includes/                     # Headers
│   ├── FixedPoint.h              # Aritmética Q8.8
│   ├── Image.h                   # Clase de imagen
│   ├── MemoryBank.h              # Banco de memoria (simula FPGA)
│   ├── Registers.h               # Registros de control y estado
│   └── BilinearInterpolator.h    # Interpolador
├── images/                       # Imágenes de prueba (PGM format)
├── scripts/                      # Scripts auxiliares
│   └── generate_test_images.py   # Genera imágenes de prueba
├── bin/                          # Ejecutables (generado)
├── build.ps1                     # Script de compilación PowerShell (Windows)
├── Makefile                      # Sistema de compilación (Linux/macOS)
├── Makefile.win                  # Makefile para Windows/MinGW
└── README.md                     # Este archivo
```

## Requisitos

### Windows (Recomendado para este proyecto)
- **Compilador**: MinGW/MSYS2 con g++ (C++17)
- **Python**: Python 3.x con numpy y Pillow
- **Sin librerías externas**: El proyecto usa formato PGM (no requiere libpng)

### Linux/macOS
- **Compilador**: g++ con soporte C++17
- **Python**: Python 3 con numpy y Pillow

### Instalación de dependencias

**Windows (MSYS2)**:
```powershell
# En MSYS2 MinGW64 terminal:
pacman -S mingw-w64-x86_64-gcc

# Python (si no está instalado):
# Descargar desde python.org
pip install numpy Pillow
```

**Ubuntu/Debian**:
```bash
sudo apt-get install g++ python3 python3-pip
pip3 install numpy Pillow
```

**macOS**:
```bash
brew install gcc python3
pip3 install numpy Pillow
```
pip3 install Pillow numpy
```

## Compilación y Uso

### Windows (PowerShell - Recomendado)

#### 1. Generar imágenes de prueba
```powershell
.\build.ps1 generate-test-images
```

Esto crea 4 imágenes PGM en escala de grises:
- `01.pgm` - Gradiente horizontal (256×256)
- `02.pgm` - Patrón de tablero (320×320)  
- `03.pgm` - Círculo con degradado radial (400×400)
- `04.pgm` - Texto "FPGA" (512×512)

#### 2. Compilar el proyecto
```powershell
.\build.ps1 all
```

#### 3. Ejecutar con ejemplo por defecto
```powershell
.\build.ps1 run
```

Procesa `images/01.pgm` con factor de escala 0.75.

#### 4. Ejecutar manualmente
```powershell
.\bin\bilinear_interpolator.exe <número_imagen> [factor_escala]
```

**Ejemplos:**
```powershell
.\bin\bilinear_interpolator.exe 01 0.75
.\bin\bilinear_interpolator.exe 02 0.50
.\bin\bilinear_interpolator.exe 03 0.90
```

#### 5. Probar todos los factores de escala
```powershell
.\build.ps1 test
```

Ejecuta el interpolador con factores de 0.50, 0.55, 0.60, ... 1.00.

#### 6. Limpiar archivos generados
```powershell
.\build.ps1 clean
```

### Linux/macOS (Makefile)

#### 1. Generar imágenes de prueba

```bash
make generate-test-images
```

Esto crea 4 imágenes en escala de grises:
- `01.png` - Gradiente horizontal (256×256)
- `02.png` - Patrón de tablero (320×320)  
- `03.png` - Círculo con degradado radial (400×400)
- `04.png` - Texto "FPGA" (512×512)

#### 2. Compilar el proyecto

```bash
make all
```

#### 3. Ejecutar con ejemplo por defecto

```bash
make run
```

Procesa `images/01.png` con factor de escala 0.75.

#### 4. Ejecutar manualmente

```bash
./bin/bilinear_interpolator <número_imagen> [factor_escala]
```

**Ejemplos:**
```bash
./bin/bilinear_interpolator 01 0.75
./bin/bilinear_interpolator 02 0.50
./bin/bilinear_interpolator 03 0.90
```

#### 5. Probar todos los factores de escala

```bash
make test
```

Ejecuta el interpolador con factores de 0.50, 0.55, 0.60, ... 1.00.

#### 6. Limpiar archivos generados

```bash
make clean      # Elimina objetos y salidas
make distclean  # Limpieza completa
```

## Salida del Programa

```
Processing image: images/01.pgm
Scale factor: 0.75

=== Mostrando cálculo de las primeras 5 interpolaciones ===

--- Interpolación en (0.0000, 0.0000) ---
Coordenadas vecinas: (0,0), (1,0), (0,1), (1,1)
Píxeles vecinos: p00=0, p10=0, p01=0, p11=0
Pesos fraccionales: a=0.0000 (0 en Q8.8), b=0.0000 (0 en Q8.8)
Pesos Q8.8: w00=256, w10=0, w01=0, w11=0
Suma ponderada: (0*256 + 0*0 + 0*0 + 0*0) >> 8 = 0
Resultado final: 0

...

=== Image Processing Statistics ===
Input size:       256x256
Output size:      192x192
Scale factor:     0.75

=== Performance Counters ===
Cycles:           36864
FLOPs:            552960
Memory reads:     147456
Memory writes:    36864
===================================

Output saved to: images/01_output_75.pgm
```

## Formato de Imágenes: PGM (Portable GrayMap)

El proyecto usa **formato PGM** en lugar de PNG por simplicidad y para evitar dependencias externas.

### ¿Qué es PGM?

PGM es un formato de imagen simple, legible en texto plano, diseñado específicamente para imágenes en escala de grises.

**Ejemplo de archivo PGM (ASCII - P2)**:
```
P2
# Comentario
256 256
255
0 1 2 3 4 ...
```

**Formato binario (P5)** - usado por este proyecto:
```
P5
256 256
255
<datos binarios>
```

### Ventajas de PGM

- ✅ **Sin dependencias**: No requiere libpng ni otras bibliotecas
- ✅ **Simple de implementar**: Solo `<fstream>` y `<sstream>`
- ✅ **Fácil de depurar**: Formato de texto plano legible (P2)
- ✅ **Perfecto para grayscale**: Diseñado específicamente para 8-bit grayscale
- ✅ **Amplio soporte**: GIMP, ImageMagick, Python/Pillow

### Ver archivos PGM

**GIMP**: Abre PGM nativamente  
**ImageMagick**: `magick images/01.pgm images/01.png`  
**Python**:
```python
from PIL import Image
img = Image.open('images/01.pgm')
img.show()
```

**Conversión masiva a PNG**:
```powershell
# PowerShell
Get-ChildItem images\*.pgm | ForEach-Object { 
    magick $_.FullName ($_.FullName -replace '.pgm','.png')
}
```

## Formato de Punto Fijo Q8.8

El sistema usa aritmética Q8.8 **solo para los coeficientes de interpolación**:

- **Total**: 16 bits
- **Entero**: 8 bits (rango: -128 a 127)
- **Fracción**: 8 bits (precisión: 1/256 ≈ 0.0039)

**Ventajas:**
- Precisión controlada sin punto flotante
- Compatible con bloques DSP de FPGA
- Resultados reproducibles bit a bit
- Operaciones eficientes con shift

**Ejemplo de operación Q8.8:**
```cpp
// Convertir 0.75 a Q8.8
FixedPoint fp = FixedPoint::fromFloat(0.75f);
// Internamente: 0.75 * 256 = 192 (0x00C0)

// Multiplicación Q8.8
FixedPoint a = FixedPoint::fromFloat(0.5f);  // 128
FixedPoint b = FixedPoint::fromFloat(0.25f); // 64
FixedPoint c = a * b;  // (128 * 64) >> 8 = 32 = 0.125
```

## Registros del Sistema

### Registros de Configuración
- Tamaño de imagen de entrada (ancho y alto)
- Factor de escala (0.5 - 1.0)

### Registros de Estado
- `busy/ready`: Estado del procesador
- `progress`: Progreso 0-100%
- `errors`: Código de error

### Contadores de Rendimiento
- `FLOPs`: Operaciones de punto fijo
- `Memory reads`: Lecturas de píxeles
- `Memory writes`: Escrituras de píxeles
- `Cycles`: Ciclos de procesamiento

## Validación con FPGA

Este código C++ replica **exactamente** el comportamiento del módulo FPGA:

1. **Mismo formato numérico**: Q8.8 para coeficientes
2. **Misma secuencia de operaciones**: Cálculo de pesos, suma ponderada
3. **Mismo manejo de saturación**: Clamp a 0-255
4. **Resultados bit a bit idénticos**

Para validar:
1. Ejecutar el modelo C++ con una imagen y factor de escala
2. Ejecutar el FPGA con la misma imagen y factor
3. Comparar las salidas bit a bit

## Principios de Diseño (SOLID)

El código sigue principios de diseño limpio:

- **Single Responsibility**: Cada clase tiene una responsabilidad única
- **Open/Closed**: Extensible sin modificar código existente
- **Liskov Substitution**: Jerarquías consistentes
- **Interface Segregation**: Interfaces cohesivas
- **Dependency Inversion**: Dependencias mediante abstracciones

## Autor

Proyecto para el curso de Arquitectura de Computadores 2  
Tecnológico de Costa Rica
