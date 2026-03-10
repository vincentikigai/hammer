param(
    [switch]$Dummy  # run in dummy/test mode
)

Write-Host "Script started" -ForegroundColor Green

$interval = 10
$logfile = "ip_log.csv"

$currentIP = ""
$currentDNS = ""
$startTime = Get-Date

# Check if we're resuming from a previous session
$resuming = $false
if ((Test-Path $logfile) -and ((Get-Item $logfile).Length -gt 0)) {
    Write-Host "Resuming from previous session. Old records will be preserved." -ForegroundColor Cyan
    $resuming = $true
}

# dummy data globals
$dummyIPs = @('1.1.1.1','2.2.2.2','3.3.3.3','4.4.4.4')
$dummyIndex = 0

function Update-LastRecord {
    param(
        [DateTime]$endTime,
        [double]$duration
    )
    $lines = Get-Content $logfile -Encoding UTF8
    if ($lines.Count -gt 1) {
        $lastLine = $lines[-1]
        $parts = $lastLine -split ','
        if ($endTime) {
            $parts[1] = $endTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        if ($duration -ge 0) {
            $parts[4] = $duration.ToString()
        }
        $lines[-1] = $parts -join ','
        $lines | Out-File $logfile -Encoding UTF8
    }
}

function Get-IP {
    if ($Dummy) {
        # cycle through a small list of fake IPs to force change events
        $ip = $dummyIPs[$dummyIndex]
        $dummyIndex = ($dummyIndex + 1) % $dummyIPs.Count
        return $ip
    }

    try {
        $ip = (Invoke-RestMethod -Uri "https://api.ipify.org")
        Write-Host "Got IP: $ip" -ForegroundColor Cyan
        return $ip
    } catch {
        Write-Host "Failed to get IP: $_" -ForegroundColor Red
        return ""
    }
}

function Get-Ping {
    try {
        $ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -ErrorAction Stop
        return $ping.ResponseTime
    } catch {
        return "timeout"
    }
}

function Get-DNS {
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | 
            Where-Object {$_.ServerAddresses.Count -gt 0} |
            Select-Object -ExpandProperty ServerAddresses |
            Select-Object -First 2
        return ($dnsServers -join ",")
    } catch {
        return "unknown"
    }
}

if (!(Test-Path $logfile) -or ((Get-Item $logfile).Length -eq 0)) {
    Write-Host "Creating new log file with header." -ForegroundColor Cyan
    "start_time,end_time,ip,dns_servers,duration_minutes,last_latency_ms" |
        Out-File $logfile -Encoding UTF8
}

# Resume from previous session if applicable
if ($resuming) {
    $lines = Get-Content $logfile -Encoding UTF8
    if ($lines.Count -gt 1) {
        $lastLine = $lines[-1]
        $parts = $lastLine -split ','
        if ([string]::IsNullOrEmpty($parts[1])) {  # end_time is empty
            $currentIP = $parts[2]
            $currentDNS = $parts[3]
            $startTime = [DateTime]::Parse($parts[0])
            Write-Host "Resumed from incomplete record: IP=$currentIP, DNS=$currentDNS, Start=$startTime" -ForegroundColor Cyan
        }
    }
}

try {
    while ($true) {

        $ip = Get-IP
        $dns = Get-DNS
        $now = Get-Date
        $latency = Get-Ping
        
        Write-Host "Current IP: $ip | Previous IP: $currentIP | DNS: $dns" -ForegroundColor Yellow

        if ($ip -ne $currentIP -or $dns -ne $currentDNS) {
            Write-Host "Change detected: IP changed from [$currentIP] to [$ip], DNS changed from [$currentDNS] to [$dns]" -ForegroundColor Green

            if ($currentIP -ne "") {
                $duration = [math]::Round(($now - $startTime).TotalMinutes, 2)
                Update-LastRecord -endTime $now -duration $duration
                Write-Host "Updated previous record with end time and duration" -ForegroundColor Green
            }

            # Save new record with empty end_time
            "$now,,$ip,$dns,,$latency" | Out-File -Append $logfile -Encoding UTF8
            Write-Host "Saved new record to file" -ForegroundColor Green

            $currentIP = $ip
            $currentDNS = $dns
            $startTime = $now
            Write-Host "$now  New IP: $ip  DNS: $dns  latency:$latency ms"
        } else {
            # Update current record duration
            $duration = [math]::Round(($now - $startTime).TotalMinutes, 2)
            Update-LastRecord -duration $duration
            Write-Host "Updated current record duration: $duration minutes" -ForegroundColor Cyan
        }

        Start-Sleep -Seconds $interval
    }
}
finally {
    # Save the current session if script is terminated
    if ($currentIP -ne "") {
        $now = Get-Date
        $duration = [math]::Round(($now - $startTime).TotalMinutes, 2)
        Update-LastRecord -endTime $now -duration $duration
        Write-Host "Script terminated. Updated final record with end time and duration." -ForegroundColor Yellow
    }
}