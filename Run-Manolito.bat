@echo off
Title Verificando Integridad de Manolito Engine...
color 0A

:: ======================================================
:: 1. DEFINIR LA FIRMA DIGITAL
set "EXPECTED_HASH=04A239A52CCF3103301817E06BCB097F88709936FEB3EB8E90236863C2BE7D42"
:: ======================================================

set "PS1_FILE=%~dp0manolito.ps1"

if not exist "%PS1_FILE%" (
    color 0C
    echo [!] ERROR CRITICO: No se encuentra el archivo manolito.ps1
    pause
    exit /b
)

echo [i] Verificando integridad criptografica (SHA256)...
for /f "skip=1 tokens=* delims=" %%# in ('certutil -hashfile "%PS1_FILE%" SHA256') do (
    set "ACTUAL_HASH=%%#"
    goto :check_hash
)

:check_hash
set ACTUAL_HASH=%ACTUAL_HASH: =%

if /I "%ACTUAL_HASH%" neq "%EXPECTED_HASH%" (
    color 0C
    echo ===================================================
    echo [!] ALERTA DE SEGURIDAD: INTEGRIDAD COMPROMETIDA
    echo ===================================================
    echo Hash Esperado: %EXPECTED_HASH%
    echo Hash Actual  : %ACTUAL_HASH%
    pause
    exit /b
)

:: 2. Lanzamiento Inteligente (Doble Bypass de Politicas)
net session >nul 2>&1
if %errorLevel% == 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1_FILE%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"\"%PS1_FILE%\"\"' -Verb RunAs"
)
exit
