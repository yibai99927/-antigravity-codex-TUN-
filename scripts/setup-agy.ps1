param (
    [int]$ProxyPort = 7897
)

# setup-agy.ps1 - One-click setup for Antigravity CLI isolated proxy wrapper
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Write-Host "Configuring Antigravity CLI (agy) isolated proxy wrapper (Port: $ProxyPort)..." -ForegroundColor Cyan

$agyFunc = @"

# Antigravity CLI proxy wrapper (isolated execution, auto clean-up)
function agy {
    `$oldHttp = `$env:HTTP_PROXY
    `$oldHttps = `$env:HTTPS_PROXY
    `$oldAll = `$env:ALL_PROXY
    `$oldNo = `$env:NO_PROXY

    try {
        `$env:HTTP_PROXY = "http://127.0.0.1:$ProxyPort"
        `$env:HTTPS_PROXY = "http://127.0.0.1:$ProxyPort"
        `$env:ALL_PROXY = "http://127.0.0.1:$ProxyPort"
        `$env:NO_PROXY = "localhost,127.0.0.1,::1,192.168.*,10.*"

        & "`$HOME\AppData\Local\agy\bin\agy.exe" @args
    }
    finally {
        `$env:HTTP_PROXY = `$oldHttp
        `$env:HTTPS_PROXY = `$oldHttps
        `$env:ALL_PROXY = `$oldAll
        `$env:NO_PROXY = `$oldNo
    }
}
"@

$profiles = @(
    "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
    "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
)

foreach ($prof in $profiles) {
    $dir = Split-Path $prof -Parent
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (!(Test-Path $prof)) { New-Item -ItemType File -Path $prof -Force | Out-Null }
    
    $content = Get-Content $prof -Raw -ErrorAction SilentlyContinue
    if ($content -match "function agy") {
        # Update existing function
        $cleanedContent = [regex]::Replace($content, "(?ms)# Antigravity CLI proxy wrapper.*?\n\}", "")
        Set-Content -Path $prof -Value ($cleanedContent.TrimEnd() + "`n" + $agyFunc) -Encoding UTF8
        Write-Host "[OK] Updated agy wrapper with port $ProxyPort in: $prof" -ForegroundColor Green
    } else {
        Add-Content -Path $prof -Value $agyFunc -Encoding UTF8
        Write-Host "[OK] Added agy wrapper with port $ProxyPort to: $prof" -ForegroundColor Green
    }
}

Write-Host "Antigravity CLI configuration complete!" -ForegroundColor Cyan