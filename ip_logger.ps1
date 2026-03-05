$interval = 10
$logfile = "ip_log.txt"

$currentIP = ""
$startTime = Get-Date

function Get-IP {
    try {
        (Invoke-RestMethod -Uri "https://api.ipify.org")
    } catch {
        return ""
    }
}

while ($true) {
    $ip = Get-IP
    $now = Get-Date

    if ($ip -ne $currentIP) {

        if ($currentIP -ne "") {
            $duration = $now - $startTime
            "$startTime -> $now  IP:$currentIP  Duration:$duration" | Out-File -Append $logfile
        }

        $currentIP = $ip
        $startTime = $now
        Write-Host "$now New IP: $ip"
    }

    Start-Sleep -Seconds $interval
}