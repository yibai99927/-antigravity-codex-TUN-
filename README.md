# Windows 下 AI 工具免 TUN 代理配置与排坑指南

> **核心目标**：在 Windows 11 环境下，完全**不开启 TUN 模式**（仅使用 Clash Verge / Mihomo 的普通系统代理端口 127.0.0.1:7897），解决以下两大难题：
> 1. **Codex Desktop**：手机端（iOS / Android）无法远程控制桌面端 Codex。
> 2. **Antigravity CLI (gy)**：无法完成 Google OAuth 登录认证及大模型调用。
>
> 且**不修改 Windows 系统全局环境变量**，对日常命令行（git、pip、python、
pm、SSH 连远程服务器等）实现**绝对零污染、零干扰**。

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
| **普通系统代理** | 仅在 Windows 注册表设置 HTTP 代理（127.0.0.1:7897） | 仅主动读取 WinINET 的图形应用（如 Chrome/Edge） | 对系统网络无侵入，但命令行工具、UWP 沙盒应用和非标准长连接默认无法走代理 |

---

### 1.2 Codex Desktop 手机远程失败机理

Codex Desktop（Windows 版本）由两部分组成：
1. **前端图形界面 (ChatGPT.exe)**：以 Windows Store / UWP (MSIX AppContainer) 格式封装。
2. **后台常驻服务 (codex.exe)**：Win32 守护进程，负责与 OpenAI 云端（wss://chatgpt.com/backend-api/...）维持 WebSocket / WebRTC 长连接，手机端控制指令通过此云端中继分发。

#### 阻断点：
* **UWP 回环网络隔离（Loopback Isolation）**：Windows 默认禁止 UWP 应用访问本地 127.0.0.1。即使开启系统代理，前端应用也无法连上 127.0.0.1:7897，连接会被内核直接切断。
* **后台守护进程不读 WinINET**：Win32 进程 codex.exe 仅读取环境变量（HTTP_PROXY）或专属配置。若未注入代理，它会尝试物理 Wi-Fi 直连，触发 GFW 阻断（Socket 处于 SynSent 挂起超时）。

---

### 1.3 Antigravity CLI 登录与模型调用失败机理

Antigravity CLI（gy.exe）为 Go 语言编写的编译型二进制：
1. **Go 网络栈特性**：Go 语言标准库 
et/http 仅识别环境变量 HTTP_PROXY / HTTPS_PROXY，**完全忽略** Windows 注册表系统代理设置。
2. **OAuth 认证与 API 换票**：
   * 浏览器点完 Google 授权后，gy.exe 必须在后台向 oauth2.googleapis.com 发送 POST 换取 Token；
   * 随后向 cloudcode-pa.googleapis.com 校验账号配额，向 generativelanguage.googleapis.com 交互模型。
   * 无代理环境变量时，CLI 后台直连 Google 必然超时，导致登录流程彻底卡死。
3. **本地 Language Server 保护（NO_PROXY）**：
   * gy.exe 内部有前端与本地 Language Server（127.0.0.1:42111 等）的通信。如果配代理时未排除 localhost,127.0.0.1，本地通信会被误送到代理端口造成死锁。

---

## 二、 免 TUN 解决方案实战

### 2.1 Codex Desktop 独立代理方案

#### 步骤 1：解除 UWP 回环隔离
以管理员权限运行 PowerShell 命令（或在 Clash Verge 中勾选 **UWP Loopback** ➔ OpenAI.Codex）：
`powershell
CheckNetIsolation.exe LoopbackExempt -a "-n=OpenAI.Codex_2p2nqsd0c76g0"
`

#### 步骤 2：创建局部环境配置文件（零系统污染）
在 ~/.codex/.env 中写入以下配置，仅供 Codex 守护进程和主程序读取：
`ini
HTTP_PROXY=http://127.0.0.1:7897
HTTPS_PROXY=http://127.0.0.1:7897
ALL_PROXY=http://127.0.0.1:7897
NO_PROXY=localhost,127.0.0.1,::1,192.168.*,10.*
http_proxy=http://127.0.0.1:7897
https_proxy=http://127.0.0.1:7897
all_proxy=http://127.0.0.1:7897
no_proxy=localhost,127.0.0.1,::1,192.168.*,10.*
`

