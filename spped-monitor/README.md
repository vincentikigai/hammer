# Internet Speed Monitor

A Windows PowerShell utility to continuously monitor your internet speed, including download speed, upload speed, and latency.

## Features

- **Continuous Monitoring**: Runs repeated speed tests at configurable intervals
- **Real-time Metrics**:
  - Download speed (Mbps)
  - Upload speed (Mbps)
  - Latency / Ping (ms)
- **Status Indicators**: Color-coded output with emoji indicators for quick visual feedback
- **Logging**: All test results logged to a daily log file
- **Threshold Warnings**: Alerts when speeds fall below configured thresholds
- **Graceful Shutdown**: Press `Ctrl+C` or type `q` to stop monitoring

## Getting Started

### Requirements
- Windows 10/11
- PowerShell 5.1 or later
- Internet connection with access to speed test servers

### Running the Monitor

#### Option 1: Background Execution (Recommended)
```
start_speed_monitor.bat
```
This launches the speed monitor in a new window and runs in the background.

#### Option 2: Terminal Execution
```powershell
.\speed_monitor.ps1
```
Run directly in PowerShell to see real-time output.

## Configuration

Edit `speed_monitor.ps1` to customize these settings:

```powershell
$INTERVAL          = 300        # Seconds between tests (300 = 5 mins)
$DOWNLOAD_LIMIT    = 10         # Mbps - warning threshold for download
$UPLOAD_LIMIT      = 5          # Mbps - warning threshold for upload
$LATENCY_LIMIT     = 100        # ms - warning threshold for latency
$TEST_SERVER_URL   = "..."      # Speed test server URL
```

## Output Format

```
╔════════════════════════════════════════════╗
║  🚀 Internet Speed Monitor                 ║
╠════════════════════════════════════════════╣
║ Download: 🟢  45.32 Mbps
║ Upload:   🟢  12.15 Mbps
║ Latency:  🟢  28 ms
╚════════════════════════════════════════════╝
```

**Status Indicators:**
- 🟢 **Green**: Good - within acceptable thresholds
- 🟡 **Yellow**: Warning - below configured limits
- 🔴 **Red**: Error - test failed or no data

## Logs

Speed test results are logged to:
```
..\logs\speed_monitor_YYYY-MM-DD.log
```

Each day creates a new log file with timestamped entries.

## Troubleshooting

### Script won't run
Ensure ExecutionPolicy allows scripts:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### No network detected
Verify internet connectivity:
```powershell
Test-Connection google.com
```

### Slow speed tests
- Check your actual ISP connection type
- Ensure no other applications are using the network
- Try running with longer `$INTERVAL` to avoid network saturation

## Advanced Usage

### Stop the Monitor
- Press `Ctrl+C` in the terminal window
- Or type `q` and press Enter

### View Live Logs
```powershell
Get-Content ..\logs\speed_monitor_*.log -Tail 20 -Wait
```

### Schedule with Task Scheduler
1. Create a new Basic Task in Task Scheduler
2. Set Trigger: At startup or Daily at specific time
3. Set Action: `Start a program`
4. Program: `cmd.exe`
5. Arguments: `/c start "" "%USERPROFILE%\path\to\start_speed_monitor.bat"`

## Notes

- Initial tests may take longer as the system establishes connections
- Results may vary based on ISP throttling and network congestion
- For most accurate results, close other applications during testing
- Test frequency can impact network bandwidth; default 5-minute interval recommended
