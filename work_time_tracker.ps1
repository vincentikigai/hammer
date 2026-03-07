# 工作时间统计程序 - 完全后台运行
# 保存为: WorkTimeTracker.ps1

# 配置
$dataFolder = "$env:USERPROFILE\WorkTimeData"
$logFile = "$dataFolder\work_log.json"
$inactivityThreshold = 180 # 3分钟无活动则结束会话（秒）

# 创建数据文件夹
if (-not (Test-Path $dataFolder)) {
    New-Item -ItemType Directory -Path $dataFolder | Out-Null
}

# 加载或初始化数据
function Load-Data {
    if (Test-Path $logFile) {
        $data = Get-Content $logFile -Raw | ConvertFrom-Json
        return $data
    } else {
        return @{
            sessions = @()
            dailyStats = @{}
        }
    }
}

# 保存数据
function Save-Data {
    param($data)
    $data | ConvertTo-Json -Depth 10 | Set-Content $logFile
}

# 获取最后输入时间
Add-Type @'
using System;
using System.Runtime.InteropServices;

public class IdleTime {
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
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

# 格式化时间
function Format-Duration {
    param($seconds)
    $hours = [Math]::Floor($seconds / 3600)
    $minutes = [Math]::Floor(($seconds % 3600) / 60)
    $secs = $seconds % 60
    return "{0:D2}:{1:D2}:{2:D2}" -f $hours, $minutes, $secs
}

# 生成日报
function Generate-DailyReport {
    param($date, $sessions)
    
    $totalSeconds = ($sessions | Measure-Object -Property duration -Sum).Sum
    $sessionCount = $sessions.Count
    
    $report = @"
=================================
工作时间日报 - $date
=================================
总工作时长: $(Format-Duration $totalSeconds)
工作会话数: $sessionCount

会话明细:
"@
    
    foreach ($session in $sessions) {
        $report += "`n$($session.start) - $($session.end) | $(Format-Duration $session.duration)"
    }
    
    $reportFile = "$dataFolder\报告_$($date -replace '/','-').txt"
    $report | Set-Content $reportFile
    
    return $totalSeconds
}

# 主循环
Write-Host "工作时间统计程序已启动（后台运行）" -ForegroundColor Green
Write-Host "数据保存位置: $dataFolder" -ForegroundColor Yellow
Write-Host "按 Ctrl+C 停止程序" -ForegroundColor Cyan

$data = Load-Data
$isWorking = $false
$sessionStart = $null
$lastSaveTime = Get-Date

while ($true) {
    $idleSeconds = [IdleTime]::GetIdleTime()
    $now = Get-Date
    $today = $now.ToString('yyyy-MM-dd')
    
    # 检查是否新的一天
    if ($data.dailyStats.ContainsKey($today) -eq $false) {
        $data.dailyStats[$today] = @{
            sessions = @()
            totalSeconds = 0
        }
    }
    
    # 判断工作状态
    if ($idleSeconds -lt $inactivityThreshold) {
        # 用户活跃
        if (-not $isWorking) {
            # 开始新会话
            $isWorking = $true
            $sessionStart = $now
            Write-Host "[$($now.ToString('HH:mm:ss'))] 开始工作会话" -ForegroundColor Green
        }
    } else {
        # 用户不活跃
        if ($isWorking) {
            # 结束会话
            $isWorking = $false
            $sessionEnd = $now.AddSeconds(-$inactivityThreshold)
            $duration = ($sessionEnd - $sessionStart).TotalSeconds
            
            if ($duration -gt 60) { # 至少工作1分钟才记录
                $session = @{
                    start = $sessionStart.ToString('HH:mm:ss')
                    end = $sessionEnd.ToString('HH:mm:ss')
                    duration = [int]$duration
                }
                
                $data.dailyStats[$today].sessions += $session
                $data.sessions += @{
                    date = $today
                    start = $sessionStart.ToString('yyyy-MM-dd HH:mm:ss')
                    end = $sessionEnd.ToString('yyyy-MM-dd HH:mm:ss')
                    duration = [int]$duration
                }
                
                Write-Host "[$($now.ToString('HH:mm:ss'))] 会话结束 - 时长: $(Format-Duration $duration)" -ForegroundColor Yellow
                
                # 保存数据
                Save-Data $data
            }
            
            $sessionStart = $null
        }
    }
    
    # 每小时自动保存并生成报告
    if (($now - $lastSaveTime).TotalMinutes -gt 60) {
        if ($data.dailyStats[$today].sessions.Count -gt 0) {
            $totalSeconds = Generate-DailyReport $today $data.dailyStats[$today].sessions
            $data.dailyStats[$today].totalSeconds = $totalSeconds
            Save-Data $data
            Write-Host "[$($now.ToString('HH:mm:ss'))] 自动保存 - 今日已工作: $(Format-Duration $totalSeconds)" -ForegroundColor Cyan
        }
        $lastSaveTime = $now
    }
    
    # 显示实时状态（每分钟）
    if ($now.Second -eq 0) {
        if ($isWorking) {
            $currentDuration = ($now - $sessionStart).TotalSeconds
            $todayTotal = $data.dailyStats[$today].totalSeconds + $currentDuration
            Write-Host "[$($now.ToString('HH:mm:ss'))] 工作中 - 本次: $(Format-Duration $currentDuration) | 今日: $(Format-Duration $todayTotal)" -ForegroundColor Green
        }
    }
    
    Start-Sleep -Seconds 1
}
