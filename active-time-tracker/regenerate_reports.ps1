param(
    [string]$DataFolder = $(if ($env:ACTIVE_TIME_FOLDER) { $env:ACTIVE_TIME_FOLDER } else { "$env:USERPROFILE\ActiveTime" }),
    [string[]]$Dates = $null
)

function Resolve-DataFolderPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

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

# Helper: Convert seconds to HH:MM:SS
function Format-Duration {
    param($seconds)
    $totalSeconds = [int]$seconds
    $hours = [Math]::Floor($totalSeconds / 3600)
    $minutes = [Math]::Floor(($totalSeconds % 3600) / 60)
    $secs = $totalSeconds % 60
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$hours, [int]$minutes, [int]$secs
}

# Helper: Atomic JSON save
function Save-JsonFile {
    param($Path, $Data)
    $tempFile = "$Path.tmp"
    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding UTF8
    if (Test-Path $Path) { Remove-Item $Path -Force }
    Move-Item $tempFile $Path -Force
}

$DataFolder = Resolve-DataFolderPath $DataFolder

# Load session log
$sessionLogFile  = Join-Path $DataFolder "session_log.json"

if (-not (Test-Path $sessionLogFile)) {
    Write-Host "✗ session_log.json not found at $DataFolder" -ForegroundColor Red
    exit 1
}

$jsonData = Get-Content $sessionLogFile -Raw | ConvertFrom-Json
$allSessions = @($jsonData.sessions)

# Dates to regenerate
if ($null -ne $Dates -and $Dates.Count -gt 0) {
    $datesToFix = $Dates
} else {
    $datesToFix = @((Get-Date).ToString("yyyy-MM-dd")) # Default to today if nothing provided
}

foreach ($date in $datesToFix) {
    $dateSessions = @($allSessions | Where-Object { $_.date -eq $date })
    
    if ($dateSessions.Count -gt 0) {
        Write-Host "Regenerating for $date with $($dateSessions.Count) sessions..." -ForegroundColor Cyan
        
        # Sort sessions
        $sortedSessions = @($dateSessions | Sort-Object { [datetime]::ParseExact($_.start, 'HH:mm:ss', $null) })
        
        # Calculate totals
        $totalSeconds = ($sortedSessions | ForEach-Object { [int]$_.duration } | Measure-Object -Sum).Sum
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
                    if ($sTime -le $eTime) { $sTime = $sTime.AddDays(1) }
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
        Write-Host "  ✓ Report saved (Total: $(Format-Duration $totalSeconds), Sessions: $sessionCount)" -ForegroundColor Green
    } else {
        Write-Host "⚠ No sessions found for $date" -ForegroundColor Yellow
    }
}

Write-Host "`n✓ All done!" -ForegroundColor Green
