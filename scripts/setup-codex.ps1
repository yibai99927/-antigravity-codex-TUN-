# setup-codex.ps1 - One-click setup for Codex Desktop local environment & restart
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Write-Host 'Configuring Codex Desktop isolated proxy & UWP Loopback...' -ForegroundColor Cyan

$codexDir = "$HOME\.codex"
if (!(Test-Path $codexDir)) { New-Item -ItemType Directory -Path $codexDir -Force | Out-Null }

$envContent = @'
HTTP_PROXY=http://127.0.0.1:7897
HTTPS_PROXY=http://127.0.0.1:7897
ALL_PROXY=http://127.0.0.1:7897
NO_PROXY=localhost,127.0.0.1,::1,192.168.*,10.*
http_proxy=http://127.0.0.1:7897
https_proxy=http://127.0.0.1:7897
all_proxy=http://127.0.0.1:7897
no_proxy=localhost,127.0.0.1,::1,192.168.*,10.*
'@

Set-Content -Path "$codexDir\.env" -Value $envContent -Encoding UTF8
Write-Host "[OK] Created local environment file: $codexDir\.env" -ForegroundColor Green

CheckNetIsolation.exe LoopbackExempt -a "-n=OpenAI.Codex_2p2nqsd0c76g0" 2>$null

Get-Process | Where-Object { $_.ProcessName -match 'chatgpt|codex' -and $_.ProcessName -ne 'codex-plus-plus-manager' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
Write-Host '[OK] Codex Desktop restarted successfully!' -ForegroundColor Green
