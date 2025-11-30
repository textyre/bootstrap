@echo off
REM Batch wrapper for launching the PowerShell sync script
REM Convenience entry point for double-click execution

echo =========================================
echo Sync to Arch server
echo =========================================
echo.

REM Launch the PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync_to_server.ps1"

echo.
pause

