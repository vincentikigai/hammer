@echo off
REM Work Time Tracker - Start Script
REM Filename: start_active_state_logger.bat

echo Starting Work Time Tracker...

REM Start PowerShell in the background with hidden window
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0active_state_logger.ps1" %*

REM Uncomment the line below (and comment out the one above) to see the console window for debugging:
REM powershell -ExecutionPolicy Bypass -File "%~dp0active_state_logger.ps1" %*

exit