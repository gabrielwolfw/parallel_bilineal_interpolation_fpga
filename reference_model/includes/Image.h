#ifndef IMAGE_H
#define IMAGE_H

#include <vector>
#include <cstdint>
#include <string>

class Image {
private:
    std::vector<uint8_t> pixels;
    uint32_t width;
    uint32_t height;

public:
    Image();
    Image(uint32_t w, uint32_t h);
    
    bool load(const std::string& filename);
    bool save(const std::string& filename) const;
    
    uint32_t getWidth() const { return width; }
    uint32_t getHeight() const { return height; }
    
    uint8_t getPixel(uint32_t x, uint32_t y) const;
    void setPixel(uint32_t x, uint32_t y, uint8_t value);
    
    const std::vector<uint8_t>& getPixelData() const { return pixels; }
    std::vector<uint8_t>& getPixelData() { return pixels; }
};

#endif