#### 步骤 3：终止旧僵尸进程并重启应用
`powershell
Get-Process | Where-Object { .ProcessName -match "chatgpt|codex" -and .ProcessName -ne "codex-plus-plus-manager" } | Stop-Process -Force
Start-Process "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
`

---

### 2.2 Antigravity CLI 独立代理方案

在 PowerShell 配置文件中加入 	ry...finally 智能封装，在执行 gy 时注入代理，退出后瞬间自动复原，终端环境永不残留脏变量：

#### 配置文件路径：
* PowerShell 7: $HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
* Windows PowerShell 5.1: $HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1

#### 写入代码：
`powershell
function agy {
    # 1. 备份当前环境变量
     = http://127.0.0.1:7897
     = http://127.0.0.1:7897
     = http://127.0.0.1:7897
     = localhost,127.0.0.1,::1,192.168.*,10.*

    try {
        # 2. 仅在此次运行 agy 期间注入代理
        http://127.0.0.1:7897 = "http://127.0.0.1:7897"
        http://127.0.0.1:7897 = "http://127.0.0.1:7897"
        http://127.0.0.1:7897 = "http://127.0.0.1:7897"
        localhost,127.0.0.1,::1,192.168.*,10.* = "localhost,127.0.0.1,::1,192.168.*,10.*"

        # 3. 完整透传所有子命令与参数
        & "C:\Users\Administrator\AppData\Local\agy\bin\agy.exe" @args
    }
    finally {
        # 4. 退出后立刻复原环境变量，终端保持绝对纯净
        http://127.0.0.1:7897 = 
        http://127.0.0.1:7897 = 
        http://127.0.0.1:7897 = 
        localhost,127.0.0.1,::1,192.168.*,10.* = 
    }
}
`

#### Git Bash 支持（~/.bash_profile）：
`ash
function agy() {
    HTTP_PROXY="http://127.0.0.1:7897" \
    HTTPS_PROXY="http://127.0.0.1:7897" \
    ALL_PROXY="http://127.0.0.1:7897" \
    NO_PROXY="localhost,127.0.0.1,::1,192.168.*,10.*" \
    "C:\Users\Administrator/AppData/Local/agy/bin/agy.exe" "$@"
}
`

---

## 三、 自动化运维脚本说明

本仓库在 [scripts/](./scripts/) 目录下提供了即插即用的自动化运维脚本：

| 脚本 | 描述 |
| :--- | :--- |
| [scripts/check-status.ps1](./scripts/check-status.ps1) | 一键检测 Codex UWP 豁免、实时 Socket 连接状态与代理连通性 |
| [scripts/setup-codex.ps1](./scripts/setup-codex.ps1) | 自动配置 .codex/.env 并重启桌面端实例 |
| [scripts/setup-agy.ps1](./scripts/setup-agy.ps1) | 自动配置 PowerShell 7、5.1 和 Git Bash 配置文件 |

---

## 四、 持久化机制与常见 FAQ

### Q1: 电脑重启或软件升级后配置会被覆盖吗？
* **重启**：100% 永久有效。PowerShell Profile、.codex/.env 以及 Windows UWP 豁免注册表均具备持久化特性。
* **软件升级**：gy update 和 Codex Desktop 升级仅替换二进制程序，不会修改用户目录下的配置与环境脚本。

### Q2: 为什么不直接在 Windows 系统环境变量里加 HTTP_PROXY？
* 如果写入系统全局环境变量，当临时关闭代理软件时，终端中执行 pip、
pm、git 或 Python 爬虫脚本会因找不到 7897 端口而报错（Connection Refused）。
* 局部注入方案做到了“各取所需、互不干扰”，保证开发环境的纯洁性。
