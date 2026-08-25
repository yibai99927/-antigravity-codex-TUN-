# check-status.ps1 - Diagnostic script for AI tools proxy & network connectivity
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Windows AI Tools Proxy & Network Health Check" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Check Clash Proxy Port
$proxyPort = 7897
$proxySocket = Get-NetTCPConnection -LocalPort $proxyPort -State Listen -ErrorAction SilentlyContinue
if ($proxySocket) {
    Write-Host "[OK] Clash Verge 代理服务正在监听端口 $proxyPort" -ForegroundColor Green
} else {
    Write-Host "[WARN] 未检测到端口 $proxyPort 正在监听，请确认代理软件是否已启动！" -ForegroundColor Yellow
}

# 2. Check Codex UWP Loopback Exemption
$uwpExempt = CheckNetIsolation.exe LoopbackExempt -s | Out-String
if ($uwpExempt -match "openai.codex") {
    Write-Host "[OK] Codex Desktop (OpenAI.Codex) 已在 Windows UWP 回环豁免名单中" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Codex Desktop 未加入 UWP 回环豁免名单！" -ForegroundColor Red
}

# 3. Check .codex/.env
$codexEnvPath = "$HOME\.codex\.env"
if (Test-Path $codexEnvPath) {
    Write-Host "[OK] 已检测到局部配置文件 $codexEnvPath" -ForegroundColor Green
} else {
    Write-Host "[FAIL] 未找到 $codexEnvPath！" -ForegroundColor Red
}

# 4. Check Antigravity CLI PowerShell Profile
$psProfile = "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
if ((Test-Path $psProfile) -and ((Get-Content $psProfile -Raw) -match "function agy")) {
    Write-Host "[OK] PowerShell 7 Profile 已配置 agy 智能代理函数" -ForegroundColor Green
} else {
    Write-Host "[FAIL] PowerShell 7 Profile 未检测到 agy 代理函数配置" -ForegroundColor Red
}

# 5. Check Active Sockets for ChatGPT & Codex
Write-Host "`n--- 当前正在建立的 Socket 连接 ---" -ForegroundColor Cyan
$processes = Get-Process | Where-Object { $_.ProcessName -match "chatgpt|codex|agy" -and $_.ProcessName -ne "codex-plus-plus-manager" }
if ($processes) {
    Get-NetTCPConnection | Where-Object { $_.OwningProcess -in $processes.Id -and $_.RemotePort -eq $proxyPort } | ForEach-Object {
        $pName = ($processes | Where-Object { $_.Id -eq $_.OwningProcess }).ProcessName
        Write-Host "  [$pName (PID $($_.OwningProcess))] 本地 $($_.LocalAddress):$($_.LocalPort) -> 代理 $($_.RemoteAddress):$($_.RemotePort) (状态: $($_.State))" -ForegroundColor Green
    }
} else {
    Write-Host "  暂无正在运行的 AI 工具进程" -ForegroundColor Gray
}

Write-Host "==================================================" -ForegroundColor Cyan