$interval = 10
$logfile = "ip_log.csv"

$currentIP = ""
$startTime = Get-Date

function Get-IP {
    try {
        (Invoke-RestMethod -Uri "https://api.ipify.org")
    } catch {
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

if (!(Test-Path $logfile)) {
    "start_time,end_time,ip,duration_seconds,last_latency_ms" |
        Out-File $logfile -Encoding UTF8
}

while ($true) {

    $ip = Get-IP
    $now = Get-Date
    $latency = Get-Ping

    if ($ip -ne $currentIP) {

        if ($currentIP -ne "") {

            $duration = ($now - $startTime).TotalSeconds

            "$startTime,$now,$currentIP,$duration,$latency" |
                Out-File -Append $logfile -Encoding UTF8
        }

        $currentIP = $ip
        $startTime = $now
        Write-Host "$now  New IP: $ip  latency:$latency ms"
    }

    Start-Sleep -Seconds $interval
}