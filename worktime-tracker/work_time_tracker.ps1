#Requires -Version 5.1
# Work Time Tracker - Enhanced Version (Supports Test Mode & Shutdown Persistence)
# Save as: WorkTimeTracker.ps1

param(
    [string]$DataFolder = "$env:USERPROFILE\WorkTimeData",
    [int]$InactivityThreshold = 180,
    [int]$ReportIntervalMinutes = 60,
    [switch]$TestMode
)

# Manual version check
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Error "This script requires PowerShell 5.1 or later. Please upgrade your system."
    exit 1
}

if ($TestMode) {
    $DataFolder = "$env:USERPROFILE\WorkTimeDataTest"
    $InactivityThreshold = 5
    $ReportIntervalMinutes = 1
    Write-Host ">>> Test Mode Enabled - Threshold: $InactivityThreshold s | Interval: $ReportIntervalMinutes min <<<" -ForegroundColor White -BackgroundColor DarkMagenta
}

$logFile = "$DataFolder\work_log.json"

# Create folder
if (-not (Test-Path $DataFolder)) {
    New-Item -ItemType Directory -Path $DataFolder | Out-Null
}

# Helper: Convert PSCustomObject to Hashtable
function ConvertTo-Hashtable {
    param($InputObject)
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable $property.Value
        }
        return $hash
    } elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += ConvertTo-Hashtable $item
        }
        return ,$result
    } else {
        return $InputObject
    }
}

# Load or init data
function Load-Data {
    if (Test-Path $logFile) {
        $raw = Get-Content $logFile -Raw | ConvertFrom-Json
        return ConvertTo-Hashtable $raw
    } else {
        return @{
            sessions = @()
            dailyStats = @{}
            activeSession = $null # Current session state for recovery
        }
    }
}

# Save data
function Save-Data {
    param($data)
    $data | ConvertTo-Json -Depth 10 | Set-Content $logFile
}

# Win32 API for Idle Time
$typeDefinition = @'
using System;
using System.Runtime.InteropServices;

public class IdleTime {
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    public static uint GetIdleTime() {
        LASTINPUTINFO lastInputInfo = new LASTINPUTINFO();
        lastInputInfo.cbSize = (uint)Marshal.SizeOf(lastInputInfo);
        GetLastInputInfo(ref lastInputInfo);
        return ((uint)Environment.TickCount - lastInputInfo.dwTime) / 1000;
    }
}
'@

try {
    Add-Type -TypeDefinition $typeDefinition -ErrorAction SilentlyContinue
} catch {}

# Format seconds to Time
function Format-Duration {
    param($seconds)
    $totalSeconds = [int]$seconds
    $hours = [Math]::Floor($totalSeconds / 3600)
    $minutes = [Math]::Floor(($totalSeconds % 3600) / 60)
    $secs = $totalSeconds % 60
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$hours, [int]$minutes, [int]$secs
}

# Daily report generation
function Generate-DailyReport {
    param($date, $sessions)
    if (-not $sessions) { return 0 }
    $durations = @($sessions | ForEach-Object { $_.duration })
    $totalSeconds = ($durations | Measure-Object -Sum).Sum
    $sessionCount = $sessions.Count
    $report = "Work Time Report - $date`nTotal: $(Format-Duration $totalSeconds)`nSessions: $sessionCount`n"
    foreach ($session in $sessions) {
        $report += "`n$($session.start) - $($session.end) | $(Format-Duration $session.duration)"
    }
    $reportFile = "$DataFolder\report_$($date -replace '/','-').txt"
    $report | Set-Content $reportFile
    return $totalSeconds
}

# Shutdown / Cleanup handler
function Stop-TrackerGracefully {
    param($data, $isWorking, $sessionStart)
    if ($isWorking -and $sessionStart) {
        $now = Get-Date
        $sessionEnd = $now
        $duration = ($sessionEnd - $sessionStart).TotalSeconds
        if ($duration -gt 1) {
            $today = $now.ToString('yyyy-MM-dd')
            $session = @{
                start = $sessionStart.ToString('HH:mm:ss')
                end = $sessionEnd.ToString('HH:mm:ss')
                duration = [int]$duration
            }
            if ($null -eq $data.dailyStats.$today) { $data.dailyStats[$today] = @{ sessions = @(); totalSeconds = 0 } }
            $data.dailyStats[$today].sessions += $session
            $data.sessions += @{
                date = $today
                start = $sessionStart.ToString('yyyy-MM-dd HH:mm:ss')
                end = $sessionEnd.ToString('yyyy-MM-dd HH:mm:ss')
                duration = [int]$duration
            }
            Write-Host "`n[SIG] Final session saved." -ForegroundColor Yellow
        }
    }
    $data.activeSession = $null # Clear heartbeat for clean exit
    Save-Data $data
    Write-Host "[SIG] Tracker stopped." -ForegroundColor Red
}

