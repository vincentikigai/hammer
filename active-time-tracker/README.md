# 🕒 Worktime Tracker

A robust, lightweight utility to automatically monitor user activity and log work sessions with zero manual effort. 
It features a cross-platform **Go client** that supports syncing multiple devices (Windows, Mac, Linux) into a single unified Markdown report via Cloud Sync.

## 🚀 Key Features
- **Multi-Device & Cross-Platform**: Run on Windows, macOS, and Linux. Syncs via any shared folder (OneDrive, Dropbox) to generate unified reports.
- **Smart Activity Detection**: Automatically tracks sessions based on mouse and keyboard input natively on each OS.
- **Dual Logging**: Maintains a structured **JSON** log for internal logic and a flat **CSV** export for Excel/Spreadsheet analysis.
- **Markdown Reports**: Generates professional daily summaries (`.md`) with session tables and break tracking for all your devices merged together.
- **Safety & Persistence**: 30-second heartbeats and auto-recovery ensure data isn't lost during power outages.
- **Midnight Splitting**: Automatically splits sessions at 12:00 AM for 100% accurate daily totals.

## 📂 Project Structure
- `tracker-client/`: The modern cross-platform Go tracking engine (Recommended).
- `active_state_logger.ps1`: The legacy Windows-only PowerShell tracking engine.
- `domain_logic.md` & `flowchart.md`: Core Domain Driven Design (DDD) specifications used across both implementations.

## ⚙️ Requirements
- **Windows OS**: Works out of the box.
- **macOS**: Works out of the box.
- **Linux**: Requires `xprintidle` installed (e.g. `sudo apt-get install xprintidle`).

## 🛠 Quick Start (Cross-Platform Go Client)

**To run locally or build from source:**
1.  Navigate to the Go client folder: `cd tracker-client`
2.  Run the tracker: `go run .` (or `.\active-time-tracker.exe`)
3.  Check your results in `~/ActiveTime` (or your `$ACTIVE_TIME_FOLDER`).

**To cross-compile for Mac/Linux from Windows:**
You can build the executable for your Mac or Linux machine without installing Go on those devices.
```powershell
cd tracker-client

# For macOS (Intel / Apple Silicon):
$env:GOOS="darwin"
$env:GOARCH="amd64" # Use "arm64" for Apple Silicon (M1/M2/M3)
go build -o active-time-tracker-mac .

# For Linux:
$env:GOOS="linux"
$env:GOARCH="amd64"
go build -o active-time-tracker-linux .
```
Transfer the resulting file to your device, make it executable (`chmod +x ./active-time-tracker-mac`), and run it.

## 🛠 Quick Start (Legacy PowerShell Version)
1.  **Run**: Double-click `start_active_state_logger.bat` or run `.\active_state_logger.ps1` in PowerShell.
2.  **Test**: Run `.\active_state_logger.ps1 -TestMode` for a 5-second threshold test.

## ⚙️ Configuration (Optional)
| Parameter | Description | Default |
| :--- | :--- | :--- |
| `-DataFolder` | Directory for logs and reports | `~\ActiveTime` |
| `-InactivityThreshold` | Idle seconds before session ends | `180` |
| `-ReportIntervalMinutes`| How often to update the MD report | `60` |

## 🧪 Testing
Requires [Pester](https://pester.dev/):
```powershell
Invoke-Pester -Path .\active_state_logger.Tests.ps1
```

## 📝 Troubleshooting
- **Execution Policy**: If blocked, run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.
- **Manual Reset**: Delete `session_log.json`, `active_state.json` and `session_history.csv` to start with a fresh history.

## 📅 Regenerating Reports
If you need to regenerate the daily `.md` report for today or a specific past date (e.g., if you manually edited the `session_log.json`), use the `regenerate_reports.ps1` script:

```powershell
# Regenerate for today
.\regenerate_reports.ps1

# Regenerate for specific dates
.\regenerate_reports.ps1 -Dates "2026-04-14", "2026-04-13"
```
