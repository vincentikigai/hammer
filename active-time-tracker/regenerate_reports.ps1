param(
    [string]$DataFolder = $(if ($env:ACTIVE_TIME_FOLDER) { $env:ACTIVE_TIME_FOLDER } else { "$env:USERPROFILE\ActiveTime" }),
    [string[]]$Dates = $null
)

function Resolve-DataFolderPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded -eq $Path -and $Path -match '%[^%]+%') {
        foreach ($match in [regex]::Matches($Path, '%([^%]+)%')) {
            $varName = $match.Groups[1].Value
            $varValue = [Environment]::GetEnvironmentVariable($varName)
            if (-not [string]::IsNullOrWhiteSpace($varValue)) {
                $expanded = $expanded.Replace($match.Value, $varValue)
            }
        }
    }
    return $expanded
}

function Format-Duration {
    param($seconds)
    $totalSeconds = [int]$seconds
    $hours   = [Math]::Floor($totalSeconds / 3600)
    $minutes = [Math]::Floor(($totalSeconds % 3600) / 60)
    $secs    = $totalSeconds % 60
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$hours, [int]$minutes, [int]$secs
}

$DataFolder = Resolve-DataFolderPath $DataFolder

# --- Load sessions from ALL *session_log.json files (Go client + legacy) ---
$sessionLogFiles = Get-ChildItem -Path $DataFolder -Filter "*session_log.json" -ErrorAction SilentlyContinue

if ($sessionLogFiles.Count -eq 0) {
    Write-Host "x No session_log.json files found in $DataFolder" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($sessionLogFiles.Count) session log file(s):" -ForegroundColor Cyan
$allSessions = @()
foreach ($file in $sessionLogFiles) {
    Write-Host "  -> $($file.Name)" -ForegroundColor DarkCyan
    $jsonData = Get-Content $file.FullName -Raw | ConvertFrom-Json
    if ($jsonData.sessions) {
        $allSessions += @($jsonData.sessions)
    }
}
Write-Host "Total sessions loaded: $($allSessions.Count)" -ForegroundColor Cyan

# --- Determine which dates to regenerate ---
if ($null -ne $Dates -and $Dates.Count -gt 0) {
    $datesToFix = $Dates
} else {
    $datesToFix = @((Get-Date).ToString("yyyy-MM-dd"))
}

# --- Derive the folder-based report title (mirrors aggregator.go logic) ---
$folderName = Split-Path $DataFolder -Leaf
# Insert spaces into CamelCase (e.g. ScreenTime -> Screen Time)
$folderName = [regex]::Replace($folderName, '([a-z])([A-Z])', '$1 $2')
$reportTitle = "$folderName Report"

# --- Generate report for each requested date ---
foreach ($date in $datesToFix) {
    $dateSessions = @($allSessions | Where-Object { $_.date -eq $date })

    if ($dateSessions.Count -gt 0) {
        Write-Host "`nRegenerating '$date' with $($dateSessions.Count) session(s)..." -ForegroundColor Cyan

        $sortedSessions = @($dateSessions | Sort-Object { [datetime]::ParseExact($_.start, 'HH:mm:ss', $null) })
        $totalSeconds   = ($sortedSessions | ForEach-Object { [int]$_.duration } | Measure-Object -Sum).Sum
        $sessionCount   = $sortedSessions.Count

        $report  = "# $reportTitle - $date`n`n"
        $report += "- **Total Duration**: $(Format-Duration $totalSeconds)`n"
        $report += "- **Total Sessions**: $sessionCount`n`n"
        $report += "## Session Details`n`n"
        $report += "| Start | End | Duration |`n"
        $report += "| :--- | :--- | :--- |`n"

        for ($i = 0; $i -lt $sortedSessions.Count; $i++) {
            $current = $sortedSessions[$i]
            $start   = if ($current.start)       { $current.start }       else { "---" }
            $end     = if ($current.end)         { $current.end }         else { "---" }
            $hms     = if ($current.durationHms) { $current.durationHms } else { Format-Duration $current.duration }

            $report += "| $start | $end | **$hms** |`n"

            if ($i -lt ($sortedSessions.Count - 1)) {
                $next = $sortedSessions[$i + 1]
                try {
                    $eTime = [datetime]::ParseExact($current.end, 'HH:mm:ss', $null)
                    $sTime = [datetime]::ParseExact($next.start,  'HH:mm:ss', $null)
                    if ($sTime -le $eTime) { $sTime = $sTime.AddDays(1) }
                    $gap = ($sTime - $eTime).TotalSeconds
                    if ($gap -gt 0) {
                        $report += "| _Break_ | _$(Format-Duration $gap)_ | _Interruption_ |`n"
                    }
                } catch {}
            }
        }

        $reportFile = Join-Path $DataFolder "report_$($date -replace '/','-').md"
        $report | Set-Content $reportFile -Encoding UTF8
        Write-Host "  + Saved: $reportFile" -ForegroundColor Green
        Write-Host "  + Total: $(Format-Duration $totalSeconds), Sessions: $sessionCount" -ForegroundColor Green
    } else {
        Write-Host "`n! No sessions found for $date" -ForegroundColor Yellow
    }
}

Write-Host "`nAll done!" -ForegroundColor Green
