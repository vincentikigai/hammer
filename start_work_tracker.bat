@echo off
REM 工作时间统计 - 启动脚本
REM 保存为: StartWorkTracker.bat

echo 正在启动工作时间统计程序...

REM 以隐藏窗口方式运行 PowerShell 脚本
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0WorkTimeTracker.ps1"

REM 如果需要看到运行状态，使用下面这行（会显示控制台窗口）
REM powershell -ExecutionPolicy Bypass -File "%~dp0WorkTimeTracker.ps1"

exit