# 🕒 Worktime Tracker

A robust, lightweight PowerShell utility to automatically monitor user activity and log work sessions with zero manual effort.

## 🚀 Key Features
- **Smart Activity Detection**: Automatically tracks sessions based on mouse and keyboard input.
- **Dual Logging**: Maintains a structured **JSON** log for internal logic and a flat **CSV** export for Excel/Spreadsheet analysis.
- **Markdown Reports**: Generates professional daily summaries (`.md`) with session tables and break tracking.
- **Safety & Persistence**: 30-second heartbeats and auto-recovery ensure data isn't lost during power outages.
- **Midnight Splitting**: Automatically splits sessions at 12:00 AM for 100% accurate daily totals.
- **Background Mode**: Run silently in the tray/background via the included `.bat` launcher.

## 📂 Project Structure
- `work_time_tracker.ps1`: The core tracking engine.
- `start_work_tracker.bat`: Launcher for background execution.
- `work_time_tracker.Tests.ps1`: Pester unit tests for core logic.
- `BACKLOG.md`: Future roadmap and pending features.

## 📐 Architecture & Design Principles
- **Domain Driven Design (DDD)**: We try to lean workflows and components closer to pure Domain Driven Design. For high-level behavioral modeling, see `domain_logic.md` which models **Domain behavior and processes** (e.g. `State: Active`, `Event: User Input Detected`). For the lower-level technical architecture spanning script constructs (like Windows API calls and execution loops), see `flowchart.md`. We keep these separated so we do not use hybrid models that mix Domain behaviors with Implementation details.

## ⚙️ Requirements
- **Windows OS** (uses `user32.dll` for idle detection).
- **PowerShell 5.1 or later**.

## 🛠 Quick Start
1.  **Run**: Double-click `start_work_tracker.bat` or run `.\work_time_tracker.ps1` in PowerShell.
2.  **View**: Check your results in `$env:USERPROFILE\WorkTimeData`.
3.  **Test**: Run `.\work_time_tracker.ps1 -TestMode` for a 5-second threshold test.

## ⚙️ Configuration (Optional)
| Parameter | Description | Default |
| :--- | :--- | :--- |
| `-DataFolder` | Directory for logs and reports | `~\WorkTimeData` |
| `-InactivityThreshold` | Idle seconds before session ends | `180` |
| `-ReportIntervalMinutes`| How often to update the MD report | `60` |

## 🧪 Testing
Requires [Pester](https://pester.dev/):
```powershell
Invoke-Pester -Path .\work_time_tracker.Tests.ps1
```

## 📝 Troubleshooting
- **Execution Policy**: If blocked, run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.
- **Manual Reset**: Delete `session_log.json`, `active_state.json`, `daily_stats.json` and `session_history.csv` to start with a fresh history.

## 📅 Regenerating Reports
If you need to regenerate the daily `.md` report for today or a specific past date (e.g., if you manually edited the `session_log.json`), use the `regenerate_reports.ps1` script:

```powershell
# Regenerate for today
.\regenerate_reports.ps1

# Regenerate for specific dates
.\regenerate_reports.ps1 -Dates "2026-04-14", "2026-04-13"
```
