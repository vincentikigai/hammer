# Requires Run as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script needs to be run as Administrator."
    Pause
    exit
}

# Define Profiles here
# PrefixLength 24 is equivalent to Subnet Mask 255.255.255.0
$Profiles = @(
    @{ Name = "DHCP (Automatic)"; Type = "DHCP" },
    @{ Name = "Home Network"; Type = "Static"; IP = "192.168.1.100"; PrefixLength = 24; Gateway = "192.168.1.1"; DNS = @("8.8.8.8", "1.1.1.1") },
    @{ Name = "Work Network"; Type = "Static"; IP = "10.0.0.50"; PrefixLength = 24; Gateway = "10.0.0.1"; DNS = @("10.0.0.2") }
)

Write-Host "============================" -ForegroundColor Cyan
Write-Host "   IP Address Switcher      " -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Available Network Adapters:" -ForegroundColor Yellow
$Adapters = Get-NetAdapter | Where-Object Status -eq "Up"
$i = 1
foreach ($Adapter in $Adapters) {
    Write-Host "  [$i] $($Adapter.Name) ($($Adapter.InterfaceDescription))"
    $i++
}

$AdapterChoice = Read-Host "`nSelect an adapter (1-$($Adapters.Count))"
$SelectedAdapter = $Adapters[[int]$AdapterChoice - 1]

if (-not $SelectedAdapter) {
    Write-Error "Invalid selection."
    exit
}

Write-Host "`nAvailable Profiles:" -ForegroundColor Yellow
$j = 1
foreach ($Profile in $Profiles) {
    if ($Profile.Type -eq "DHCP") {
        Write-Host "  [$j] $($Profile.Name) - DHCP"
    } else {
        Write-Host "  [$j] $($Profile.Name) - Static ($($Profile.IP)/$($Profile.PrefixLength))"
    }
    $j++
}

$ProfileChoice = Read-Host "`nSelect a profile (1-$($Profiles.Count))"
$SelectedProfile = $Profiles[[int]$ProfileChoice - 1]

if (-not $SelectedProfile) {
    Write-Error "Invalid selection."
    exit
}

Write-Host "`nApplying Profile: $($SelectedProfile.Name) to adapter '$($SelectedAdapter.Name)'..." -ForegroundColor Cyan

try {
    if ($SelectedProfile.Type -eq "DHCP") {
        Set-NetIPInterface -InterfaceAlias $SelectedAdapter.Name -Dhcp Enabled -ErrorAction Stop
        Set-DnsClientServerAddress -InterfaceAlias $SelectedAdapter.Name -ResetServerAddresses -ErrorAction Stop
        Write-Host "Set to DHCP successfully." -ForegroundColor Green
    } else {
        # Clear existing IP addresses (silently continue if it fails)
        Remove-NetIPAddress -InterfaceAlias $SelectedAdapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        
        # Set new static IP
        New-NetIPAddress -InterfaceAlias $SelectedAdapter.Name -IPAddress $SelectedProfile.IP -PrefixLength $SelectedProfile.PrefixLength -DefaultGateway $SelectedProfile.Gateway -ErrorAction Stop | Out-Null
        
        if ($SelectedProfile.DNS) {
            Set-DnsClientServerAddress -InterfaceAlias $SelectedAdapter.Name -ServerAddresses $SelectedProfile.DNS -ErrorAction Stop
        }
        Write-Host "Set to Static IP ($($SelectedProfile.IP)) successfully." -ForegroundColor Green
    }
} catch {
    Write-Error "An error occurred while changing the IP address: $_"
}

Write-Host "`nCurrent Configuration for '$($SelectedAdapter.Name)':" -ForegroundColor Yellow
Get-NetIPAddress -InterfaceAlias $SelectedAdapter.Name -AddressFamily IPv4 | Select-Object IPAddress, PrefixLength | Format-Table -AutoSize

Write-Host "`nPress any key to exit..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
