# README para compilación en Windows

## Problema actual: Dependencia de libpng

El modelo de referencia actual requiere `libpng` para leer/escribir imágenes PNG. En Windows con MSYS2, necesitas:

### Opción 1: Instalar libpng en MSYS2 (Recomendado)

```powershell
# Abrir MSYS2 MinGW64 shell
# Actualizar el sistema (puede requerir reiniciar la terminal)
pacman -Syu

# Después de reiniciar, instalar libpng
pacman -S mingw-w64-x86_64-libpng

# Compilar el proyecto
cd reference_model
./build.ps1 generate-test-images
./build.ps1 all
./build.ps1 run
```

### Opción 2: Usar pre-compilados de libpng

1. Descargar libpng pre-compilado para MinGW desde: https://packages.msys2.org/package/mingw-w64-x86_64-libpng
2. Extraer en `C:\msys64\mingw64\`
3. Compilar normalmente

### Opción 3: Usar stb_image (alternativa sin dependencias externas)

Si los métodos anteriores fallan, puedo modificar el código para usar `stb_image.h` y `stb_image_write.h` (header-only libraries) que no requieren instalación de librerías externas.

## Estado actual del proyecto

✅ **Generación de imágenes de prueba funciona**:
- 4 imágenes PNG de prueba generadas correctamente (256x256 a 512x512)
- Gradiente, tablero, círculo degradado, texto "FPGA"

❌ **Compilación pendiente**:
- Requiere libpng instalado en MSYS2
- Error actual: `fatal error: png.h: No such file or directory`

## Archivos creados para Windows

1. **Makefile.win** - Makefile adaptado para Windows/MinGW
   - Usa comandos Windows (mkdir, del, rmdir)
   - Compatible con mingw32-make

2. **build.ps1** - Script de compilación PowerShell
   - No requiere make
   - Compilación directa con g++
   - Comandos: all, run, test, generate-test-images, clean

3. **scripts/generate_test_images.py** (modificado)
   - Rutas de fuentes Windows (C:/Windows/Fonts/arial.ttf)
   - Compatible con Linux/Mac/Windows

## Próximos pasos

1. Resolver instalación de libpng en MSYS2
2. Compilar el proyecto
3. Probar con imágenes generadas
4. Validar que la interpolación Q8.8 funciona correctamente

## Alternativa: stb_image

Si prefieres evitar dependencias externas, puedo modificar `Image.cpp` para usar stb_image:

```cpp
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
```

Esto eliminaría completamente la dependencia de libpng.
