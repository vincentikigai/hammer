# Internet Monitor

A utility to monitor your internet and VPN connectivity. It provides granular status updates and distinguishes between a total internet outage and a global-only reachability issue.

## Features

- **Granular Monitoring**: Pings `google.com` (Global) and `baidu.com` (Local) to identify the nature of a disconnect.
- **Color-Coded Status**: 
    - **🟢 Green**: Connected (Primary: `google.com`).
    - **🟡 Yellow**: Global Internet Not Reachable (Google down, Baidu up).
    - **🔴 Red**: Internet Interrupted (Both down).
- **Windows Notifications**: Sends toast or balloon tip notifications with state-specific icons (Info/Warning/Error).
- **Background Execution**: Can run silently in the background.

## Getting Started

### Requirements
- Windows 10/11
- PowerShell 5.1 or later
- (Optional) `BurntToast` PowerShell module for rich notifications (script will attempt to auto-install this).

### Running the Monitor
- **Manual Start**: Run `start_monitor.bat` to launch the script in the background.
- **Terminal Start**: Execute `.\internet_monitor.ps1` in a PowerShell terminal to see real-time color-coded logs.

## Setup Startup with Windows (Manual)

To have the monitor start automatically when you log in:

1.  Press `Win + R` on your keyboard.
2.  Type `shell:startup` and press Enter. This opens the Windows Startup folder.
3.  Right-click `start_monitor.bat` in this directory and select **Create shortcut**.
4.  Move the newly created shortcut into the Startup folder you opened in step 2.

The monitor will now launch silently in the background every time you log in.

## Logic & Workflow
For a visual overview of how the script handles failures and target fallbacks, see [flowchart.md](flowchart.md).
