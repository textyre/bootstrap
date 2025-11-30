@echo off
REM Batch wrapper for SSH key setup

echo =========================================
echo SSH key setup
echo =========================================
echo.
echo Password will not be requested after setup!
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_ssh_key.ps1"

echo.
pause


