@echo off
REM launch the IP logger in dummy mode for testing
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0\ip_logger.ps1" -Dummy
