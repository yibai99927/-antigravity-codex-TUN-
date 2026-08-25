# Non-TUN Proxy Guide for AI Developer Tools on Windows

[**简体中文**](./README.md) | [**English**](./README_EN.md)

> **Goal**: On Windows 11, resolve connectivity and remote control issues **without enabling TUN mode** (using local proxy ports such as `7897`, `7890`, or `10809` via Clash, Mihomo, v2ray, etc.):
> 1. **Codex Desktop**: Mobile remote control (iOS / Android) failing to connect to Desktop Codex.
> 2. **Antigravity CLI (`agy`)**: OAuth login failure and Gemini model API connection timeouts.
>
> **Zero Global Pollution**: Does not modify Windows global environment variables, keeping terminal tools (`git`, `pip`, `python`, `npm`, SSH) 100% clean and unaffected.

---

> ⚠️ **Configurable Proxy Port Notice**:
> The default port `7897` used across this guide corresponds to **Clash Verge (Mihomo)**.
> **Please replace it with your actual local proxy port**:
> * **Clash Verge (Mihomo)** default: `7897`
> * **Clash for Windows / Clash Core** default: `7890`
> * **v2rayN / Xray** HTTP proxy default: `10809`
> * **SagerNet / Sing-box** default: `2080` / `7890`
> 
> *All bundled scripts support dynamic port parameters, e.g., `.\setup-agy.ps1 -ProxyPort 7890`.*

---

## Table of Contents

