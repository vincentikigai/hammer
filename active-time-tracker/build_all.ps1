$ToolkitDir = "$env:ONEDRIVE\toolkit"

Write-Host "Creating toolkit directory at $ToolkitDir..." -ForegroundColor Cyan
if (-not (Test-Path $ToolkitDir)) {
    New-Item -ItemType Directory -Force -Path $ToolkitDir | Out-Null
}

# Ensure we run from the correct directory where the Go code lives
Set-Location "$PSScriptRoot\tracker-client"

Write-Host "Building for Windows (amd64, with console — for debugging)..."
$env:GOOS="windows"
$env:GOARCH="amd64"
go build -o "$ToolkitDir\active-time-tracker-console.exe" .

Write-Host "Building for Windows (amd64, hidden console — for startup/background)..."
$env:GOOS="windows"
$env:GOARCH="amd64"
go build -ldflags -H=windowsgui -o "$ToolkitDir\active-time-tracker.exe" .

Write-Host "Building for macOS (Intel)..."
$env:GOOS="darwin"
$env:GOARCH="amd64"
go build -o "$ToolkitDir\active-time-tracker-mac-intel" .

Write-Host "Building for macOS (Apple Silicon arm64)..."
$env:GOOS="darwin"
$env:GOARCH="arm64"
go build -o "$ToolkitDir\active-time-tracker-mac-arm64" .

Write-Host "Building for Linux (amd64)..."
$env:GOOS="linux"
$env:GOARCH="amd64"
go build -o "$ToolkitDir\active-time-tracker-linux" .

Write-Host "`n✓ All binaries successfully built and placed in $ToolkitDir" -ForegroundColor Green
