CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2 -I./includes
LDFLAGS = -lpng

SRC_DIR = src
INC_DIR = includes
BIN_DIR = bin
TEST_DIR = test

SRCS = $(SRC_DIR)/main.cpp $(SRC_DIR)/Image.cpp $(SRC_DIR)/BilinearInterpolator.cpp
OBJS = $(SRCS:$(SRC_DIR)/%.cpp=$(BIN_DIR)/%.o)
TARGET = $(BIN_DIR)/bilinear_interpolator

TEST_TARGET = $(BIN_DIR)/test_interpolation

.PHONY: all clean run test test-interpolation generate-test-images help

all: directories $(TARGET)

directories:
	@mkdir -p $(BIN_DIR)
	@mkdir -p images
	@mkdir -p $(TEST_DIR)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

$(BIN_DIR)/%.o: $(SRC_DIR)/%.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(BIN_DIR)/main.o: $(SRC_DIR)/main.cpp $(INC_DIR)/Image.h $(INC_DIR)/BilinearInterpolator.h \
                   $(INC_DIR)/Registers.h $(INC_DIR)/MemoryBank.h $(INC_DIR)/FixedPoint.h

$(BIN_DIR)/Image.o: $(SRC_DIR)/Image.cpp $(INC_DIR)/Image.h

$(BIN_DIR)/BilinearInterpolator.o: $(SRC_DIR)/BilinearInterpolator.cpp $(INC_DIR)/BilinearInterpolator.h \
                                   $(INC_DIR)/FixedPoint.h $(INC_DIR)/MemoryBank.h $(INC_DIR)/Registers.h

$(TEST_TARGET): $(TEST_DIR)/main_test.cpp $(INC_DIR)/FixedPoint.h
	$(CXX) $(CXXFLAGS) -o $@ $<

test-interpolation: $(TEST_TARGET)
	@echo "Ejecutando pruebas de interpolación bilineal Q8.8..."
	@$(TEST_TARGET)

run: $(TARGET)
	@echo "Running bilinear interpolation with scale 0.75..."
	@if [ -f images/01.png ]; then \
		$(TARGET) 01 0.75; \
	else \
		echo "Error: images/01.png not found. Run 'make generate-test-images' first."; \
	fi

test: $(TARGET)
	@echo "Testing with different scale factors..."
	@for scale in 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00; do \
		echo "\n=== Testing scale factor: $$scale ==="; \
		$(TARGET) 01 $$scale; \
	done

generate-test-images:
	@echo "Generating test images..."
	@python3 scripts/generate_test_images.py

clean:
	rm -rf $(BIN_DIR)/*.o $(TARGET) $(TEST_TARGET)
	rm -f images/*_output_*.png

distclean: clean
	rm -rf $(BIN_DIR)
	rm -f images/*.png

help:
	@echo "=== Parallel Bilinear Interpolation FPGA - Makefile Help ==="
	@echo ""
	@echo "Available targets:"
	@echo "  all                    - Build the bilinear interpolator"
	@echo "  run                    - Run with default test image (01.png, scale 0.75)"
	@echo "  test                   - Test all scale factors from 0.5 to 1.0"
	@echo "  test-interpolation     - Run Q8.8 interpolation unit tests"
	@echo "  generate-test-images   - Generate test images (grayscale PNG)"
	@echo "  clean                  - Remove object files and output images"
	@echo "  distclean              - Remove all generated files including test images"
	@echo "  help                   - Show this help message"
	@echo ""
	@echo "Manual usage:"
	@echo "  $(TARGET) <image_number> [scale_factor]"
	@echo "  Example: $(TARGET) 01 0.75"
	@echo ""
	@echo "Scale factor range: 0.5 to 1.0 in steps of 0.05"
