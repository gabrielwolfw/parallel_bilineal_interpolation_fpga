# PowerShell build script for Windows
# Alternative to Makefile for pure PowerShell environments

param(
    [string]$Target = "all"
)

$CXX = "g++"
$CXXFLAGS = "-std=c++17 -Wall -Wextra -O2 -I./includes"
$LDFLAGS = ""  # No external libraries needed for PGM format

$SRC_DIR = "src"
$INC_DIR = "includes"
$BIN_DIR = "bin"

function Create-Directories {
    if (-not (Test-Path $BIN_DIR)) { New-Item -ItemType Directory -Path $BIN_DIR | Out-Null }
    if (-not (Test-Path "images")) { New-Item -ItemType Directory -Path "images" | Out-Null }
    if (-not (Test-Path "test")) { New-Item -ItemType Directory -Path "test" | Out-Null }
    Write-Host "Directories created." -ForegroundColor Green
}

function Build-All {
    Write-Host "Building bilinear interpolator..." -ForegroundColor Cyan
    Create-Directories
    
    # Compile source files
    Write-Host "Compiling main.cpp..." -ForegroundColor Yellow
    & $CXX $CXXFLAGS.Split() -c "$SRC_DIR/main.cpp" -o "$BIN_DIR/main.o"
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to compile main.cpp"; exit 1 }
    
    Write-Host "Compiling Image.cpp..." -ForegroundColor Yellow
    & $CXX $CXXFLAGS.Split() -c "$SRC_DIR/Image.cpp" -o "$BIN_DIR/Image.o"
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to compile Image.cpp"; exit 1 }
    
    Write-Host "Compiling BilinearInterpolator.cpp..." -ForegroundColor Yellow
    & $CXX $CXXFLAGS.Split() -c "$SRC_DIR/BilinearInterpolator.cpp" -o "$BIN_DIR/BilinearInterpolator.o"
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to compile BilinearInterpolator.cpp"; exit 1 }
    
    # Link
    Write-Host "Linking..." -ForegroundColor Yellow
    & $CXX $CXXFLAGS.Split() -o "$BIN_DIR/bilinear_interpolator.exe" `
        "$BIN_DIR/main.o" "$BIN_DIR/Image.o" "$BIN_DIR/BilinearInterpolator.o" `
        $LDFLAGS.Split()
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Build successful! Executable: $BIN_DIR/bilinear_interpolator.exe" -ForegroundColor Green
    } else {
        Write-Error "Linking failed"
        exit 1
    }
}

function Run-Default {
    if (-not (Test-Path "$BIN_DIR/bilinear_interpolator.exe")) {
        Write-Host "Executable not found. Building first..." -ForegroundColor Yellow
        Build-All
    }
    
    if (-not (Test-Path "images/01.pgm")) {
        Write-Error "Test image not found. Run: .\build.ps1 generate-test-images"
        exit 1
    }
    
    Write-Host "Running with default parameters (01.pgm, scale 0.75)..." -ForegroundColor Cyan
    & "$BIN_DIR/bilinear_interpolator.exe" "01" "0.75"
}

function Run-Tests {
    if (-not (Test-Path "$BIN_DIR/bilinear_interpolator.exe")) {
        Write-Host "Executable not found. Building first..." -ForegroundColor Yellow
        Build-All
    }
    
    Write-Host "Testing with different scale factors..." -ForegroundColor Cyan
    $scales = @(0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00)
    
    foreach ($scale in $scales) {
        Write-Host "`n=== Testing scale factor: $scale ===" -ForegroundColor Magenta
        & "$BIN_DIR/bilinear_interpolator.exe" "01" "$scale"
    }
}

function Generate-TestImages {
    Write-Host "Generating test images..." -ForegroundColor Cyan
    python scripts\generate_test_images.py
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Test images generated successfully!" -ForegroundColor Green
    } else {
        Write-Error "Failed to generate test images. Make sure Python 3 and Pillow are installed."
    }
}

function Clean-Build {
    Write-Host "Cleaning build artifacts..." -ForegroundColor Yellow
    Remove-Item -Path "$BIN_DIR/*.o" -ErrorAction SilentlyContinue
    Remove-Item -Path "$BIN_DIR/*.exe" -ErrorAction SilentlyContinue
    Remove-Item -Path "images/*_output_*.png" -ErrorAction SilentlyContinue
    Write-Host "Clean complete." -ForegroundColor Green
}

function Show-Help {
    Write-Host "=== Parallel Bilinear Interpolation FPGA - Build Script ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\build.ps1 [target]" -ForegroundColor White
    Write-Host ""
    Write-Host "Available targets:" -ForegroundColor Yellow
    Write-Host "  all                    - Build the bilinear interpolator (default)"
    Write-Host "  run                    - Run with default test image (01.png, scale 0.75)"
    Write-Host "  test                   - Test all scale factors from 0.5 to 1.0"
    Write-Host "  generate-test-images   - Generate test images (grayscale PNG)"
    Write-Host "  clean                  - Remove object files and output images"
    Write-Host "  help                   - Show this help message"
    Write-Host ""
    Write-Host "Manual usage:" -ForegroundColor Yellow
    Write-Host "  .\bin\bilinear_interpolator.exe <image_number> [scale_factor]"
    Write-Host "  Example: .\bin\bilinear_interpolator.exe 01 0.75"
    Write-Host ""
    Write-Host "Requirements:" -ForegroundColor Yellow
    Write-Host "  - MinGW/MSYS2 with g++ (C++17 support)"
    Write-Host "  - Python 3 with Pillow and numpy (for test image generation)"
    Write-Host "  - No external C++ libraries needed (uses PGM format)"
}

# Main script logic
switch ($Target.ToLower()) {
    "all"                  { Build-All }
    "build"                { Build-All }
    "run"                  { Run-Default }
    "test"                 { Run-Tests }
    "generate-test-images" { Generate-TestImages }
    "clean"                { Clean-Build }
    "help"                 { Show-Help }
    default                { 
        Write-Host "Unknown target: $Target" -ForegroundColor Red
        Show-Help
        exit 1
    }
}
