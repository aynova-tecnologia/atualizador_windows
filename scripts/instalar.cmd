@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1"
if errorlevel 1 (
    echo.
    echo A instalacao falhou. Tire um print desta janela e envie para a TI.
)
pause
