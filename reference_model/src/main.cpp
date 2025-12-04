#include "Image.h"
#include "MemoryBank.h"
#include "BilinearInterpolator.h"
#include "Registers.h"
#include <iostream>
#include <iomanip>
#include <string>
#include <cmath>

class ImageProcessor {
private:
    ConfigRegisters config;
    StatusRegisters status;
    PerformanceCounters perfCounters;
    BilinearInterpolator interpolator;

public:
    ImageProcessor() : interpolator(config, status, perfCounters) {}
    
    bool processImage(const std::string& inputPath, const std::string& outputPath, float scaleFactor) {
        if (scaleFactor < 0.5f || scaleFactor > 1.0f) {
            std::cerr << "Error: Scale factor must be between 0.5 and 1.0" << std::endl;
            return false;
        }
        
        Image inputImage;
        if (!inputImage.load(inputPath)) {
            std::cerr << "Error: Failed to load image: " << inputPath << std::endl;
            return false;
        }
        
        uint32_t inputWidth = inputImage.getWidth();
        uint32_t inputHeight = inputImage.getHeight();
        
        if (inputWidth > 512 || inputHeight > 512) {
            std::cerr << "Error: Image dimensions exceed 512x512 maximum" << std::endl;
            return false;
        }
        
        config.setImageSize(inputWidth, inputHeight);
        config.setScaleFactor(scaleFactor);
        
        MemoryBank memory;
        memory.initialize(inputImage.getPixelData(), inputWidth, inputHeight);
        
        uint32_t outputWidth = static_cast<uint32_t>(std::round(inputWidth * scaleFactor));
        uint32_t outputHeight = static_cast<uint32_t>(std::round(inputHeight * scaleFactor));
        
        std::vector<uint8_t> outputPixels;
        interpolator.processSequential(memory, outputPixels, outputWidth, outputHeight);
        
        Image outputImage(outputWidth, outputHeight);
        outputImage.getPixelData() = outputPixels;
        
        if (!outputImage.save(outputPath)) {
            std::cerr << "Error: Failed to save image: " << outputPath << std::endl;
            return false;
        }
        
        printStatistics(inputWidth, inputHeight, outputWidth, outputHeight, scaleFactor);
        
        return true;
    }

private:
    void printStatistics(uint32_t inW, uint32_t inH, uint32_t outW, uint32_t outH, float scale) {
        std::cout << "\n=== Image Processing Statistics ===" << std::endl;
        std::cout << "Input size:       " << inW << "x" << inH << std::endl;
        std::cout << "Output size:      " << outW << "x" << outH << std::endl;
        std::cout << "Scale factor:     " << std::fixed << std::setprecision(2) << scale << std::endl;
        std::cout << "\n=== Performance Counters ===" << std::endl;
        std::cout << "Cycles:           " << perfCounters.getCycles() << std::endl;
        std::cout << "FLOPs:            " << perfCounters.getFlops() << std::endl;
        std::cout << "Memory reads:     " << perfCounters.getMemoryReads() << std::endl;
        std::cout << "Memory writes:    " << perfCounters.getMemoryWrites() << std::endl;
        std::cout << "===================================\n" << std::endl;
    }
};

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " <image_number> [scale_factor]" << std::endl;
        std::cout << "Example: " << argv[0] << " 01 0.75" << std::endl;
        std::cout << "Scale factor range: 0.5 to 1.0 in steps of 0.05" << std::endl;
        return 1;
    }
    
    std::string imageNumber = argv[1];
    float scaleFactor = (argc >= 3) ? std::atof(argv[2]) : 0.75f;
    
    float rounded = std::round(scaleFactor / 0.05f) * 0.05f;
    scaleFactor = rounded;
    
    std::string inputPath = "images/" + imageNumber + ".pgm";
    std::string outputPath = "images/" + imageNumber + "_output_" + 
                            std::to_string(static_cast<int>(scaleFactor * 100)) + ".pgm";
    
    std::cout << "Processing image: " << inputPath << std::endl;
    std::cout << "Scale factor: " << std::fixed << std::setprecision(2) << scaleFactor << std::endl;
    
    ImageProcessor processor;
    if (processor.processImage(inputPath, outputPath, scaleFactor)) {
        std::cout << "Output saved to: " << outputPath << std::endl;
        return 0;
    }
    
    return 1;
}
