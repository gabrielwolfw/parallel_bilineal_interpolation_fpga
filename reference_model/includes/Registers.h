#ifndef REGISTERS_H
#define REGISTERS_H

#include <cstdint>

class ConfigRegisters {
private:
    uint32_t inputWidth;
    uint32_t inputHeight;
    uint16_t scaleFactor;

public:
    ConfigRegisters() : inputWidth(0), inputHeight(0), scaleFactor(0) {}
    
    void setImageSize(uint32_t width, uint32_t height) {
        inputWidth = width;
        inputHeight = height;
    }
    
    void setScaleFactor(float scale) {
        scaleFactor = static_cast<uint16_t>(scale * 256);
    }
    
    uint32_t getInputWidth() const { return inputWidth; }
    uint32_t getInputHeight() const { return inputHeight; }
    uint16_t getScaleFactorRaw() const { return scaleFactor; }
    float getScaleFactor() const { return scaleFactor / 256.0f; }
};

class StatusRegisters {
private:
    bool busy;
    bool ready;
    uint32_t progress;
    uint32_t errorCode;

public:
    StatusRegisters() : busy(false), ready(true), progress(0), errorCode(0) {}
    
    void setBusy(bool state) { busy = state; ready = !state; }
    void setProgress(uint32_t value) { progress = value; }
    void setError(uint32_t code) { errorCode = code; }
    
    bool isBusy() const { return busy; }
    bool isReady() const { return ready; }
    uint32_t getProgress() const { return progress; }
    uint32_t getErrorCode() const { return errorCode; }
};

class PerformanceCounters {
private:
    uint64_t flops;
    uint64_t memoryReads;
    uint64_t memoryWrites;
    uint64_t cycles;

public:
    PerformanceCounters() : flops(0), memoryReads(0), memoryWrites(0), cycles(0) {}
    
    void reset() {
        flops = 0;
        memoryReads = 0;
        memoryWrites = 0;
        cycles = 0;
    }
    
    void incrementFlops(uint64_t count = 1) { flops += count; }
    void incrementMemoryReads(uint64_t count = 1) { memoryReads += count; }
    void incrementMemoryWrites(uint64_t count = 1) { memoryWrites += count; }
    void incrementCycles(uint64_t count = 1) { cycles += count; }
    
    uint64_t getFlops() const { return flops; }
    uint64_t getMemoryReads() const { return memoryReads; }
    uint64_t getMemoryWrites() const { return memoryWrites; }
    uint64_t getCycles() const { return cycles; }
};

#endif
