# 🕒 Active Time Tracker

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

## 🌍 Cross-Compiling (Build for any OS)
Because Go supports cross-compilation natively, you can build the executable for Mac, Linux, or Windows from any machine without needing to install Go on the target devices.

**The easiest way — run the included build script from the project root:**
```powershell
.\build_all.ps1
```
This automatically compiles all 4 platform binaries and places them directly into your `%ONEDRIVE%\toolkit\` folder, ready to distribute to any device.

**Or build manually:**
```powershell
cd tracker-client

# For Windows (with console window — useful for debugging):
$env:GOOS="windows"; $env:GOARCH="amd64"
go build -o active-time-tracker-console.exe .

# For Windows (silent, no console window — use for startup/background running):
$env:GOOS="windows"; $env:GOARCH="amd64"
go build -ldflags -H=windowsgui -o active-time-tracker.exe .

# For macOS (Intel):
$env:GOOS="darwin"; $env:GOARCH="amd64"
go build -o active-time-tracker-mac-intel .

# For macOS (Apple Silicon M1/M2/M3):
$env:GOOS="darwin"; $env:GOARCH="arm64"
go build -o active-time-tracker-mac-arm64 .

# For Linux:
$env:GOOS="linux"; $env:GOARCH="amd64"
go build -o active-time-tracker-linux .
```

## 🪟 Running on Windows

**Step 1: Navigate to the Go client folder:**
```powershell
cd tracker-client
```

**Step 2 (Optional): Configure the shared data folder** (required for multi-device sync). Set the env variable to point to your OneDrive/Dropbox folder:
```powershell
$env:ACTIVE_TIME_FOLDER="$env:USERPROFILE\OneDrive\ActiveTime"
```

**Step 3: Run the tracker:**
```powershell
go run . 
# Or build it first: go build -o active-time-tracker.exe . && .\active-time-tracker.exe
```

**Step 4 (Optional): Run at login automatically (Silently)**
1. Build the executable so it runs completely hidden in the background without a console window:
   ```powershell
   go build -ldflags -H=windowsgui -o active-time-tracker.exe .
   ```
2. Press `Win + R`, type `shell:startup`, and press Enter.
3. In the folder that opens, Right-Click -> New -> Shortcut. Point the shortcut to your compiled `active-time-tracker.exe`.

*(Note: If you are using a custom `ACTIVE_TIME_FOLDER`, you must set it permanently in your Windows **System Environment Variables** (search "Environment Variables" in the Start menu) so the background process can see it on boot).*

## 🍎 Running on macOS

**Step 1: Transfer** the `active-time-tracker-mac` file to your Mac (e.g., place it in `~/Downloads`).

**Step 2: Make it executable.** Open Terminal and run:
```bash
chmod +x ~/Downloads/active-time-tracker-mac
```

**Step 3: Configure the shared data folder** (required for multi-device sync). Set the env variable to point to your OneDrive/Dropbox folder:
```bash
# Use $HOME, NOT ~ (tilde does not expand inside double quotes in bash)
export ACTIVE_TIME_FOLDER="$HOME/Library/CloudStorage/OneDrive-Personal/ActiveTime"
```

> **Note:** The OneDrive folder path varies by account type. Common paths on macOS:
> - Personal: `$HOME/Library/CloudStorage/OneDrive-Personal/`
> - Work/School: `$HOME/Library/CloudStorage/OneDrive-YourOrgName/`
> 
> You can find your exact path by running: `ls ~/Library/CloudStorage/`

**Step 4: Run the tracker:**
```bash
~/Downloads/active-time-tracker-mac
```

**Step 5 (Optional): Run at login automatically.** Create a launch agent so it starts on every boot:
```bash
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.worktime.tracker.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.worktime.tracker</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOUR_USERNAME/Downloads/active-time-tracker-mac</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>ACTIVE_TIME_FOLDER</key>
        <string>/Users/YOUR_USERNAME/Library/CloudStorage/OneDrive-Personal/ActiveTime</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/worktime-tracker.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/worktime-tracker.log</string>
</dict>
</plist>
EOF
# Replace YOUR_USERNAME with your actual macOS username, then load it:
launchctl load ~/Library/LaunchAgents/com.worktime.tracker.plist
```

## 🐧 Running on Linux

**Step 1: Transfer** the `active-time-tracker-linux` file to your Linux machine.

**Step 2: Install the idle detection dependency:**
```bash
sudo apt-get install xprintidle   # Debian / Ubuntu
# or
sudo dnf install xprintidle       # Fedora
```

**Step 3: Make it executable and run:**
```bash
chmod +x ~/Downloads/active-time-tracker-linux
export ACTIVE_TIME_FOLDER="$HOME/OneDrive/ActiveTime"
~/Downloads/active-time-tracker-linux
```

**Step 4 (Optional): Run at login automatically** using a systemd user service:
```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/worktime-tracker.service << 'EOF'
[Unit]
Description=Worktime Tracker

[Service]
ExecStart=%h/Downloads/active-time-tracker-linux
Environment="ACTIVE_TIME_FOLDER=%h/OneDrive/ActiveTime"
Restart=on-failure

[Install]
WantedBy=default.target
EOF
systemctl --user enable --now worktime-tracker.service
```

## 🛠 Quick Start (Legacy PowerShell Version — Windows Only)
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
