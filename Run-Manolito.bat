@echo off
Title Iniciando Manolito v2.7.0...

:: 1. Comprobar privilegios de Administrador
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunManolito
) else (
    :: Pedir permisos UAC usando la ruta absoluta segura
    powershell -Command "Start-Process -FilePath cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:RunManolito
:: 2. Navegar a la carpeta actual y lanzar el motor ocultando la consola negra
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0manolito.ps1"

exit
