# Worktime Tracker

A lightweight PowerShell-based utility to monitor user activity and log work sessions.

## 🚀 Features
- **Automatic Activity Detection**: Tracks work sessions based on system input (mouse/keyboard).
- **Session Logging**: Detailed logs of session start, end, and duration stored in JSON.
- **Reporting**: Automatically generates daily summaries of work hours.
- **Background Execution**: Can be run silently via the provided batch script.
- **Testable**: Supports a dedicated test mode and Pester unit tests.

## 📂 Project Structure
- `WorkTimeTracker.ps1`: The main tracking engine (refactored for robustness and testability).
- `StartWorkTracker.bat`: A simple launcher to start the tracker in the background.
- `WorkTimeTracker.Tests.ps1`: Pester unit tests for core utility functions.

## ⚙️ Requirements
- **PowerShell 5.1 or later**: The script uses features introduced in PowerShell 5.1.
- **Windows OS**: Uses Win32 APIs (`user32.dll`) for idle time detection.

## 🛠 Usage

### Standard Run
To start tracking work time normally:
1. Run `StartWorkTracker.bat` or run directly in PowerShell:
   ```powershell
   .\WorkTimeTracker.ps1
   ```
2. Logs and reports are saved to `$env:USERPROFILE\WorkTimeData`.

### Test Mode
To verify the tracker logic without affecting your real data, use the `-TestMode` flag:
```powershell
.\WorkTimeTracker.ps1 -TestMode
```
- Inactivity threshold is reduced to 5 seconds.
- Reports are generated every 1 minute.
- Data is saved to `$env:USERPROFILE\WorkTimeDataTest`.

## ⚙️ Configuration (Parameters)
The script supports several optional parameters:
- `-DataFolder <string>`: Custom directory for logs and reports.
- `-InactivityThreshold <int>`: Delay in seconds before a session is considered ended (default: 180).
- `-ReportIntervalMinutes <int>`: Frequency of automatic report updates (default: 60).

## 🧪 Testing
To run the automated unit tests (requires [Pester](https://pester.dev/)):
```powershell
Invoke-Pester -Path .\WorkTimeTracker.Tests.ps1
```

## 📝 Troubleshooting
- **Execution Policy**: If the script is blocked, run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.
- **JSON Format**: If the log file becomes corrupted, delete `work_log.json` and it will be re-initialized.
