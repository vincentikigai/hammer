param(
    [string]$DataFolder = "C:\Users\sim\WorkTimeData"
)

# Helper: Convert seconds to HH:MM:SS
function Format-Duration {
    param($seconds)
    $totalSeconds = [int]$seconds
    $hours = [Math]::Floor($totalSeconds / 3600)
    $minutes = [Math]::Floor(($totalSeconds % 3600) / 60)
    $secs = $totalSeconds % 60
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$hours, [int]$minutes, [int]$secs
}

# Load JSON data
$logFile = Join-Path $DataFolder "work_log.json"
$jsonData = Get-Content $logFile -Raw | ConvertFrom-Json
$allSessions = $jsonData.sessions

# Dates to regenerate
$datesToFix = @("2026-04-05", "2026-04-06", "2026-04-07", "2026-04-08", "2026-04-09", "2026-04-10")

foreach ($date in $datesToFix) {
    $dateSessions = @($allSessions | Where-Object { $_.date -eq $date })
    
    if ($dateSessions.Count -gt 0) {
        Write-Host "Regenerating report for $date with $($dateSessions.Count) sessions" -ForegroundColor Cyan
        
        # Sort sessions
        $sortedSessions = @($dateSessions | Sort-Object { [datetime]::ParseExact($_.start, 'HH:mm:ss', $null) })
        
        # Calculate totals
        $totalSeconds = ($sortedSessions | Measure-Object -Property duration -Sum).Sum
        $sessionCount = $sortedSessions.Count
        
        # Build markdown report
        $report = "# Work Time Report - $date`n`n"
        $report += "- **Total Duration**: $(Format-Duration $totalSeconds)`n"
        $report += "- **Total Sessions**: $sessionCount`n`n"
        $report += "## Session Details`n`n"
        $report += "| Start | End | Duration |`n"
        $report += "| :--- | :--- | :--- |`n"
        
        for ($i = 0; $i -lt $sortedSessions.Count; $i++) {
            $current = $sortedSessions[$i]
            $start = if ($current.start) { $current.start } else { "---" }
            $end = if ($current.end) { $current.end } else { "---" }
            $hms = if ($current.durationHms) { $current.durationHms } else { Format-Duration $current.duration }
            
            $report += "| $start | $end | **$hms** |`n"
            
            # Add break if there's a gap
            if ($i -lt ($sortedSessions.Count - 1)) {
                $next = $sortedSessions[$i + 1]
                try {
                    $eTime = [datetime]::ParseExact($current.end, 'HH:mm:ss', $null)
                    $sTime = [datetime]::ParseExact($next.start, 'HH:mm:ss', $null)
                    # Handle same-day or next-day gap
                    if ($sTime -le $eTime) {
                        $sTime = $sTime.AddDays(1)
                    }
                    $gap = ($sTime - $eTime).TotalSeconds
                    if ($gap -gt 0) {
                        $report += "| _Break_ | _$(Format-Duration $gap)_ | _Interruption_ |`n"
                    }
                } catch {}
            }
        }
        
        # Save report
        $reportFile = Join-Path $DataFolder "report_$($date -replace '/','-').md"
        $report | Set-Content $reportFile -Encoding UTF8
        Write-Host "✓ Report saved: $reportFile (Total: $(Format-Duration $totalSeconds), Sessions: $sessionCount)" -ForegroundColor Green
    } else {
        Write-Host "⚠ No sessions found for $date" -ForegroundColor Yellow
    }
}

Write-Host "`n✓ All reports regenerated successfully!" -ForegroundColor Green