- [1. Problem Analysis & Root Cause](#1-problem-analysis--root-cause)
  - [1.1 TUN Mode vs. Standard System Proxy](#11-tun-mode-vs-standard-system-proxy)
  - [1.2 Codex Desktop Mobile Remote Control Breakdown](#12-codex-desktop-mobile-remote-control-breakdown)
  - [1.3 Antigravity CLI Login Breakdown](#13-antigravity-cli-login-breakdown)
- [2. Step-by-Step Non-TUN Solutions](#2-step-by-step-non-tun-solutions)
  - [2.1 Codex Desktop Setup](#21-codex-desktop-setup)
  - [2.2 Antigravity CLI Setup](#22-antigravity-cli-setup)
- [3. Automated Scripts](#3-automated-scripts)
- [4. Persistence & FAQ](#4-persistence--faq)

---

## 1. Problem Analysis & Root Cause

### 1.1 TUN Mode vs. Standard System Proxy

| Mode | Mechanism | Scope | Pros & Cons |
| :--- | :--- | :--- | :--- |
| **TUN Mode** | Creates a virtual network adapter (L3 driver) to intercept all system traffic (TCP/UDP/DNS). | All software automatically routes through proxy. | High compatibility, but risks routing conflicts with VMs (VMware/Hyper-V), mesh VPNs (Tailscale/ZeroTier), or corporate/campus VPNs. |
| **Standard System Proxy** | Sets WinINET registry proxy (`127.0.0.1:<PORT>`). | Only GUI apps actively querying WinINET (e.g. Chrome/Edge). | Zero network driver overhead, but CLI tools, UWP sandboxed apps, and raw WebSocket/UDP daemons fail by default. |

---

### 1.2 Codex Desktop Mobile Remote Control Breakdown

Codex Desktop on Windows consists of two components:
1. **Frontend GUI (`ChatGPT.exe`)**: Packaged as a Windows Store / UWP (MSIX AppContainer) application.
2. **Background Daemon (`codex.exe`)**: Win32 daemon that maintains a persistent WebSocket (`wss://chatgpt.com/backend-api/...`) with OpenAI cloud relay to handle mobile commands.

#### Blockers:
* **UWP Loopback Isolation**: Windows AppContainer sandbox blocks UWP apps from connecting to `127.0.0.1`. Even with system proxy enabled, frontend requests to `127.0.0.1:<PORT>` are dropped with permission errors by the Windows kernel.
* **Daemon Ignores WinINET**: The Win32 `codex.exe` daemon reads environment variables (`HTTP_PROXY`) rather than WinINET registry settings. Without environment configuration, it attempts direct Wi-Fi connections that are blocked by firewalls/GFW (`SynSent` timeout).

---

### 1.3 Antigravity CLI Login Breakdown

Antigravity CLI (`agy.exe`) is a Go-compiled binary:
1. **Go Network Stack Behavior**: The Go standard library `net/http` only recognizes environment variables (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`), completely ignoring Windows registry system proxies.
2. **OAuth Token Exchange**: After browser authentication, `agy.exe` itself sends backend POST requests to `oauth2.googleapis.com` and quota checks to `cloudcode-pa.googleapis.com`. Without proxy environment variables, direct connections time out.
3. **Local Language Server Protection**: `agy.exe` communicates with an internal Language Server on `127.0.0.1:42111`. `NO_PROXY` must include `localhost,127.0.0.1` to prevent internal traffic from being misrouted to the proxy port.

---

## 2. Step-by-Step Non-TUN Solutions

### 2.1 Codex Desktop Setup

#### Step 1: Grant UWP Loopback Exemption
Run in Administrator PowerShell (or check **UWP Loopback** ➔ `OpenAI.Codex` in Clash Verge):
```powershell
CheckNetIsolation.exe LoopbackExempt -a "-n=OpenAI.Codex_2p2nqsd0c76g0"
```

#### Step 2: Create Local Environment File (Zero Global Pollution)
Create `~/.codex/.env` (*replace `<PORT>` with your proxy port, e.g. `7897` or `7890`*):
```ini
HTTP_PROXY=http://127.0.0.1:<PORT>
HTTPS_PROXY=http://127.0.0.1:<PORT>
ALL_PROXY=http://127.0.0.1:<PORT>
NO_PROXY=localhost,127.0.0.1,::1,192.168.*,10.*
http_proxy=http://127.0.0.1:<PORT>
https_proxy=http://127.0.0.1:<PORT>
all_proxy=http://127.0.0.1:<PORT>
no_proxy=localhost,127.0.0.1,::1,192.168.*,10.*
```

#### Step 3: Terminate Stale Processes & Restart App
```powershell
Get-Process | Where-Object { $_.ProcessName -match "chatgpt|codex" -and $_.ProcessName -ne "codex-plus-plus-manager" } | Stop-Process -Force
Start-Process "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
```

---

### 2.2 Antigravity CLI Setup

Add a `try...finally` isolated wrapper function in your PowerShell profile so proxy variables are only mounted during `agy` execution and instantly cleaned up upon exit:

#### Profile Locations:
* PowerShell 7: `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
* Windows PowerShell 5.1: `$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`

#### Function Code (*replace `<PORT>` with your proxy port*):
```powershell
function agy {
    # 1. Backup existing environment variables
    $oldHttp = $env:HTTP_PROXY
    $oldHttps = $env:HTTPS_PROXY
    $oldAll = $env:ALL_PROXY
    $oldNo = $env:NO_PROXY

    try {
        # 2. Inject proxy variables only during this invocation
        $env:HTTP_PROXY = "http://127.0.0.1:<PORT>"
        $env:HTTPS_PROXY = "http://127.0.0.1:<PORT>"
        $env:ALL_PROXY = "http://127.0.0.1:<PORT>"
        $env:NO_PROXY = "localhost,127.0.0.1,::1,192.168.*,10.*"

        # 3. Transparently forward all arguments and subcommands
        & "$HOME\AppData\Local\agy\bin\agy.exe" @args
    }
    finally {
        # 4. Instantly revert variables on exit
        $env:HTTP_PROXY = $oldHttp
        $env:HTTPS_PROXY = $oldHttps
        $env:ALL_PROXY = $oldAll
        $env:NO_PROXY = $oldNo
    }
}
```

#### Git Bash Profile (`~/.bash_profile`):
```bash
function agy() {
    HTTP_PROXY="http://127.0.0.1:<PORT>" \
    HTTPS_PROXY="http://127.0.0.1:<PORT>" \
    ALL_PROXY="http://127.0.0.1:<PORT>" \
    NO_PROXY="localhost,127.0.0.1,::1,192.168.*,10.*" \
    "$HOME/AppData/Local/agy/bin/agy.exe" "$@"
}
```

---

## 3. Automated Scripts

All scripts in the [`scripts/`](./scripts/) directory support custom port parameters:

| Script | Default Run | Custom Port Example | Description |
| :--- | :--- | :--- | :--- |
| [`scripts/check-status.ps1`](./scripts/check-status.ps1) | `.\check-status.ps1` | `.\check-status.ps1 -ProxyPort 7890` | Verifies UWP loopback, active sockets, and proxy reachability. |
| [`scripts/setup-codex.ps1`](./scripts/setup-codex.ps1) | `.\setup-codex.ps1` | `.\setup-codex.ps1 -ProxyPort 7890` | Configures `.codex/.env` and restarts Codex Desktop instances. |
| [`scripts/setup-agy.ps1`](./scripts/setup-agy.ps1) | `.\setup-agy.ps1` | `.\setup-agy.ps1 -ProxyPort 7890` | Injects isolated `agy` proxy functions into PowerShell & Git Bash. |

---

## 4. Persistence & FAQ

### Q1: Will computer reboot or app updates overwrite these settings?
* **Reboots**: 100% persistent. PowerShell profiles, `~/.codex/.env`, and UWP Loopback registry rules remain intact across reboots.
* **Updates**: `agy update` and Codex Desktop upgrades only replace binary files, leaving user directories and profile scripts untouched.

### Q2: Why not set `HTTP_PROXY` in Windows global user environment variables?
* Setting global proxy variables causes terminal tools (`pip`, `npm`, `git`, python scripts) to throw `Connection Refused` errors whenever the proxy client is temporarily closed.
* Isolated injection ensures zero side-effects and maximum developer stability.