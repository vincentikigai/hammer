#Requires -Version 5.1
# Work Time Tracker - Enhanced Version (Supports Test Mode, Startup Recovery & Readable JSON)
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

# Helper: Convert seconds to Time (HH:mm:ss)
function Format-Duration {
    param($seconds)
    $totalSeconds = [int]$seconds
    $hours = [Math]::Floor($totalSeconds / 3600)
    $minutes = [Math]::Floor(($totalSeconds % 3600) / 60)
    $secs = $totalSeconds % 60
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$hours, [int]$minutes, [int]$secs
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
    $defaultData = @{
        sessions = @()
        dailyStats = @{}
        activeSession = $null
    }
    if (Test-Path $logFile) {
        $content = Get-Content $logFile -Raw
        if ([string]::IsNullOrWhiteSpace($content)) { return $defaultData }
        $raw = $content | ConvertFrom-Json
        if ($null -eq $raw) { return $defaultData }
        $data = ConvertTo-Hashtable $raw
        # Ensure properties exist
        foreach ($key in $defaultData.Keys) {
            if (-not $data.ContainsKey($key)) { $data[$key] = $defaultData[$key] }
        }
        return $data
    } else {
        return $defaultData
    }
}

# Save data (with atomic writes, backup, and validation)
function Save-Data {
    param($data)
    try {
        # Backup existing file before save
        $backupFile = "$logFile.backup"
        if (Test-Path $logFile) {
            Copy-Item $logFile $backupFile -Force -ErrorAction SilentlyContinue
            Write-Host "[SAVE] Backup created at: $backupFile" -ForegroundColor Gray
        }
        
        # 1. Save JSON atomically using temp file
        $tempFile = "$logFile.tmp"
        $jsonContent = $data | ConvertTo-Json -Depth 10
        $jsonContent | Set-Content -Path $tempFile -Encoding UTF8 -ErrorAction Stop
        
        # Verify temp file was created
        if (-not (Test-Path $tempFile)) {
            throw "Temp file not created at $tempFile"
        }
        
        # Atomic replace: Move temp file to actual file
        [System.IO.File]::Move($tempFile, $logFile, $true)
        
        # Verify move succeeded
        if (-not (Test-Path $logFile)) {
            throw "Move to final location failed - file not found at $logFile"
        }
        
        Write-Host "[SAVE] JSON saved successfully (backup: $backupFile)" -ForegroundColor Cyan
        
        # 2. Save CSV (Export the flat sessions list)
        if ($data.sessions -and $data.sessions.Count -gt 0) {
            $csvFile = Join-Path $DataFolder "work_sessions.csv"
            # Convert Hashtables back to PSCustomObject for correct CSV export
            $data.sessions | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            Write-Host "[SAVE] CSV saved successfully." -ForegroundColor Cyan
        }
    } catch {
        Write-Host "[ERROR] Failed to save data: $_" -ForegroundColor Red
        # Cleanup temp file if it exists
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            Write-Host "[CLEANUP] Temp file removed." -ForegroundColor Yellow
        }
        # Don't exit - allow tracker to continue, data stays in memory
    }
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

