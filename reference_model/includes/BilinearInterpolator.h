#ifndef BILINEAR_INTERPOLATOR_H
#define BILINEAR_INTERPOLATOR_H

#include "FixedPoint.h"
#include "MemoryBank.h"
#include "Registers.h"
#include <cstdint>

class BilinearInterpolator {
private:
    ConfigRegisters& config;
    StatusRegisters& status;
    PerformanceCounters& perfCounters;
    
public:
    BilinearInterpolator(ConfigRegisters& cfg, StatusRegisters& stat, PerformanceCounters& perf)
        : config(cfg), status(stat), perfCounters(perf) {}
    
    FixedPoint interpolatePixel(const MemoryBank& memory, float x, float y, bool verbose = false);
    
    void processSequential(const MemoryBank& inputMemory, std::vector<uint8_t>& outputPixels,
                          uint32_t outputWidth, uint32_t outputHeight);
};

#endif
