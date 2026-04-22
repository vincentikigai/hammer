#Requires -Version 5.1
# Work Time Tracker - Enhanced Version (Supports Test Mode, Startup Recovery & Readable JSON)
# Save as: active_state_logger.ps1

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

$LegacyLogFile  = "$DataFolder\work_log.json"
$SessionLogFile = "$DataFolder\session_log.json"
$ActiveStateFile= "$DataFolder\active_state.json"
$CsvFile        = "$DataFolder\session_history.csv"

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

# Helper: Sum session durations for a given date
function Get-DayTotal {
    param($sessions, $date)
    $daySessions = @($sessions | Where-Object { $_.date -eq $date })
    if ($daySessions.Count -eq 0) { return 0 }
    return ($daySessions | ForEach-Object { [int]$_.duration } | Measure-Object -Sum).Sum
}

function Save-JsonFile {
    param($Path, $Data)
    try {
        $tempFile = "$Path.tmp"
        $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding UTF8 -ErrorAction Stop
        if (Test-Path $Path) { Remove-Item $Path -Force -ErrorAction Stop }
        Move-Item $tempFile $Path -Force -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Failed to save $($Path): $_" -ForegroundColor Red
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

function Save-ActiveState {
    param($activeSession)
    Save-JsonFile -Path $ActiveStateFile -Data @{ activeSession = $activeSession }
}

function Save-Sessions {
    param($sessions)
    Save-JsonFile -Path $SessionLogFile -Data @{ sessions = $sessions }
    if ($sessions -and $sessions.Count -gt 0) {
        try {
            $sessions | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            Write-Host "[SAVE] Session log & CSV saved successfully." -ForegroundColor Cyan
        } catch {}
    }
}

# Load or init data
function Load-Data {
    $data = @{
        sessions      = @()
        activeSession = $null
    }

    # 1. Check Legacy Migration (work_log.json -> session_log.json + active_state.json)
    if (Test-Path $LegacyLogFile) {
        $content = Get-Content $LegacyLogFile -Raw
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            $raw = $content | ConvertFrom-Json
            $legacyData = ConvertTo-Hashtable $raw

            if ($legacyData.sessions)      { $data.sessions      = $legacyData.sessions }
            if ($legacyData.activeSession) { $data.activeSession = $legacyData.activeSession }

            Save-Sessions $data.sessions
            Save-ActiveState $data.activeSession

            # Backup & remove legacy file
            Rename-Item -Path $LegacyLogFile -NewName "work_log.json.legacy_backup" -Force
            Write-Host "[MIGRATION] legacy work_log.json migrated to session_log.json!" -ForegroundColor Magenta
        }
    } else {
        # 2. Normal loading
        if (Test-Path $SessionLogFile) {
            $raw = Get-Content $SessionLogFile -Raw | ConvertFrom-Json
            if ($raw -and $raw.sessions) { $data.sessions = ConvertTo-Hashtable $raw.sessions }
        }
        if (Test-Path $ActiveStateFile) {
            $raw = Get-Content $ActiveStateFile -Raw | ConvertFrom-Json
            if ($raw -and $raw.activeSession) { $data.activeSession = ConvertTo-Hashtable $raw.activeSession }
        }
    }
    return $data
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

    $totalSeconds = ($sortedSessions | ForEach-Object { [int]$_.duration } | Measure-Object -Sum).Sum
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
        $end   = if ($current.end)   { $current.end }   else { "---" }
        $hms   = if ($current.durationHms) { $current.durationHms } else { Format-Duration $current.duration }

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
        $duration = ($now - $sessionStart).TotalSeconds
        if ($duration -gt 1) {
            $today = $now.ToString('yyyy-MM-dd')
            $session = [Ordered]@{
                date        = $today
                start       = $sessionStart.ToString('HH:mm:ss')
                end         = $now.ToString('HH:mm:ss')
                duration    = [int]$duration
                durationHms = Format-Duration $duration
            }
            $data.sessions += $session
            Write-Host "`n[SIG] Final session saved." -ForegroundColor Yellow
        }
    }
    $data.activeSession = $null
    Save-Sessions $data.sessions
    Save-ActiveState $data.activeSession

    # Final report update
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $todaySessions = @($data.sessions | Where-Object { $_.date -eq $today })
    if ($todaySessions.Count -gt 0) {
        Generate-DailyReport $today $todaySessions | Out-Null
    }

    Write-Host "[SIG] Tracker stopped." -ForegroundColor Red
}

