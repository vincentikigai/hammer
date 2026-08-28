# fix_reports.ps1
# Standalone script to regenerate and clean Work Time Markdown reports from primary JSON session log sources.

param(
    [string]$DataFolder = "",
    [string[]]$Dates = @("2026-08-16", "2026-08-17", "2026-08-18", "2026-08-19", "2026-08-20", "2026-08-21", "2026-08-22"),
    [int]$MinDurationSeconds = 0
)

# 1. Resolve Data Folder
if ([string]::IsNullOrWhiteSpace($DataFolder)) {
    if ($env:ACTIVE_TIME_FOLDER) {
        $DataFolder = $env:ACTIVE_TIME_FOLDER
    } else {
        $DataFolder = "C:\Users\sim\OneDrive\WorkTime"
        if (-not (Test-Path $DataFolder)) {
            $homeDir = [System.Environment]::GetFolderPath('UserProfile')
            $DataFolder = Join-Path $homeDir "ActiveTime"
        }
    }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Work Time Report Cleaner" -ForegroundColor Cyan
Write-Host " Target Directory: $DataFolder" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $DataFolder)) {
    Write-Host "Error: Target directory '$DataFolder' does not exist." -ForegroundColor Red
    exit 1
}

function Format-Hms([int]$seconds) {
    if ($seconds -lt 0) { $seconds = 0 }
    $h = [math]::Floor($seconds / 3600)
    $m = [math]::Floor(($seconds % 3600) / 60)
    $s = $seconds % 60
    return ("{0:00}:{1:00}:{2:00}" -f [int]$h, [int]$m, [int]$s)
}

function Parse-TimeToSeconds([string]$timeStr) {
    $timeStr = $timeStr.Trim()
    $parts = $timeStr.Split(':')
    if ($parts.Count -eq 3) {
        return ([int]$parts[0] * 3600) + ([int]$parts[1] * 60) + [int]$parts[2]
    }
    return 0
}

function Is-PrimarySessionLog([string]$filename) {
    $base = [System.IO.Path]::GetFileName($filename)
    if ($base -eq "session_log.json") { return $true }
    if ($base -eq "session_log_Precision-3640.json") { return $true }
    if ($base -eq "session_log_Vincents-MacBook-Pro.local.json") { return $true }
    if ($base -eq "session_log_Vincents-MBP.json") { return $true }
    if ($base -eq "session_log_Thinkpad-T470P.json") { return $true }

    # Reject conflict copy files containing spaces, special characters, quotes, or numbered suffixes
    if ($base -match '[ \(\)''"’`]') { return $false }
    if ($base -match '-\d+\.json$') { return $false }

    return $true
}

# Load all primary JSON session logs in the directory
$jsonFiles = Get-ChildItem -Path $DataFolder -Filter "session_log*.json" -ErrorAction SilentlyContinue | Where-Object { Is-PrimarySessionLog $_.FullName }

foreach ($date in $Dates) {
    $rawSessions = @()

    # 1. Read sessions from primary JSON logs for this date
    foreach ($file in $jsonFiles) {
        try {
            # Use .NET FileStream with FileShare.ReadWrite to bypass OneDrive file locks
            $fs = [System.IO.FileStream]::new($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = [System.IO.StreamReader]::new($fs)
            $content = $reader.ReadToEnd()
            $reader.Close()
            $fs.Close()

            if (-not $content) { continue }
            $jsonObj = $content | ConvertFrom-Json
            if ($jsonObj -and $jsonObj.sessions) {
                foreach ($sess in $jsonObj.sessions) {
                    if ($sess.date -eq $date) {
                        $startSec = Parse-TimeToSeconds $sess.start
                        $endSec = Parse-TimeToSeconds $sess.end
                        $durationSec = $endSec - $startSec

                        if ($durationSec -ge $MinDurationSeconds) {
                            $rawSessions += [PSCustomObject]@{
                                Start = $sess.start
                                End = $sess.end
                                StartSec = $startSec
                                EndSec = $endSec
                                DurationSec = $durationSec
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Host "  Warning: Could not read $($file.Name): $_" -ForegroundColor DarkYellow
        }
    }

    # 2. Also fallback to parsing existing markdown file if JSON yields nothing
    $fileName = "report_$date.md"
    $filePath = Join-Path $DataFolder $fileName
    if ($rawSessions.Count -eq 0 -and (Test-Path $filePath)) {
        $lines = Get-Content -Path $filePath -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '^\s*\|\s*(\d{2}:\d{2}:\d{2})\s*\|\s*(\d{2}:\d{2}:\d{2})\s*\|') {
                $start = $matches[1]
                $end = $matches[2]
                $startSec = Parse-TimeToSeconds $start
                $endSec = Parse-TimeToSeconds $end
                $durationSec = $endSec - $startSec

                if ($durationSec -ge $MinDurationSeconds) {
                    $rawSessions += [PSCustomObject]@{
                        Start = $start
                        End = $end
                        StartSec = $startSec
                        EndSec = $endSec
                        DurationSec = $durationSec
                    }
                }
            }
        }
    }

    $rawSessions = @($rawSessions)
    if ($rawSessions.Count -eq 0) {
        Write-Host "- $fileName : No sessions found for $date" -ForegroundColor Yellow
        continue
    }

    # Group sessions by StartSec and select the maximum EndSec
    $groupedByStart = $rawSessions | Group-Object -Property StartSec
    $uniqueSessions = @()
    foreach ($group in $groupedByStart) {
        $best = $group.Group | Sort-Object -Property EndSec -Descending | Select-Object -First 1
        $uniqueSessions += $best
    }

    # Force array type in PowerShell!
    $sortedSessions = @($uniqueSessions | Sort-Object -Property StartSec)
    $totalSessionsCount = $sortedSessions.Count

    # Calculate total duration
    $totalDurationSec = 0
    foreach ($s in $sortedSessions) {
        $totalDurationSec += $s.DurationSec
    }
    $totalDurationHms = Format-Hms $totalDurationSec

    # Rebuild Markdown
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Work Time Report - $date")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- **Total Duration**: $totalDurationHms")
    [void]$sb.AppendLine("- **Total Sessions**: $totalSessionsCount")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Session Details")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Start | End | Duration |")
    [void]$sb.AppendLine("| :--- | :--- | :--- |")

    for ($i = 0; $i -lt $sortedSessions.Count; $i++) {
        $curr = $sortedSessions[$i]
        $durationHms = Format-Hms $curr.DurationSec
        [void]$sb.AppendLine("| $($curr.Start) | $($curr.End) | **$durationHms** |")

        if ($i -lt ($sortedSessions.Count - 1)) {
            $next = $sortedSessions[$i + 1]
            $breakSec = $next.StartSec - $curr.EndSec
            if ($breakSec -gt 0) {
                $breakHms = Format-Hms $breakSec
                [void]$sb.AppendLine("| _Break_ | _${breakHms}_ | _Interruption_ |")
            }
        }
    }

    # Write cleaned report back to file
    Set-Content -Path $filePath -Value $sb.ToString() -Encoding UTF8
    Write-Host "+ $fileName : Fixed! Written $($totalSessionsCount) session(s), Total Duration: $totalDurationHms" -ForegroundColor Green
}

Write-Host ""
Write-Host "Report cleanup complete!" -ForegroundColor Cyan
