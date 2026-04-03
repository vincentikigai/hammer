@echo off
REM ============================================================
REM  Speed Monitor Launcher
REM ============================================================

setlocal enabledelayedexpansion

REM Get the directory of this batch file
set SCRIPT_DIR=%~dp0

REM Check if PowerShell is available
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: PowerShell is not installed or not in PATH
    pause
    exit /b 1
)

REM Run the PowerShell script
echo Starting Internet Speed Monitor...
echo Press Ctrl+C or type 'q' to stop
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%speed_monitor.ps1"

if %errorlevel% neq 0 (
    echo.
    echo ERROR: Speed Monitor failed to run
    pause
)