# Main Application
function Start-Tracker {
    Write-Host "Work Time Tracker Started..." -ForegroundColor Green
    Write-Host "Data Path: $DataFolder" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Cyan
    
    $data = Load-Data
    
    # --- Recovery Logic ---
    if ($data.activeSession) {
        Write-Host ">>> Recovering unclosed session from $($data.activeSession.start)..." -ForegroundColor Magenta
        $recSession = $data.activeSession
        $today = $recSession.date
        if ($null -eq $data.dailyStats.$today) { $data.dailyStats[$today] = @{ sessions = @(); totalSeconds = 0 } }
        
        $session = @{
            start = $recSession.startTime
            end = $recSession.lastHeartbeatTime
            duration = [int]$recSession.duration
        }
        $data.dailyStats[$today].sessions += $session
        $data.sessions += @{
            date = $today
            start = "$today $($recSession.startTime)"
            end = "$today $($recSession.lastHeartbeatTime)"
            duration = [int]$recSession.duration
        }
        $data.activeSession = $null
        Save-Data $data
        Write-Host ">>> Session recovered successfully." -ForegroundColor Green
    }
    
    $isWorking = $false
    $sessionStart = $null
    $lastSaveTime = Get-Date

    # Interruption Trap
    trap { Stop-TrackerGracefully $data $isWorking $sessionStart; break }

    while ($true) {
        $idleSeconds = [IdleTime]::GetIdleTime()
        $now = Get-Date
        $today = $now.ToString('yyyy-MM-dd')
        
        if ($null -eq $data.dailyStats) { $data.dailyStats = @{} }
        if (-not $data.dailyStats.ContainsKey($today)) {
            $data.dailyStats[$today] = @{ sessions = @(); totalSeconds = 0 }
        }
        
        if ($idleSeconds -lt $InactivityThreshold) {
            # Active
            if (-not $isWorking) {
                $isWorking = $true
                $sessionStart = $now
                Write-Host "[$($now.ToString('HH:mm:ss'))] Session Start" -ForegroundColor Green
            }
            
            # Heartbeat Save (every 30 seconds while working)
            if ($now.Second % 30 -eq 0) {
                $duration = ($now - $sessionStart).TotalSeconds
                $data.activeSession = @{
                    date = $today
                    startTime = $sessionStart.ToString('HH:mm:ss')
                    lastHeartbeatTime = $now.ToString('HH:mm:ss')
                    duration = [int]$duration
                }
                Save-Data $data
            }

        } else {
            # Inactive
            if ($isWorking) {
                $isWorking = $false
                $sessionEnd = $now.AddSeconds(-$InactivityThreshold)
                $duration = ($sessionEnd - $sessionStart).TotalSeconds
                if ($duration -gt 1) { 
                    $session = @{
                        start = $sessionStart.ToString('HH:mm:ss')
                        end = $sessionEnd.ToString('HH:mm:ss')
                        duration = [int]$duration
                    }
                    $data.dailyStats[$today].sessions += $session
                    if ($null -eq $data.sessions) { $data.sessions = @() }
                    $data.sessions += @{
                        date = $today
                        start = $sessionStart.ToString('yyyy-MM-dd HH:mm:ss')
                        end = $sessionEnd.ToString('yyyy-MM-dd HH:mm:ss')
                        duration = [int]$duration
                    }
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Session End - Duration: $(Format-Duration $duration)" -ForegroundColor Yellow
                    $data.activeSession = $null # Clear heartbeat
                    Save-Data $data
                }
                $sessionStart = $null
            }
        }
        
        # Periodic report saving
        if (($now - $lastSaveTime).TotalMinutes -gt $ReportIntervalMinutes) {
            if ($data.dailyStats[$today].sessions.Count -gt 0) {
                $totalSeconds = Generate-DailyReport $today $data.dailyStats[$today].sessions
                $data.dailyStats[$today].totalSeconds = $totalSeconds
                Save-Data $data
                Write-Host "[$($now.ToString('HH:mm:ss'))] Auto Save & Report updated." -ForegroundColor Cyan
            }
            $lastSaveTime = $now
        }
        
        # Display status
        $displayInterval = if ($TestMode) { 10 } else { 60 }
        if ($now.Second % $displayInterval -eq 0) {
            if ($isWorking) {
                $currentDuration = ($now - $sessionStart).TotalSeconds
                $todayTotal = $data.dailyStats[$today].totalSeconds + $currentDuration
                Write-Host "[$($now.ToString('HH:mm:ss'))] Working - Session: $(Format-Duration $currentDuration) | Today: $(Format-Duration $todayTotal)" -ForegroundColor Green
            } elseif ($TestMode) {
                Write-Host "[$($now.ToString('HH:mm:ss'))] Idle: $idleSeconds s" -ForegroundColor Gray
            }
        }
        Start-Sleep -Seconds 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-Tracker
}