# Daily report generation
function Generate-DailyReport {
    param($date, $sessions)
    if (-not $sessions) { return 0 }
    
    # Ensure sessions are sorted and treated as objects
    $objSessions = @($sessions | ForEach-Object { [PSCustomObject]$_ })
    $sortedSessions = @($objSessions | Sort-Object { $_.start })
    
    $totalSeconds = ($sortedSessions | Measure-Object -Property duration -Sum).Sum
    $sessionCount = $sortedSessions.Length
    
    # Markdown Header
    $report = "# Work Time Report - $date`n`n"
    $report += "- **Total Duration**: $(Format-Duration $totalSeconds)`n"
    $report += "- **Total Sessions**: $sessionCount`n`n"
    $report += "## Session Details`n`n"
    $report += "| Start | End | Duration |`n"
    $report += "| :--- | :--- | :--- |`n"
    
    for ($i = 0; $i -lt $sortedSessions.Count; $i++) {
        $current = $sortedSessions[$i]
        
        # Add Session Row
        $start = if ($current.start) { $current.start } else { "---" }
        $end = if ($current.end) { $current.end } else { "---" }
        $hms = if ($current.durationHms) { $current.durationHms } else { Format-Duration $current.duration }
        
        $report += "| $start | $end | **$hms** |`n"
        
        # Add Break Row
        if ($i -lt ($sortedSessions.Count - 1)) {
            $next = $sortedSessions[$i + 1]
            try {
                $eTime = [DateTime]([string]$current.end).Trim()
                $sTime = [DateTime]([string]$next.start).Trim()
                $gap = ($sTime - $eTime).TotalSeconds
                if ($gap -gt 0) {
                    $report += "| _Break_ | _$(Format-Duration $gap)_ | _Interruption_ |`n"
                }
            } catch {}
        }
    }
    
    $reportFile = "$DataFolder\report_$($date -replace '/','-').md"
    $report | Set-Content $reportFile -Encoding UTF8
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
            # Use Ordered Hashtable for readability
            $session = [Ordered]@{
                date     = $today
                start    = $sessionStart.ToString('HH:mm:ss')
                end      = $sessionEnd.ToString('HH:mm:ss')
                duration = [int]$duration
                durationHms = Format-Duration $duration
            }
            if ($null -eq $data.dailyStats.$today) { $data.dailyStats[$today] = [Ordered]@{ sessions = @(); totalSeconds = 0; totalHms = "00:00:00" } }
            $data.dailyStats[$today].sessions += $session
            $data.sessions += $session
            Write-Host "`n[SIG] Final session saved." -ForegroundColor Yellow
        }
    }
    $data.activeSession = $null # Clear heartbeat for clean exit
    Save-Data $data
    
    # Final report update
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($data.dailyStats[$today].sessions.Count -gt 0) {
        Generate-DailyReport $today $data.dailyStats[$today].sessions | Out-Null
    }
    
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
        Write-Host ">>> Recovering unclosed session from $($data.activeSession.startTime)..." -ForegroundColor Magenta
        $recSession = $data.activeSession
        $today = $recSession.date
        if ($null -eq $data.dailyStats.$today) { $data.dailyStats[$today] = [Ordered]@{ sessions = @(); totalSeconds = 0; totalHms = "00:00:00" } }
        
        $session = [Ordered]@{
            date     = $today
            start    = $recSession.startTime
            end      = $recSession.lastHeartbeatTime
            duration = [int]$recSession.duration
            durationHms = Format-Duration $recSession.duration
        }
        $data.dailyStats[$today].sessions += $session
        $data.sessions += $session
        $data.activeSession = $null
        Save-Data $data
        # Update report after recovery
        Generate-DailyReport $today $data.dailyStats[$today].sessions | Out-Null
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
        
        if ($null -eq $data.dailyStats) { $data.dailyStats = [Ordered]@{} }
        if (-not $data.dailyStats.ContainsKey($today)) {
            $data.dailyStats[$today] = [Ordered]@{ sessions = @(); totalSeconds = 0; totalHms = "00:00:00" }
        }
        
        if ($idleSeconds -lt $InactivityThreshold) {
            # Active
            if (-not $isWorking) {
                $isWorking = $true
                $sessionStart = $now
                Write-Host "[$($now.ToString('HH:mm:ss'))] Session Start" -ForegroundColor Green
            }
            
            # --- Midnight Split Check ---
            if ($isWorking -and $sessionStart.Date -ne $now.Date) {
                # Finalize old part
                $oldDate = $sessionStart.ToString('yyyy-MM-dd')
                $sessionEnd = $sessionStart.Date.AddDays(1).AddSeconds(-1)
                $duration = ($sessionEnd - $sessionStart).TotalSeconds
                
                $session = [Ordered]@{
                    date     = $oldDate
                    start    = $sessionStart.ToString('HH:mm:ss')
                    end      = "23:59:59"
                    duration = [int]$duration
                    durationHms = Format-Duration $duration
                }
                
                # Save old part
                if (-not $data.dailyStats.ContainsKey($oldDate)) { $data.dailyStats[$oldDate] = [Ordered]@{ sessions = @(); totalSeconds = 0; totalHms = "00:00:00" } }
                $data.dailyStats[$oldDate].sessions += $session
                $data.sessions += $session
                
                # Start new part
                $sessionStart = $now.Date # 00:00:00 today
                Write-Host "[$($now.ToString('HH:mm:ss'))] Midnight Split - New day session started." -ForegroundColor Magenta
                Save-Data $data
            }
            
            # Heartbeat Save (every 30 seconds)
            if ($now.Second % 30 -eq 0) {
                $duration = ($now - $sessionStart).TotalSeconds
                $data.activeSession = [Ordered]@{
                    date = $today
                    startTime = $sessionStart.ToString('HH:mm:ss')
                    lastHeartbeatTime = $now.ToString('HH:mm:ss')
                    duration = [int]$duration
                    durationHms = Format-Duration $duration
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
                    $session = [Ordered]@{
                        date     = $today
                        start    = $sessionStart.ToString('HH:mm:ss')
                        end      = $sessionEnd.ToString('HH:mm:ss')
                        duration = [int]$duration
                        durationHms = Format-Duration $duration
                    }
                    $data.dailyStats[$today].sessions += $session
                    if ($null -eq $data.sessions) { $data.sessions = @() }
                    $data.sessions += $session
                    
                    # Update Total
                    $sum = ($data.dailyStats[$today].sessions | ForEach-Object { $_.duration } | Measure-Object -Sum).Sum
                    $data.dailyStats[$today].totalSeconds = [int]$sum
                    $data.dailyStats[$today].totalHms = Format-Duration $sum
                    
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Session End - Duration: $(Format-Duration $duration)" -ForegroundColor Yellow
                    $data.activeSession = $null
                    Save-Data $data
                    # Update report immediately after saving session
                    Generate-DailyReport $today $data.dailyStats[$today].sessions | Out-Null
                }
                $sessionStart = $null
            }
        }
        
        # Periodic report saving
        if (($now - $lastSaveTime).TotalMinutes -gt $ReportIntervalMinutes) {
            if ($data.dailyStats[$today].sessions.Count -gt 0) {
                $totalSeconds = Generate-DailyReport $today $data.dailyStats[$today].sessions
                $data.dailyStats[$today].totalSeconds = [int]$totalSeconds
                $data.dailyStats[$today].totalHms = Format-Duration $totalSeconds
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
