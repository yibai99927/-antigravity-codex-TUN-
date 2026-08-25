param (
    [int]$ProxyPort = 7897
)

# check-status.ps1 - Diagnostic script for AI tools proxy & network connectivity
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Windows AI Tools Proxy & Network Health Check" -ForegroundColor Cyan
Write-Host "   Target Proxy Port: $ProxyPort" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Check Proxy Port
$proxySocket = Get-NetTCPConnection -LocalPort $ProxyPort -State Listen -ErrorAction SilentlyContinue
if ($proxySocket) {
    Write-Host "[OK] 本地代理服务正在监听端口 $ProxyPort" -ForegroundColor Green
} else {
    Write-Host "[WARN] 未检测到端口 $ProxyPort 正在监听！如果您使用的是其他端口（如 7890/10809），请运行: .\check-status.ps1 -ProxyPort <端口号>" -ForegroundColor Yellow
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
    $envContent = Get-Content $codexEnvPath -Raw
    Write-Host "[OK] 已检测到局部配置文件 $codexEnvPath" -ForegroundColor Green
    if ($envContent -match ":$ProxyPort") {
        Write-Host "     -> 端口配置匹配目标端口 $ProxyPort" -ForegroundColor Green
    } else {
        Write-Host "     -> [提示] 配置文件中的端口与当前检测端口 $ProxyPort 不一致" -ForegroundColor Yellow
    }
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
Write-Host "`n--- 当前建立的 Socket 连接 (目标端口 $ProxyPort) ---" -ForegroundColor Cyan
$processes = Get-Process | Where-Object { $_.ProcessName -match "chatgpt|codex|agy" -and $_.ProcessName -ne "codex-plus-plus-manager" }
if ($processes) {
    $connections = Get-NetTCPConnection | Where-Object { $_.OwningProcess -in $processes.Id -and $_.RemotePort -eq $ProxyPort }
    if ($connections) {
        $connections | ForEach-Object {
            $pName = ($processes | Where-Object { $_.Id -eq $_.OwningProcess }).ProcessName
            Write-Host "  [$pName (PID $($_.OwningProcess))] 本地 $($_.LocalAddress):$($_.LocalPort) -> 代理 $($_.RemoteAddress):$($_.RemotePort) (状态: $($_.State))" -ForegroundColor Green
        }
    } else {
        Write-Host "  未检测到与端口 $ProxyPort 建立的连接" -ForegroundColor Gray
    }
} else {
    Write-Host "  暂无正在运行的 AI 工具进程" -ForegroundColor Gray
}

Write-Host "==================================================" -ForegroundColor Cyan