# Windows 下 AI 工具免 TUN 代理配置与排坑指南

[**简体中文**](./README.md) | [**English**](./README_EN.md)

> **核心目标**：在 Windows 11 环境下，完全**不开启 TUN 模式**（使用 Clash / Mihomo / v2ray 等本地代理端口，如 `7897` 或 `7890`），解决以下两大难题：
> 1. **Codex Desktop**：手机端（iOS / Android）无法远程控制桌面端 Codex。
> 2. **Antigravity CLI (`agy`)**：无法完成 Google OAuth 登录认证及大模型调用。
>
> 且**不修改 Windows 系统全局环境变量**，对日常命令行（`git`、`pip`、`python`、`npm`、SSH 连远程服务器等）实现**绝对零污染、零干扰**。

---

> ⚠️ **代理端口声明（非固定写死）**：
> 文档与脚本中默认使用的 `7897` 为 **Clash Verge (Mihomo)** 的常见本地混合端口。
> **请根据您实际使用的代理客户端端口进行替换**：
> * **Clash Verge (Mihomo)** 常见端口：`7897`
> * **Clash for Windows / Clash Core** 常见端口：`7890`
> * **v2rayN / Xray** 常见 HTTP 端口：`10809`
> * **SagerNet / Sing-box** 常见端口：`2080` / `7890`
> 
> *脚本均支持动态传入端口参数，例如：`.\setup-agy.ps1 -ProxyPort 7890`*。

---

## 目录