# Main Application
function Start-Tracker {
    Write-Host "Work Time Tracker Started..." -ForegroundColor Green
    Write-Host "Data Path: $DataFolder" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Cyan

    $data = Load-Data

    $isWorking    = $false
    $sessionStart = $null

    # --- Recovery Logic ---
    if ($data.activeSession) {
        $recSession = $data.activeSession
        $today = $recSession.date

        # Calculate gap from last heartbeat
        $lastHbStr  = "$($recSession.date) $($recSession.lastHeartbeatTime)"
        $lastHbTime = [DateTime]::ParseExact($lastHbStr, 'yyyy-MM-dd HH:mm:ss', $null)
        $gapSeconds = ((Get-Date) - $lastHbTime).TotalSeconds

        if ($gapSeconds -le $InactivityThreshold) {
            Write-Host ">>> Brief interruption detected ($([math]::Round($gapSeconds))s). Seamlessly resuming session from $($recSession.startTime)..." -ForegroundColor Magenta
            $startStr     = "$($recSession.date) $($recSession.startTime)"
            $sessionStart = [DateTime]::ParseExact($startStr, 'yyyy-MM-dd HH:mm:ss', $null)
            $isWorking    = $true
            Write-Host ">>> Session seamlessly resumed." -ForegroundColor Green
        } else {
            Write-Host ">>> Long gap detected. Finalizing unended session from $($recSession.startTime)..." -ForegroundColor Magenta
            $session = [Ordered]@{
                date        = $today
                start       = $recSession.startTime
                end         = $recSession.lastHeartbeatTime
                duration    = [int]$recSession.duration
                durationHms = Format-Duration $recSession.duration
            }
            $data.sessions += $session
            $data.activeSession = $null

            Save-Sessions $data.sessions
            Save-ActiveState $data.activeSession

            # Update report after recovery
            $todaySessions = @($data.sessions | Where-Object { $_.date -eq $today })
            Generate-DailyReport $today $todaySessions | Out-Null
            Write-Host ">>> Session finalized." -ForegroundColor Green
        }
    }
    $lastSaveTime = Get-Date
    $lastLoopTime = Get-Date

    # Interruption Trap
    trap { Stop-TrackerGracefully $data $isWorking $sessionStart; break }

    while ($true) {
        $now   = Get-Date
        $today = $now.ToString('yyyy-MM-dd')

        # --- Sleep/Suspend Detection (F1 in flowchart) ---
        $loopGap = ($now - $lastLoopTime).TotalSeconds
        if ($loopGap -gt $InactivityThreshold) {
            # System was suspended - time jumped unexpectedly
            if ($isWorking) {
                # Retroactively end session at last known awake time (F2→F3)
                $sessionEnd = $lastLoopTime
                $duration   = ($sessionEnd - $sessionStart).TotalSeconds
                if ($duration -gt 1) {
                    $endDate = $sessionStart.ToString('yyyy-MM-dd')
                    $session = [Ordered]@{
                        date        = $endDate
                        start       = $sessionStart.ToString('HH:mm:ss')
                        end         = $sessionEnd.ToString('HH:mm:ss')
                        duration    = [int]$duration
                        durationHms = Format-Duration $duration
                    }
                    $data.sessions += $session
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Sleep detected! Session ended retroactively at $($sessionEnd.ToString('HH:mm:ss')) ($(Format-Duration $duration))" -ForegroundColor Magenta
                }
                $isWorking    = $false
                $sessionStart = $null
                $data.activeSession = $null
                Save-Sessions $data.sessions
                Save-ActiveState $data.activeSession

                $todaySessions = @($data.sessions | Where-Object { $_.date -eq $endDate })
                Generate-DailyReport $endDate $todaySessions | Out-Null
            }
        }
        $lastLoopTime = $now

        $idleSeconds = [IdleTime]::GetIdleTime()

        if ($idleSeconds -lt $InactivityThreshold) {
            # Active
            if (-not $isWorking) {
                $isWorking    = $true
                $sessionStart = $now
                Write-Host "[$($now.ToString('HH:mm:ss'))] Session Start" -ForegroundColor Green
            }

            # --- Midnight Split Check ---
            if ($isWorking -and $sessionStart.Date -ne $now.Date) {
                $oldDate    = $sessionStart.ToString('yyyy-MM-dd')
                $sessionEnd = $sessionStart.Date.AddDays(1).AddSeconds(-1)
                $duration   = ($sessionEnd - $sessionStart).TotalSeconds

                $session = [Ordered]@{
                    date        = $oldDate
                    start       = $sessionStart.ToString('HH:mm:ss')
                    end         = "23:59:59"
                    duration    = [int]$duration
                    durationHms = Format-Duration $duration
                }
                $data.sessions += $session
                $sessionStart = $now.Date # 00:00:00 today
                Write-Host "[$($now.ToString('HH:mm:ss'))] Midnight Split - New day session started." -ForegroundColor Magenta
                Save-Sessions $data.sessions
                
                # Update the final report for the old day
                $oldDaySessions = @($data.sessions | Where-Object { $_.date -eq $oldDate })
                Generate-DailyReport $oldDate $oldDaySessions | Out-Null
            }

            # Heartbeat Save (every 30 seconds)
            if ($now.Second % 30 -eq 0) {
                $duration = ($now - $sessionStart).TotalSeconds
                $data.activeSession = [Ordered]@{
                    date              = $today
                    startTime         = $sessionStart.ToString('HH:mm:ss')
                    lastHeartbeatTime = $now.ToString('HH:mm:ss')
                    duration          = [int]$duration
                    durationHms       = Format-Duration $duration
                }
                Save-ActiveState $data.activeSession
            }

        } else {
            # Inactive
            if ($isWorking) {
                $isWorking  = $false
                $sessionEnd = $now.AddSeconds(-$InactivityThreshold)
                $duration   = ($sessionEnd - $sessionStart).TotalSeconds
                if ($duration -gt 1) {
                    $session = [Ordered]@{
                        date        = $today
                        start       = $sessionStart.ToString('HH:mm:ss')
                        end         = $sessionEnd.ToString('HH:mm:ss')
                        duration    = [int]$duration
                        durationHms = Format-Duration $duration
                    }
                    if ($null -eq $data.sessions) { $data.sessions = @() }
                    $data.sessions += $session

                    Write-Host "[$($now.ToString('HH:mm:ss'))] Session End - Duration: $(Format-Duration $duration)" -ForegroundColor Yellow
                    $data.activeSession = $null
                    $todaySessions = @($data.sessions | Where-Object { $_.date -eq $today })
                    Save-Sessions $data.sessions
                    Save-ActiveState $data.activeSession
                    Generate-DailyReport $today $todaySessions | Out-Null
                }
                $sessionStart = $null
            }
        }

        # Periodic report saving
        if (($now - $lastSaveTime).TotalMinutes -gt $ReportIntervalMinutes) {
            $todaySessions = @($data.sessions | Where-Object { $_.date -eq $today })
            if ($todaySessions.Count -gt 0) {
                Generate-DailyReport $today $todaySessions | Out-Null
                Write-Host "[$($now.ToString('HH:mm:ss'))] Auto Report updated." -ForegroundColor Cyan
            }
            $lastSaveTime = $now
        }

        # Display status
        $displayInterval = if ($TestMode) { 10 } else { 60 }
        if ($now.Second % $displayInterval -eq 0) {
            if ($isWorking) {
                $currentDuration = ($now - $sessionStart).TotalSeconds
                $todayTotal = (Get-DayTotal $data.sessions $today) + $currentDuration
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
