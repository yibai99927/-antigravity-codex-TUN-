param (
    [int]$ProxyPort = 7897
)

# setup-codex.ps1 - One-click setup for Codex Desktop local environment & restart
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Write-Host "Configuring Codex Desktop isolated proxy (Port: $ProxyPort) & UWP Loopback..." -ForegroundColor Cyan

# 1. Write ~/.codex/.env
$codexDir = "$HOME\.codex"
if (!(Test-Path $codexDir)) { New-Item -ItemType Directory -Path $codexDir -Force | Out-Null }

$envContent = @"
HTTP_PROXY=http://127.0.0.1:$ProxyPort
HTTPS_PROXY=http://127.0.0.1:$ProxyPort
ALL_PROXY=http://127.0.0.1:$ProxyPort
NO_PROXY=localhost,127.0.0.1,::1,192.168.*,10.*
http_proxy=http://127.0.0.1:$ProxyPort
https_proxy=http://127.0.0.1:$ProxyPort
all_proxy=http://127.0.0.1:$ProxyPort
no_proxy=localhost,127.0.0.1,::1,192.168.*,10.*
"@

Set-Content -Path "$codexDir\.env" -Value $envContent -Encoding UTF8
Write-Host "[OK] Created/Updated local environment file: $codexDir\.env (Port $ProxyPort)" -ForegroundColor Green

# 2. UWP Loopback Exemption
Write-Host "Applying UWP Loopback exemption for Codex Desktop..." -ForegroundColor Cyan
CheckNetIsolation.exe LoopbackExempt -a "-n=OpenAI.Codex_2p2nqsd0c76g0" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] UWP Loopback exemption applied successfully!" -ForegroundColor Green
} else {
    Write-Host "[NOTE] If administrator prompt is required, please enable UWP Loopback in your proxy client GUI (e.g. Clash Verge)." -ForegroundColor Yellow
}

# 3. Clean restart
Write-Host "Restarting Codex Desktop processes..." -ForegroundColor Cyan
Get-Process | Where-Object { $_.ProcessName -match "chatgpt|codex" -and $_.ProcessName -ne "codex-plus-plus-manager" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
Write-Host "[OK] Codex Desktop restarted successfully!" -ForegroundColor Green