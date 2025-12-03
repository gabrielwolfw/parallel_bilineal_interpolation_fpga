# ============================================
# quick_test_jtag.ps1
# Prueba rápida de escritura/lectura JTAG
# ============================================

param(
    [int]$StartAddr = 0,
    [switch]$Verify
)

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Quick JTAG Memory Test" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Verificar que Python esté disponible
$python = Get-Command python -ErrorAction SilentlyContinue

if (-not $python) {
    Write-Host "ERROR: Python no encontrado" -ForegroundColor Red
    exit 1
}

# Directorio de scripts
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mem_writer = Join-Path $scriptDir "jtag_mem_writer.py"

if (-not (Test-Path $mem_writer)) {
    Write-Host "ERROR: jtag_mem_writer.py no encontrado" -ForegroundColor Red
    exit 1
}

# Datos de prueba: patrón incremental 0x00 a 0xFF
Write-Host "Generando patrón de prueba (256 bytes: 0x00 a 0xFF)..." -ForegroundColor Yellow

$testData = @()
for ($i = 0; $i -lt 256; $i++) {
    $testData += "0x{0:X2}" -f $i
}

Write-Host "Patrón generado: $($testData.Count) bytes" -ForegroundColor Green
Write-Host ""

# Construir comando
$cmd = "python `"$mem_writer`" --addr $StartAddr --data $($testData -join ' ')"

if ($Verify) {
    $cmd += " --verify"
}

$cmd += " -v"

Write-Host "Ejecutando:" -ForegroundColor Cyan
Write-Host "  $cmd" -ForegroundColor White
Write-Host ""

# Ejecutar
Invoke-Expression $cmd

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Test completado" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
