@echo off
Title Verificando Integridad de Manolito Engine...
color 0A

:: ======================================================
:: 1. DEFINIR LA FIRMA DIGITAL
set "EXPECTED_HASH=26A22ADACB03681FEA3DF6910AF9BD4F138431B9D38F5C757BCFC0F6F61981EB"
:: ======================================================

set "PS1_FILE=%~dp0manolito.ps1"

:: 2. Comprobar si existe el archivo
if not exist "%PS1_FILE%" (
    color 0C
    echo [!] ERROR CRITICO: No se encuentra el archivo manolito.ps1
    pause
    exit /b
)

:: 3. Calcular el Hash del archivo local (Certutil)
echo [i] Verificando integridad criptografica (SHA256)...
for /f "skip=1 tokens=* delims=" %%# in ('certutil -hashfile "%PS1_FILE%" SHA256') do (
    set "ACTUAL_HASH=%%#"
    goto :check_hash
)

:check_hash
:: Limpiar espacios invisibles generados por certutil
set ACTUAL_HASH=%ACTUAL_HASH: =%

:: 4. Comparar hashes
if /I "%ACTUAL_HASH%" neq "%EXPECTED_HASH%" (
    color 0C
    echo ===================================================
    echo [!] ALERTA DE SEGURIDAD: INTEGRIDAD COMPROMETIDA
    echo ===================================================
    echo El archivo manolito.ps1 ha sido modificado, esta corrupto
    echo o es una version no autorizada.
    echo.
    echo Hash Esperado: %EXPECTED_HASH%
    echo Hash Actual  : %ACTUAL_HASH%
    echo.
    echo Por su seguridad, el motor NO se ejecutara.
    pause
    exit /b
)

echo [OK] Firma verificada. Arrancando motor...

:: 5. Comprobar privilegios de Administrador (UAC)
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunManolito
) else (
    powershell -Command "Start-Process -FilePath cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:RunManolito
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1_FILE%"
exit
