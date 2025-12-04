#ifndef MEMORY_BANK_H
#define MEMORY_BANK_H

#include <vector>
#include <cstdint>

class MemoryBank {
private:
    std::vector<uint8_t> data;
    uint32_t width;
    uint32_t height;

public:
    MemoryBank() : width(0), height(0) {}
    
    void initialize(const std::vector<uint8_t>& pixelData, uint32_t w, uint32_t h) {
        data = pixelData;
        width = w;
        height = h;
    }
    
    uint8_t readPixel(uint32_t x, uint32_t y) const {
        if (x >= width || y >= height) {
            return 0;
        }
        return data[y * width + x];
    }
    
    uint32_t getWidth() const { return width; }
    uint32_t getHeight() const { return height; }
};

#endif
