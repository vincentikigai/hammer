# IP-Tracker

A PowerShell-based utility to monitor and log your external IP address and DNS server changes. It tracks connection sessions, calculates durations, performs latency checks, and identifies the country associated with your current IP.

## Key Features

- **Real-time Monitoring**: Checks your connection every 10 seconds (configurable).
- **Change Detection**: Automatically detects and logs when your external IP or DNS servers change.
- **Session Logging**: Tracks the start time, end time, and duration of each connection session.
- **Detailed Data**: Logs IP address, DNS servers, country, and latency (ping to 8.8.8.8) to a CSV file.
- **Resumption**: Safely resumes tracking from previous sessions if the script or system restarts.
- **Heartbeat Updates**: Continuously updates the duration of the current session to prevent data loss in case of a crash.
- **Test Mode**: Includes a "dummy" mode for testing script logic without actual network changes.

## Getting Started

### Requirements

- Windows OS
- PowerShell 5.1 or later
- Active internet connection

### Installation

1.  Clone or download the `ip-tracker` repository.
2.  Ensure you have permission to run PowerShell scripts on your system (`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`).

### How to Run

-   **Normal Mode**: Run the `start_logger.bat` file or execute the script directly in PowerShell:
    ```powershell
    .\ip_logger.ps1
    ```
-   **Test/Dummy Mode**: Run the `start_test.bat` file or execute the script with the `-Dummy` switch:
    ```powershell
    .\ip_logger.ps1 -Dummy
    ```

## Log File Details

The script logs all data to a CSV file located at:
`~\NetworkMonitor\ip_log.csv`

### CSV Header Explanation

| Column | Description |
| :--- | :--- |
| `start_time` | Timestamp when the connection session began. |
| `end_time` | Timestamp when the connection session ended. |
| `ip` | External IP address during the session. |
| `dns_servers` | IPv4 DNS server addresses used during the session. |
| `duration_minutes` | Total duration of the session in minutes. |
| `last_latency_ms` | The last recorded ping latency to 8.8.8.8 (in ms). |
| `country` | The country associated with the external IP (via ip-api). |

## Workflow

For a detailed visual representation of the script's logic, refer to the [flowchart.md](flowchart.md) file. This document describes the initialization, main loop, change detection, and termination logic.

## Manual Control

- **Stop Logging**: Press `Ctrl+C` in the terminal to terminate the script. The script will automatically update the final record with the end time and total duration before closing.
- **Configuration**: You can adjust the `$interval` variable in `ip_logger.ps1` to change the frequency of checks.
