# Work Time Tracker - Enhanced Version (Supports Test Mode)
# Save as: WorkTimeTracker.ps1

param(
    [string]$DataFolder = "$env:USERPROFILE\WorkTimeData",
    [int]$InactivityThreshold = 180,
    [int]$ReportIntervalMinutes = 60,
    [switch]$TestMode
)

if ($TestMode) {
    $DataFolder = "$env:USERPROFILE\WorkTimeDataTest"
    $InactivityThreshold = 5
    $ReportIntervalMinutes = 1
    Write-Host ">>> Test Mode Enabled - Threshold: $InactivityThreshold s | Interval: $ReportIntervalMinutes min <<<" -ForegroundColor White -BackgroundColor DarkMagenta
}

$logFile = "$DataFolder\work_log.json"

if (-not (Test-Path $DataFolder)) {
    New-Item -ItemType Directory -Path $DataFolder | Out-Null
}

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

function Load-Data {
    if (Test-Path $logFile) {
        $raw = Get-Content $logFile -Raw | ConvertFrom-Json
        return ConvertTo-Hashtable $raw
    } else {
        return @{
            sessions = @()
            dailyStats = @{}
        }
    }
}

function Save-Data {
    param($data)
    $data | ConvertTo-Json -Depth 10 | Set-Content $logFile
}

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

function Format-Duration {
    param($seconds)
    $totalSeconds = [int]$seconds
    $hours = [Math]::Floor($totalSeconds / 3600)
    $minutes = [Math]::Floor(($totalSeconds % 3600) / 60)
    $secs = $totalSeconds % 60
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$hours, [int]$minutes, [int]$secs
}

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

function Start-Tracker {
    Write-Host "Work Time Tracker Started..." -ForegroundColor Green
    Write-Host "Data Path: $DataFolder" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Cyan
    
    $data = Load-Data
    $isWorking = $false
    $sessionStart = $null
    $lastSaveTime = Get-Date

    while ($true) {
        $idleSeconds = [IdleTime]::GetIdleTime()
        $now = Get-Date
        $today = $now.ToString('yyyy-MM-dd')
        
        if ($null -eq $data.dailyStats) { $data.dailyStats = @{} }
        if (-not $data.dailyStats.ContainsKey($today)) {
            $data.dailyStats[$today] = @{ sessions = @(); totalSeconds = 0 }
        }
        
        if ($idleSeconds -lt $InactivityThreshold) {
            if (-not $isWorking) {
                $isWorking = $true
                $sessionStart = $now
                Write-Host "[$($now.ToString('HH:mm:ss'))] Session Start" -ForegroundColor Green
            }
        } else {
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
                    Save-Data $data
                }
                $sessionStart = $null
            }
        }
        
        if (($now - $lastSaveTime).TotalMinutes -gt $ReportIntervalMinutes) {
            if ($data.dailyStats[$today].sessions.Count -gt 0) {
                $totalSeconds = Generate-DailyReport $today $data.dailyStats[$today].sessions
                $data.dailyStats[$today].totalSeconds = $totalSeconds
                Save-Data $data
                Write-Host "[$($now.ToString('HH:mm:ss'))] Auto Save - Today Total: $(Format-Duration $totalSeconds)" -ForegroundColor Cyan
            }
            $lastSaveTime = $now
        }
        
        $displayInterval = if ($TestMode) { 10 } else { 60 }
        if ($now.Second % $displayInterval -eq 0) {
            if ($isWorking) {
                $currentDuration = ($now - $sessionStart).TotalSeconds
                $todayTotal = $data.dailyStats[$today].totalSeconds + $currentDuration
                Write-Host "[$($now.ToString('HH:mm:ss'))] Working - Current: $(Format-Duration $currentDuration) | Today: $(Format-Duration $todayTotal)" -ForegroundColor Green
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
