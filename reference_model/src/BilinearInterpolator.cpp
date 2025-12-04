#include "BilinearInterpolator.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <iomanip>

FixedPoint BilinearInterpolator::interpolatePixel(const MemoryBank& memory, float x, float y, bool verbose) {
    int x0 = static_cast<int>(std::floor(x));
    int y0 = static_cast<int>(std::floor(y));
    int x1 = std::min(x0 + 1, static_cast<int>(memory.getWidth()) - 1);
    int y1 = std::min(y0 + 1, static_cast<int>(memory.getHeight()) - 1);
    
    x0 = std::max(0, std::min(x0, static_cast<int>(memory.getWidth()) - 1));
    y0 = std::max(0, std::min(y0, static_cast<int>(memory.getHeight()) - 1));
    
    perfCounters.incrementMemoryReads(4);
    
    uint8_t p00 = memory.readPixel(x0, y0);
    uint8_t p10 = memory.readPixel(x1, y0);
    uint8_t p01 = memory.readPixel(x0, y1);
    uint8_t p11 = memory.readPixel(x1, y1);
    
    float x_weight_float = x - static_cast<float>(x0);
    float y_weight_float = y - static_cast<float>(y0);
    
    FixedPoint a = FixedPoint::fromFloat(x_weight_float);
    FixedPoint b = FixedPoint::fromFloat(y_weight_float);
    
    FixedPoint one_fixed = FixedPoint::fromInt(1);
    
    perfCounters.incrementFlops(2);
    
    int32_t w00 = ((one_fixed - a).getRaw() * (one_fixed - b).getRaw()) >> 8;
    int32_t w10 = (a.getRaw() * (one_fixed - b).getRaw()) >> 8;
    int32_t w01 = ((one_fixed - a).getRaw() * b.getRaw()) >> 8;
    int32_t w11 = (a.getRaw() * b.getRaw()) >> 8;
    
    perfCounters.incrementFlops(4);
    
    int32_t interp_sum = ((p00 * w00) + (p10 * w10) + (p01 * w01) + (p11 * w11)) >> 8;
    
    perfCounters.incrementFlops(7);
    
    if (verbose) {
        std::cout << std::fixed << std::setprecision(4);
        std::cout << "\n--- Interpolación en (" << x << ", " << y << ") ---" << std::endl;
        std::cout << "Coordenadas vecinas: (" << x0 << "," << y0 << "), (" << x1 << "," << y0 
                  << "), (" << x0 << "," << y1 << "), (" << x1 << "," << y1 << ")" << std::endl;
        std::cout << "Píxeles vecinos: p00=" << (int)p00 << ", p10=" << (int)p10 
                  << ", p01=" << (int)p01 << ", p11=" << (int)p11 << std::endl;
        std::cout << "Pesos fraccionales: a=" << x_weight_float << " (" << a.getRaw() << " en Q8.8)"
                  << ", b=" << y_weight_float << " (" << b.getRaw() << " en Q8.8)" << std::endl;
        std::cout << "Pesos Q8.8: w00=" << w00 << ", w10=" << w10 << ", w01=" << w01 << ", w11=" << w11 << std::endl;
        std::cout << "Suma ponderada: (" << (int)p00 << "*" << w00 << " + " << (int)p10 << "*" << w10 
                  << " + " << (int)p01 << "*" << w01 << " + " << (int)p11 << "*" << w11 << ") >> 8" << std::endl;
        std::cout << "              = " << ((p00 * w00) + (p10 * w10) + (p01 * w01) + (p11 * w11)) 
                  << " >> 8 = " << interp_sum << std::endl;
    }
    
    if (interp_sum > 255) {
        interp_sum = 255;
    } else if (interp_sum < 0) {
        interp_sum = 0;
    }
    
    if (verbose) {
        std::cout << "Resultado final: " << interp_sum << std::endl;
    }
    
    return FixedPoint::fromInt(static_cast<int>(interp_sum));
}

void BilinearInterpolator::processSequential(const MemoryBank& inputMemory,
                                             std::vector<uint8_t>& outputPixels,
                                             uint32_t outputWidth,
                                             uint32_t outputHeight) {
    status.setBusy(true);
    status.setProgress(0);
    perfCounters.reset();
    
    outputPixels.resize(outputWidth * outputHeight);
    
    uint32_t inputWidth = inputMemory.getWidth();
    uint32_t inputHeight = inputMemory.getHeight();
    
    double x_ratio = (outputWidth > 1) 
        ? static_cast<double>(inputWidth - 1) / static_cast<double>(outputWidth - 1)
        : 0.0;
    
    double y_ratio = (outputHeight > 1)
        ? static_cast<double>(inputHeight - 1) / static_cast<double>(outputHeight - 1)
        : 0.0;
    
    uint32_t totalPixels = outputWidth * outputHeight;
    uint32_t interpolationCount = 0;
    
    std::cout << "\n=== Mostrando cálculo de las primeras 5 interpolaciones ===" << std::endl;
    
    for (uint32_t outY = 0; outY < outputHeight; outY++) {
        for (uint32_t outX = 0; outX < outputWidth; outX++) {
            perfCounters.incrementCycles(1);
            
            float src_x = static_cast<float>(x_ratio * static_cast<double>(outX));
            float src_y = static_cast<float>(y_ratio * static_cast<double>(outY));
            
            perfCounters.incrementFlops(2);
            
            bool verbose = (interpolationCount%1000?false:true);
            FixedPoint interpolatedValue = interpolatePixel(inputMemory, src_x, src_y, verbose);
            interpolationCount++;
            
            int pixelValue = interpolatedValue.toInt();
            
            outputPixels[outY * outputWidth + outX] = static_cast<uint8_t>(pixelValue);
            perfCounters.incrementMemoryWrites(1);
            
            uint32_t currentPixel = outY * outputWidth + outX + 1;
            if (currentPixel % (totalPixels / 100 + 1) == 0) {
                status.setProgress((currentPixel * 100) / totalPixels);
            }
        }
    }
    
    std::cout << "\n=== Fin de ejemplos de interpolación ===" << std::endl;
    
    status.setProgress(100);
    status.setBusy(false);
}
