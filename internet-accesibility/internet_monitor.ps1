# ============================================================
#  Internet / VPN Monitor — PowerShell 5.1 Compatible
#  Sends Windows 11 toast notification when internet drops
# ============================================================
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Programmatic Emoji "Lights" (prevents mojibake in script file)
$L_GREEN  = [char]::ConvertFromUtf32(0x1F7E2) # 🟢
$L_YELLOW = [char]::ConvertFromUtf32(0x1F7E1) # 🟡
$L_RED    = [char]::ConvertFromUtf32(0x1F534) # 🔴

# ── SINGLE INSTANCE CHECK ─────────────────────────────────────
$mutexName  = "Global\InternetMonitor_SingleInstance_Vincent"
$createdNew = $false
$mutex      = New-Object System.Threading.Mutex($false, $mutexName, [ref]$createdNew)

if (-not $createdNew) {
    Write-Host "  >> ERROR: Another instance of Internet Monitor is already running." -ForegroundColor Red
    Write-Host "  >> Please close the existing instance before starting a new one."
    exit
}
# ─────────────────────────────────────────────────────────────

# ── CONFIG ───────────────────────────────────────────────────
$GLOBAL_TARGET  = "google.com" # Primary/Global target
$LOCAL_TARGET   = "baidu.com"  # Fallback/Local target
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
        [string]$Message,
        [string]$Type = "Warning" # Info, Warning, Error
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $balloon                 = New-Object System.Windows.Forms.NotifyIcon
    $balloon.Icon            = if ($Type -eq "Error") { [System.Drawing.SystemIcons]::Error } elseif ($Type -eq "Warning") { [System.Drawing.SystemIcons]::Warning } else { [System.Drawing.SystemIcons]::Information }
    $balloon.BalloonTipTitle = $Title
    $balloon.BalloonTipText  = $Message
    $balloon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::$Type
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
        [string]$Message,
        [string]$Type = "Warning"
    )

    if ($UseBurntToast) {
        try {
            # Use specific emoji in BurntToast text if needed, but Title already has it
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
    
    # Optional: could add sound/color customizations here via XML
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Internet Monitor").Show($toast)
}

function Notify {
    param(
        [string]$Title, 
        [string]$Message, 
        [string]$Type = "Warning"
    )

    Write-Host "  >> Sending notification: $Title"

    # Try toast, fallback to balloon
    $toastSent = $false
    try {
        Send-Toast -Title $Title -Message $Message -Type $Type
        $toastSent = $true
        Write-Host "  >> Toast sent OK"
    } catch {
        Write-Host "  >> Toast failed: $($_.Exception.Message)"
    }

    if (-not $toastSent) {
        try {
            Send-BalloonTip -Title $Title -Message $Message -Type $Type
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
Write-Host "  Global Target : $GLOBAL_TARGET"
Write-Host "  Local Target  : $LOCAL_TARGET"
Write-Host "  Interval      : ${INTERVAL}s"
Write-Host "  Threshold     : $FAIL_THRESHOLD failures"
Write-Host "============================================"
Write-Host ""
Write-Host ">> Sending TEST notification now..."
Notify -Title "$L_GREEN Internet Monitor Started" -Message "Monitoring connectivity. Global: $GLOBAL_TARGET | Local: $LOCAL_TARGET" -Type "Info"
Write-Host ">> If you saw a notification, everything is working!"
Write-Host ""

# ── Main loop ────────────────────────────────────────────────
$currentState = "Connected" # Connected, GlobalDown, InternetDown

try {
    while ($true) {

        $pingGlobal = Test-Connection -ComputerName $GLOBAL_TARGET -Count 1 -Quiet -ErrorAction SilentlyContinue
        $pingLocal  = $false
        
        if (-not $pingGlobal) {
            $pingLocal = Test-Connection -ComputerName $LOCAL_TARGET -Count 1 -Quiet -ErrorAction SilentlyContinue
        }
        
        $ts    = Get-Date -Format "HH:mm:ss"
        $state = "Connected"
        $color = "Green"
        
        if (-not $pingGlobal) {
            if ($pingLocal) {
                $state = "GlobalDown"
                $color = "Yellow"
            } else {
                $state = "InternetDown"
                $color = "Red"
            }
        }

        if ($state -eq "Connected") {
            $failCount = 0
            if ($currentState -ne "Connected") {
                Write-Host "[$ts] $L_GREEN Connection Restored" -ForegroundColor Green
                Notify -Title "$L_GREEN Internet Restored" -Message "Connection to $GLOBAL_TARGET is back online." -Type "Info"
                $currentState = "Connected"
            } else {
                Write-Host "[$ts] $L_GREEN Connected (Primary: $GLOBAL_TARGET)" -ForegroundColor Green
            }
        } else {
            $failCount++
            $emoji = if ($state -eq "GlobalDown") { $L_YELLOW } else { $L_RED }
            Write-Host "[$ts] $emoji State: $state | Failures: $failCount/$FAIL_THRESHOLD" -ForegroundColor $color
            
            if ($failCount -ge $FAIL_THRESHOLD -and $currentState -ne $state) {
                if ($state -eq "GlobalDown") {
                    Notify -Title "$L_YELLOW Global Internet Not Reachable" -Message "Google is down, but Baidu is reachable. Possible VPN issue." -Type "Warning"
                } else {
                    Notify -Title "$L_RED Internet Interrupted" -Message "Both Google and Baidu are unreachable. Internet may be down." -Type "Error"
                }
                $currentState = $state
            }
        }

        Start-Sleep -Seconds $INTERVAL
    }
} finally {
    if ($mutex) {
        # Release if we own it (though exit usually clears it)
        try { $mutex.ReleaseMutex() } catch {}
        $mutex.Dispose()
    }
}
