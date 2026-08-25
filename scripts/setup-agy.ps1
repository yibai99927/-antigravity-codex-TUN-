# setup-agy.ps1 - One-click setup for Antigravity CLI isolated proxy wrapper
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Write-Host 'Configuring Antigravity CLI (agy) isolated proxy wrapper...' -ForegroundColor Cyan

$agyFunc = @'

# Antigravity CLI proxy wrapper (isolated execution, auto clean-up)
function agy {
    $oldHttp = $env:HTTP_PROXY
    $oldHttps = $env:HTTPS_PROXY
    $oldAll = $env:ALL_PROXY
    $oldNo = $env:NO_PROXY

    try {
        $env:HTTP_PROXY = "http://127.0.0.1:7897"
        $env:HTTPS_PROXY = "http://127.0.0.1:7897"
        $env:ALL_PROXY = "http://127.0.0.1:7897"
        $env:NO_PROXY = "localhost,127.0.0.1,::1,192.168.*,10.*"

        & "$HOME\AppData\Local\agy\bin\agy.exe" @args
    }
    finally {
        $env:HTTP_PROXY = $oldHttp
        $env:HTTPS_PROXY = $oldHttps
        $env:ALL_PROXY = $oldAll
        $env:NO_PROXY = $oldNo
    }
}
'@

$profiles = @(
    "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
    "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
)

foreach ($prof in $profiles) {
    $dir = Split-Path $prof -Parent
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (!(Test-Path $prof)) { New-Item -ItemType File -Path $prof -Force | Out-Null }
    $content = Get-Content $prof -Raw -ErrorAction SilentlyContinue
    if ($content -notmatch 'function agy') {
        Add-Content -Path $prof -Value $agyFunc -Encoding UTF8
        Write-Host "[OK] Added agy wrapper to: $prof" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Already configured in: $prof" -ForegroundColor Yellow
    }
}

Write-Host 'Antigravity CLI configuration complete!' -ForegroundColor Cyan
