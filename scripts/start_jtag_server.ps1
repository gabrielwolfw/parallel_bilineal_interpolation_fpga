# ============================================
# start_jtag_server.ps1
# Inicia el servidor TCL JTAG para comunicación con FPGA
# ============================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "JTAG Server Starter" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Verificar que Quartus esté en el PATH
$quartus_stp = Get-Command quartus_stp -ErrorAction SilentlyContinue

if (-not $quartus_stp) {
    Write-Host "ERROR: quartus_stp no encontrado en PATH" -ForegroundColor Red
    Write-Host "Agrega Quartus a tu PATH o ejecuta desde Quartus Shell" -ForegroundColor Yellow
    exit 1
}

Write-Host "Quartus encontrado: $($quartus_stp.Source)" -ForegroundColor Green
Write-Host ""

# Cambiar a directorio vjtag_pc
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vjtag_pc_dir = Join-Path $scriptDir "..\fpga\vjtag_pc"

if (-not (Test-Path $vjtag_pc_dir)) {
    Write-Host "ERROR: Directorio vjtag_pc no encontrado" -ForegroundColor Red
    exit 1
}

Set-Location $vjtag_pc_dir
Write-Host "Directorio de trabajo: $(Get-Location)" -ForegroundColor Cyan
Write-Host ""

# Parámetros
$DATA_WIDTH = 8
$PORT = 2540

Write-Host "Configuración:" -ForegroundColor Yellow
Write-Host "  Ancho de datos: $DATA_WIDTH bits" -ForegroundColor White
Write-Host "  Puerto TCP:     $PORT" -ForegroundColor White
Write-Host ""

Write-Host "Iniciando servidor JTAG TCL..." -ForegroundColor Cyan
Write-Host "Presiona Ctrl+C para detener" -ForegroundColor Yellow
Write-Host ""

# Iniciar servidor
quartus_stp -t jtag_server.tcl $DATA_WIDTH $PORT