- [一、 现象与底层根因剖析](#一-现象与底层根因剖析)
  - [1.1 为什么 TUN 模式能用，而普通代理会失效？](#11-为什么-tun-模式能用而普通代理会失效)
  - [1.2 Codex Desktop 手机远程失败机理](#12-codex-desktop-手机远程失败机理)
  - [1.3 Antigravity CLI 登录与模型调用失败机理](#13-antigravity-cli-登录与模型调用失败机理)
- [二、 免 TUN 解决方案实战](#二-免-tun-解决方案实战)
  - [2.1 Codex Desktop 独立代理方案](#21-codex-desktop-独立代理方案)
  - [2.2 Antigravity CLI 独立代理方案](#22-antigravity-cli-独立代理方案)
- [三、 自动化运维脚本说明](#三-自动化运维脚本说明)
- [四、 持久化机制与常见 FAQ](#四-持久化机制与常见-faq)

---

## 一、 现象与底层根因剖析

### 1.1 为什么 TUN 模式能用，而普通代理会失效？

| 模式 | 工作原理 | 适用范围 | 优缺点 |
| :--- | :--- | :--- | :--- |
| **TUN 模式** | 创建虚拟网卡（L3 网络层驱动），强制接管系统所有出站流量（TCP/UDP/DNS） | 所有软件无需配置代理即可走分流 | 兼容性高，但可能与虚拟机（VMware/Hyper-V）、内网穿透（Tailscale/ZeroTier）或校园网/企业 VPN 产生路由冲突 |
| **普通系统代理** | 仅在 Windows 注册表设置 HTTP 代理（`127.0.0.1:<PORT>`） | 仅主动读取 WinINET 的图形应用（如 Chrome/Edge） | 对系统网络无侵入，但命令行工具、UWP 沙盒应用和非标准长连接默认无法走代理 |

---

### 1.2 Codex Desktop 手机远程失败机理

Codex Desktop（Windows 版本）由两部分组成：
1. **前端图形界面 (`ChatGPT.exe`)**：以 Windows Store / UWP (MSIX AppContainer) 格式封装。
2. **后台常驻服务 (`codex.exe`)**：Win32 守护进程，负责与 OpenAI 云端（`wss://chatgpt.com/backend-api/...`）维持 WebSocket / WebRTC 长连接，手机端控制指令通过此云端中继分发。

#### 阻断点：
* **UWP 回环网络隔离（Loopback Isolation）**：Windows 默认禁止 UWP 应用访问本地 `127.0.0.1`。即使开启系统代理，前端应用也无法连上 `127.0.0.1:<PORT>`，连接会被内核直接切断。
* **后台守护进程不读 WinINET**：Win32 进程 `codex.exe` 仅读取环境变量（`HTTP_PROXY`）或专属配置。若未注入代理，它会尝试物理 Wi-Fi 直连，触发 GFW 阻断（Socket 处于 `SynSent` 挂起超时）。

---

### 1.3 Antigravity CLI 登录与模型调用失败机理

Antigravity CLI（`agy.exe`）为 Go 语言编写的编译型二进制：
1. **Go 网络栈特性**：Go 语言标准库 `net/http` 仅识别环境变量 `HTTP_PROXY` / `HTTPS_PROXY`，**完全忽略** Windows 注册表系统代理设置。
2. **OAuth 认证与 API 换票**：
   * 浏览器点完 Google 授权后，`agy.exe` 必须在后台向 `oauth2.googleapis.com` 发送 POST 换取 Token；
   * 随后向 `cloudcode-pa.googleapis.com` 校验账号配额，向 `generativelanguage.googleapis.com` 交互模型。
   * 无代理环境变量时，CLI 后台直连 Google 必然超时，导致登录流程彻底卡死。
3. **本地 Language Server 保护（NO_PROXY）**：
   * `agy.exe` 内部有前端与本地 Language Server（`127.0.0.1:42111` 等）的通信。如果配代理时未排除 `localhost,127.0.0.1`，本地通信会被误送到代理端口造成死锁。

---

## 二、 免 TUN 解决方案实战

### 2.1 Codex Desktop 独立代理方案

#### 步骤 1：解除 UWP 回环隔离
以管理员权限运行 PowerShell 命令（或在 Clash Verge 中勾选 **UWP Loopback** ➔ `OpenAI.Codex`）：
```powershell
CheckNetIsolation.exe LoopbackExempt -a "-n=OpenAI.Codex_2p2nqsd0c76g0"
```

#### 步骤 2：创建局部环境配置文件（零系统污染）
在 `~/.codex/.env` 中写入以下配置，仅供 Codex 守护进程和主程序读取（*将 `<PORT>` 替换为您的代理端口，如 `7897` 或 `7890`*）：
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

#### 步骤 3：终止旧僵尸进程并重启应用
```powershell
Get-Process | Where-Object { $_.ProcessName -match "chatgpt|codex" -and $_.ProcessName -ne "codex-plus-plus-manager" } | Stop-Process -Force
Start-Process "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
```

---

### 2.2 Antigravity CLI 独立代理方案

在 PowerShell 配置文件中加入 `try...finally` 智能封装，在执行 `agy` 时注入代理，退出后瞬间自动复原，终端环境永不残留脏变量：

#### 配置文件路径：
* PowerShell 7: `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
* Windows PowerShell 5.1: `$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`

#### 写入代码（*将 `<PORT>` 替换为您的代理端口*）：
```powershell
function agy {
    # 1. 备份当前环境变量
    $oldHttp = $env:HTTP_PROXY
    $oldHttps = $env:HTTPS_PROXY
    $oldAll = $env:ALL_PROXY
    $oldNo = $env:NO_PROXY

    try {
        # 2. 仅在此次运行 agy 期间注入代理
        $env:HTTP_PROXY = "http://127.0.0.1:<PORT>"
        $env:HTTPS_PROXY = "http://127.0.0.1:<PORT>"
        $env:ALL_PROXY = "http://127.0.0.1:<PORT>"
        $env:NO_PROXY = "localhost,127.0.0.1,::1,192.168.*,10.*"

        # 3. 完整透传所有子命令与参数
        & "$HOME\AppData\Local\agy\bin\agy.exe" @args
    }
    finally {
        # 4. 退出后立刻复原环境变量，终端保持绝对纯净
        $env:HTTP_PROXY = $oldHttp
        $env:HTTPS_PROXY = $oldHttps
        $env:ALL_PROXY = $oldAll
        $env:NO_PROXY = $oldNo
    }
}
```

#### Git Bash 支持（`~/.bash_profile`）：
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

## 三、 自动化运维脚本说明

本仓库在 [`scripts/`](./scripts/) 目录下提供了即插即用的自动化运维脚本，**全部支持自定义代理端口**：

| 脚本 | 默认执行 | 自定义端口示例 | 描述 |
| :--- | :--- | :--- | :--- |
| [`scripts/check-status.ps1`](./scripts/check-status.ps1) | `.\check-status.ps1` | `.\check-status.ps1 -ProxyPort 7890` | 一键检测 Codex UWP 豁免、实时 Socket 连接状态与代理连通性 |
| [`scripts/setup-codex.ps1`](./scripts/setup-codex.ps1) | `.\setup-codex.ps1` | `.\setup-codex.ps1 -ProxyPort 7890` | 自动配置 `.codex/.env` 并重启桌面端实例 |
| [`scripts/setup-agy.ps1`](./scripts/setup-agy.ps1) | `.\setup-agy.ps1` | `.\setup-agy.ps1 -ProxyPort 7890` | 自动配置 PowerShell 7、5.1 和 Git Bash 配置文件 |

---

## 四、 持久化机制与常见 FAQ

### Q1: 电脑重启或软件升级后配置会被覆盖吗？
* **重启**：100% 永久有效。PowerShell Profile、`.codex/.env` 以及 Windows UWP 豁免注册表均具备持久化特性。
* **软件升级**：`agy update` 和 Codex Desktop 升级仅替换二进制程序，不会修改用户目录下的配置与环境脚本。

### Q2: 为什么不直接在 Windows 系统环境变量里加 `HTTP_PROXY`？
* 如果写入系统全局环境变量，当临时关闭代理软件时，终端中执行 `pip`、`npm`、`git` 或 Python 爬虫脚本会因找不到代理端口而报错（`Connection Refused`）。
* 局部注入方案做到了“各取所需、互不干扰”，保证开发环境的纯洁性。