# IP Switcher Tool

This directory contains two interactive scripts to easily switch your network interface IP configurations between DHCP and various static profiles.

## Files
- `switch-ip-windows.ps1` - PowerShell script for Windows.
- `switch-ip-linux.sh` - Bash script for Linux (requires `NetworkManager` / `nmcli`).

## How to Configure Profiles

Both scripts contain a section near the top where you can define your custom profiles.

### Windows Configuration
Open `switch-ip-windows.ps1` in a text editor and modify the `$Profiles` array:
```powershell
$Profiles = @(
    @{ Name = "DHCP (Automatic)"; Type = "DHCP" },
    @{ Name = "Home Network"; Type = "Static"; IP = "192.168.1.100"; PrefixLength = 24; Gateway = "192.168.1.1"; DNS = @("8.8.8.8", "1.1.1.1") },
    @{ Name = "Work Network"; Type = "Static"; IP = "10.0.0.50"; PrefixLength = 24; Gateway = "10.0.0.1"; DNS = @("10.0.0.2") }
)
```
*(Note: `PrefixLength = 24` is equivalent to a subnet mask of `255.255.255.0`)*

### Linux Configuration
Open `switch-ip-linux.sh` in a text editor and modify the `profiles` array. The format is `Name|Type|IP/Prefix|Gateway|DNS`.
```bash
profiles=(
    "DHCP (Automatic)|DHCP|||"
    "Home Network|Static|192.168.1.100/24|192.168.1.1|8.8.8.8,1.1.1.1"
    "Work Network|Static|10.0.0.50/24|10.0.0.1|10.0.0.2"
)
```

## Usage

### Windows
You must run the PowerShell script as Administrator.
1. Right-click `switch-ip-windows.ps1` and select **Run with PowerShell** (ensure you accept the UAC prompt if applicable).
2. Alternatively, open an elevated PowerShell prompt and run:
   ```powershell
   .\switch-ip-windows.ps1
   ```
3. Follow the interactive menu to select your adapter and desired profile.

### Linux
You must run the Bash script as root (using `sudo`).
1. Make the script executable (only needed once):
   ```bash
   chmod +x switch-ip-linux.sh
   ```
2. Run the script:
   ```bash
   sudo ./switch-ip-linux.sh
   ```
3. Follow the interactive menu to select your interface and desired profile.
