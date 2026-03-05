# ============================================================
#  Internet / VPN Monitor — PowerShell 5.1 Compatible
#  Sends Windows 11 toast notification when internet drops
# ============================================================

# ── CONFIG ───────────────────────────────────────────────────
$TARGET         = "1.1.1.1"   # Cloudflare DNS
$INTERVAL       = 10           # seconds between checks
$FAIL_THRESHOLD = 2            # consecutive failures before alerting
# ─────────────────────────────────────────────────────────────

# Auto-install BurntToast if missing (PowerShell 5.1, installs to CurrentUser)
$UseBurntToast = $false
try {
    Import-Module BurntToast -ErrorAction Stop
    $UseBurntToast = $true
    Write-Host "  >> BurntToast module loaded: toasts will use BurntToast"
} catch {
    Write-Host "  >> BurntToast not found. Attempting to install to CurrentUser from PSGallery..."
    try {
        # Ensure TLS 1.2 for PSGallery access
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Ensure NuGet provider is available (may prompt once)
        try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue } catch {}

        # Install BurntToast
        Install-Module -Name BurntToast -Scope CurrentUser -Force -ErrorAction Stop

        # Try import again
        Import-Module BurntToast -ErrorAction Stop
        $UseBurntToast = $true
        Write-Host "  >> BurntToast installed and loaded."
    } catch {
        Write-Host "  >> BurntToast install/load failed: $($_.Exception.Message)"
        Write-Host "  >> Falling back to WinRT/balloon notifications."
    }
}

$failCount    = 0
$notifiedDown = $false

# Balloon tip notification (most reliable on all Windows versions)
function Send-BalloonTip {
    param(
        [string]$Title,
        [string]$Message
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $balloon                 = New-Object System.Windows.Forms.NotifyIcon
    $balloon.Icon            = [System.Drawing.SystemIcons]::Warning
    $balloon.BalloonTipTitle = $Title
    $balloon.BalloonTipText  = $Message
    $balloon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
    $balloon.Visible         = $true
    $balloon.ShowBalloonTip(8000)

    # Must stay alive long enough to show
    Start-Sleep -Seconds 2
    $balloon.Visible = $false
    $balloon.Dispose()
}

# Toast notification (Windows 10/11) - prefer BurntToast if installed
function Send-Toast {
    param(
        [string]$Title,
        [string]$Message
    )

    if ($UseBurntToast) {
        try {
            New-BurntToastNotification -Text $Title, $Message
            return
        } catch {
            Write-Host "  >> BurntToast failed: $($_.Exception.Message). Falling back to WinRT toast."
        }
    }

    Add-Type -AssemblyName System.Runtime.WindowsRuntime

    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    $template = @"
<toast duration="long">
  <visual>
    <binding template="ToastGeneric">
      <text>$Title</text>
      <text>$Message</text>
    </binding>
  </visual>
</toast>
"@

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($template)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Internet Monitor").Show($toast)
}

function Notify {
    param([string]$Title, [string]$Message)

    Write-Host "  >> Sending notification: $Title"

    # Try toast, fallback to balloon
    $toastSent = $false
    try {
        Send-Toast -Title $Title -Message $Message
        $toastSent = $true
        Write-Host "  >> Toast sent OK"
    } catch {
        Write-Host "  >> Toast failed: $($_.Exception.Message)"
    }

    if (-not $toastSent) {
        try {
            Send-BalloonTip -Title $Title -Message $Message
            Write-Host "  >> Balloon tip sent OK"
        } catch {
            Write-Host "  >> Balloon tip also failed: $($_.Exception.Message)"
        }
    }
}

# ── Startup: test notification immediately ───────────────────
Write-Host ""
Write-Host "============================================"
Write-Host "  Internet Monitor (PowerShell 5.1)"
Write-Host "  Target   : $TARGET"
Write-Host "  Interval : ${INTERVAL}s"
Write-Host "  Threshold: $FAIL_THRESHOLD failures"
Write-Host "============================================"
Write-Host ""
Write-Host ">> Sending TEST notification now..."
Notify -Title "Internet Monitor Started" -Message "Monitoring $TARGET every ${INTERVAL}s. You will be alerted if connection drops."
Write-Host ">> If you saw a notification, everything is working!"
Write-Host ""

# ── Main loop ────────────────────────────────────────────────
while ($true) {

    $ping = Test-Connection -ComputerName $TARGET -Count 1 -Quiet -ErrorAction SilentlyContinue
    $ts   = Get-Date -Format "HH:mm:ss"

    Write-Host "[$ts] Ping result: $ping  | failCount: $failCount | notifiedDown: $notifiedDown"

    if ($ping) {
        $failCount = 0

        if ($notifiedDown) {
            Notify -Title "Internet Restored" -Message "Connection to $TARGET is back online."
            $notifiedDown = $false
        }

    } else {
        $failCount++
        Write-Host "  >> FAIL #$failCount detected"

        if ($failCount -ge $FAIL_THRESHOLD -and -not $notifiedDown) {
            Notify -Title "Internet Disconnected" -Message "No response from $TARGET after $failCount attempts. VPN may be down."
            $notifiedDown = $true
        }
    }

    Start-Sleep -Seconds $INTERVAL
}
