
readme_content = '''<p align="center">
  <img src="https://raw.githubusercontent.com/SagerNet/sing-box/main/docs/assets/logo.svg" width="120" alt="Sing-box Logo" />
</p>

<h1 align="center">🚀 Sing-box 终极定制版安装脚本</h1>

<p align="center">
  <a href="https://github.com/kzhx666/sb-install/stargazers"><img src="https://img.shields.io/github/stars/kzhx666/sb-install?style=for-the-badge&color=ff69b4" alt="Stars" /></a>
  <a href="https://github.com/kzhx666/sb-install/network/members"><img src="https://img.shields.io/github/forks/kzhx666/sb-install?style=for-the-badge&color=blue" alt="Forks" /></a>
  <a href="https://github.com/kzhx666/sb-install/issues"><img src="https://img.shields.io/github/issues/kzhx666/sb-install?style=for-the-badge&color=red" alt="Issues" /></a>
  <a href="https://github.com/kzhx666/sb-install/blob/main/LICENSE"><img src="https://img.shields.io/github/license/kzhx666/sb-install?style=for-the-badge&color=green" alt="License" /></a>
  <br/>
  <a href="https://sing-box.sagernet.org/"><img src="https://img.shields.io/badge/Sing--Box-Core-1.12+-blue?style=for-the-badge&logo=linux" alt="Sing-box Core" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Platform-Linux-orange?style=for-the-badge&logo=linux" alt="Platform" /></a>
</p>

<p align="center">
  <b>一键部署 Sing-box 多协议代理服务 | 支持 Reality/Hysteria2/Tuic/AnyTLS/ShadowTLS/Trojan | 内置 WARP 分流 | 端口跳跃 | Cloudflare Argo 隧道</b>
</p>

<p align="center">
  <a href="#-快速开始">🚀 快速开始</a> •
  <a href="#-功能特性">✨ 功能特性</a> •
  <a href="#-系统支持">💻 系统支持</a> •
  <a href="#-项目结构">📁 项目结构</a> •
  <a href="#-faq">❓ FAQ</a> •
  <a href="#-更新日志">📋 更新日志</a>
</p>

---

## 📸 项目截图

<details>
<summary>点击查看演示截图</summary>

| 主菜单界面 | 配置生成 | 节点输出 |
|:---:|:---:|:---:|
| ![Menu](https://via.placeholder.com/400x200/2d2d2d/ffffff?text=Interactive+Menu) | ![Config](https://via.placeholder.com/400x200/2d2d2d/ffffff?text=Auto+Config+Gen) | ![Nodes](https://via.placeholder.com/400x200/2d2d2d/ffffff?text=Multi-Protocol+Links) |

</details>

## ⚡ 一键安装

```bash
# 方式一：直接运行（推荐）
bash <(curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)

# 方式二：先下载再执行
wget -N https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh && bash install.sh

# 方式三：使用代理加速（国内服务器）
bash <(curl -fsSL https://ghproxy.com/https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)
```

> 🎬 **安装演示 GIF**  
> ![Install Demo](https://via.placeholder.com/800x400/1a1a2e/ffffff?text=Auto+Install+Demo+GIF)

---

## 📋 目录

- [功能特性](#-功能特性)
- [系统支持](#-系统支持)
- [前置要求](#-前置要求)
- [安装步骤](#-安装步骤)
- [使用方法](#-使用方法)
- [项目结构](#-项目结构)
- [架构图](#-架构图)
- [FAQ](#-faq)
- [更新日志](#-更新日志)
- [Star History](#-star-history)
- [贡献者](#-贡献者)
- [许可证](#-许可证)

---

## ✨ 功能特性

| 功能模块 | 详细说明 | 状态 |
|:---:|:---|:---:|
| **多协议支持** | VLESS+Reality / Hysteria2 / TUIC / AnyTLS / ShadowTLS / Trojan / VLESS+WS+Argo | ✅ |
| **双栈支持** | IPv4/IPv6 单栈或双栈同时监听，智能路由分流 | ✅ |
| **WARP 分流** | 自动注册 Cloudflare WARP，支持域名分流或全局代理 | ✅ |
| **端口跳跃** | Hysteria2 原生多端口 + iptables/nftables REDIRECT 双重保障 | ✅ |
| **Argo 隧道** | 内置 Cloudflared，支持 QUIC/HTTP2 自动降级 | ✅ |
| **证书管理** | ACME DNS-01/HTTP-01 自动签发 或 自签证书 | ✅ |
| **性能调优** | 自动 TCP BBR / 缓冲区优化 / 连接数调优 | ✅ |
| **防火墙管理** | 自动识别 ufw/firewalld/iptables/nftables 并放行端口 | ✅ |
| **WARP 守护** | 自动检测 WARP 连通性，故障自动切换端口重启 | ✅ |
| **配置复用** | 重装时自动保留 UUID/密码/密钥，客户端无需重新配置 | ✅ |

---

## 💻 系统支持

| 操作系统 | 版本要求 | 包管理器 | 支持状态 |
|:---|:---|:---:|:---:|
| **Debian** | 10+ (Buster/Bullseye/Bookworm) | `apt` | ✅ 完全支持 |
| **Ubuntu** | 18.04+ (LTS 推荐) | `apt` | ✅ 完全支持 |
| **CentOS** | 7 / Stream 8/9 | `yum/dnf` | ✅ 完全支持 |
| **Alpine Linux** | 3.14+ | `apk` | ✅ 完全支持 |
| **Arch Linux** | Rolling | `pacman` | ⚠️ 手动安装依赖 |
| **OpenWrt** | 21.02+ | `opkg` | ⚠️ 实验性支持 |

### 最低系统要求

- **CPU**: 1 vCore (x86_64/ARM64/ARMv7)
- **内存**: 512 MB RAM (推荐 1GB+)
- **磁盘**: 100 MB 可用空间
- **网络**: 公网 IPv4 和/或 IPv6 地址
- **权限**: Root 用户或 sudo 权限

---

## 🔧 前置要求

### 必需依赖

脚本会自动安装以下依赖，如遇网络问题可手动预装：

```bash
# Debian/Ubuntu
apt-get update && apt-get install -y bash curl wget tar jq openssl socat lsof net-tools \\
  iptables iproute2 nftables ca-certificates coreutils util-linux libcap2-bin tcpdump

# CentOS/RHEL
yum install -y bash curl wget tar jq openssl socat lsof net-tools \\
  iptables iproute nftables ca-certificates coreutils util-linux libcap tcpdump

# Alpine Linux
apk add --no-cache bash curl wget tar jq openssl socat lsof net-tools \\
  iptables ip6tables nftables iproute2 ca-certificates coreutils util-linux libcap tcpdump
```

### 可选优化（推荐）

```bash
# 开启 BBR 加速（脚本会自动配置）
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# 调整文件描述符限制
ulimit -n 1048576
echo "* soft nofile 1048576" >> /etc/security/limits.conf
echo "* hard nofile 1048576" >> /etc/security/limits.conf
```

---

## 🚀 安装步骤

### 步骤 1：执行安装脚本

```bash
# 使用 curl（推荐）
bash <(curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)

# 或使用 wget
bash <(wget -qO- https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)
```

### 步骤 2：交互式配置

脚本启动后将显示主菜单：

```
==============================================================
   Sing-box 终极定制版 v6.5 (无损原排版 + 修复 Bug + 交互菜单)   
==============================================================
  1. 全新安装 / 重新配置 (含WARP,跳跃,Argo等)
  2. 查看所有节点链接与配置 (sb 命令)
  3. 一键更新 Sing-box 核心至最新版
  4. 彻底卸载脚本及所有服务
  0. 退出
==============================================================
```

### 步骤 3：根据提示完成配置

| 配置项 | 说明 | 建议 |
|:---|:---|:---|
| **IP 模式** | IPv4/IPv6/Both | 根据 VPS 网络选择 |
| **起始端口** | 服务监听端口 | 回车随机生成高位端口 |
| **端口跳跃** | Hysteria2 多端口范围 | 如 `31000-32000` |
| **节点前缀** | 节点显示名称 | 如 `HK`、`SG`、`US` |
| **证书模式** | ACME 域名证书或自签 | 有域名选 1，无域名选 2 |
| **Cloudflare Argo** | 内网穿透隧道 | 可选，不需要回车跳过 |
| **WARP 分流** | Cloudflare WARP 出站 | 推荐启用解决风控 |

### 步骤 4：查看节点信息

```bash
# 安装完成后执行
sb

# 或查看详细配置
cat /etc/sing-box/config.json
```

---

## 🎮 使用方法

### 快捷命令

```bash
sb                      # 显示主菜单和节点链接
sb --uninstall          # 彻底卸载
```

### 服务管理

```bash
# systemd 系统
systemctl status sing-box          # 查看状态
systemctl restart sing-box         # 重启服务
systemctl stop sing-box            # 停止服务
journalctl -u sing-box -f          # 查看日志

# OpenRC 系统
rc-service sing-box status
rc-service sing-box restart
```

### 配置文件位置

| 文件路径 | 说明 |
|:---|:---|
| `/etc/sing-box/config.json` | 主配置文件 |
| `/etc/sing-box/.sb_state` | 安装状态保存 |
| `/etc/sing-box/cert/` | TLS 证书目录 |
| `/etc/sing-box/mihomo_proxies.yaml` | Mihomo/Clash 配置 |
| `/usr/local/bin/sb` | 快捷命令脚本 |

---

## 📁 项目结构

```
sb-install/
├── 📄 install.sh              # 主安装脚本 (核心)
├── 📁 .github/
│   └── 📁 workflows/          # GitHub Actions CI/CD
├── 📄 README.md               # 项目说明文档
├── 📄 LICENSE                 # MIT 许可证
├── 📄 CHANGELOG.md            # 更新日志
└── 📁 docs/                   # 详细文档
    ├── 📄 warp-guide.md       # WARP 配置指南
    ├── 📄 hop-optimization.md # 端口跳跃优化
    └── 📄 faq.md              # 常见问题详解
```

### 核心脚本功能模块

```
install.sh
├── 🎨 颜色输出与日志系统
├── 🔍 系统检测 (包管理器/初始化系统)
├── 📦 依赖安装 (apt/yum/dnf/apk)
├── 👤 用户权限管理 (sing-box 用户)
├── 🔌 端口管理 (占用检测/随机分配)
├── 🌐 WARP 管理 (wgcf 注册/探测/守护)
├── ⚡ 性能调优 (sysctl/BBR/缓冲区)
├── 🧱 防火墙管理 (ufw/firewalld/iptables/nftables)
├── 🔐 证书管理 (OpenSSL/ACME)
├── ⬇️  核心安装 (sing-box 二进制)
├── ⚙️  配置生成 (多协议 JSON)
├── 🚀 Argo 隧道 (cloudflared)
├── 🎯 端口跳跃 (redirect/socat)
├── 🔄 服务管理 (systemd/OpenRC)
├── 🛡️ WARP 自愈 (定时检测脚本)
└── 📋 sb 命令 (节点链接生成)
```

---

## 🏗️ 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                        客户端 (Client)                       │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐ │
│  │ VLESS   │ │Hysteria2│ │  TUIC   │ │ AnyTLS  │ │Trojan  │ │
│  │+Reality │ │  +Hop   │ │  +BBR   │ │         │ │        │ │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └───┬────┘ │
│       │           │           │           │          │      │
│       └───────────┴───────────┴───────────┴──────────┘      │
│                           │                                 │
│                    ┌──────┴──────┐                         │
│                    │  Cloudflare │                         │
│                    │ Argo Tunnel │ (可选)                   │
│                    └──────┬──────┘                         │
└───────────────────────────┼─────────────────────────────────┘
                            │
┌───────────────────────────┼─────────────────────────────────┐
│                      VPS 服务器                              │
│  ┌────────────────────────┴────────────────────────┐         │
│  │           Sing-box 核心 (多入站)                 │         │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐ │         │
│  │  │VLESS    │ │Hysteria2│ │  TUIC   │ │Shadow  │ │         │
│  │  │Reality  │ │  UDP    │ │  UDP    │ │TLS     │ │         │
│  │  │:443     │ │:Range   │ │:Port    │ │:Port   │ │         │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └───┬────┘ │         │
│  └───────┼───────────┼───────────┼──────────┼──────┘         │
│          └───────────┴─────┬─────┴──────────┘                │
│                            │                                 │
│              ┌─────────────┴─────────────┐                   │
│              │      路由 & 分流规则        │                   │
│              │  ┌─────────────────────┐   │                   │
│              │  │   WARP Interface    │   │                   │
│              │  │  (Cloudflare WireGuard)│  │                   │
│              │  │  - Google/AI/流媒体   │   │                   │
│              │  └─────────────────────┘   │                   │
│              │  ┌─────────────────────┐   │                   │
│              │  │   Direct Outbound   │   │                   │
│              │  │  (IPv4/IPv6 优选)    │   │                   │
│              │  └─────────────────────┘   │                   │
│              └─────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

---

## ❓ FAQ

<details>
<summary><b>Q: 安装过程中提示 "端口被占用" 怎么办？</b></summary>

脚本会自动检测端口占用并重新分配随机端口。如需指定端口，请确保该端口未被其他服务使用：

```bash
# 检查端口占用
lsof -i :8080
ss -tulnp | grep 8080
```
</details>

<details>
<summary><b>Q: WARP 连接失败或频繁断开？</b></summary>

脚本内置 WARP 自愈守护，会自动检测并切换端口。如需手动调整：

```bash
# 编辑 WARP 配置
nano /etc/sing-box/config.json

# 修改入口地址和端口
# 常用入口: engage.cloudflareclient.com / 162.159.192.1 / 162.159.193.10
# 常用端口: 2408 / 500 / 1701 / 4500

# 重启服务
systemctl restart sing-box
```
</details>

<details>
<summary><b>Q: 如何更新 Sing-box 核心？</b></summary>

```bash
# 方式一：使用 sb 命令菜单
sb
# 选择选项 3

# 方式二：手动更新
bash <(curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)
# 选择更新核心
```
</details>

<details>
<summary><b>Q: 如何完全卸载？</b></summary>

```bash
sb
# 选择选项 4

# 或执行
bash <(curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh) --uninstall
```
</details>

<details>
<summary><b>Q: 支持哪些客户端？</b></summary>

| 客户端 | 支持协议 | 推荐版本 |
|:---|:---|:---:|
| **sing-box** | 全协议 | 1.12+ |
| **Mihomo (Clash.Meta)** | 全协议 | 1.18+ |
| **Hiddify** | 全协议 | 最新版 |
| **Nekoray** | Reality/Hysteria2/Trojan | 最新版 |
| **v2rayN** | Reality/VLESS/Trojan | 6.0+ |
| **Shadowrocket** | 全协议 | iOS 付费 |
| **Stash** | 全协议 | iOS/macOS |

</details>

<details>
<summary><b>Q: 如何开启端口跳跃的 Hysteria2？</b></summary>

安装时输入跳跃范围如 `31000-32000`，脚本会自动配置：
- **方式一**：nftables/iptables REDIRECT（推荐，性能最好）
- **方式二**：原生多端口监听（sing-box 1.12+）
- **方式三**：socat 中继（兼容模式，无 NAT 内核时使用）

客户端配置：
```
hysteria2://password@ip:31000-32000?mport=31000-32000&sni=bing.com
```
</details>

---

## 📋 更新日志

### v6.5 (2024-03-09)
- ✨ 新增交互式主菜单系统
- 🛡️ 修复防火墙 nftables 兼容性问题
- 🔄 优化 WARP 端口探测逻辑
- 📝 配置复用机制，重装保留密钥
- ⚡ 改进 Argo 隧道 QUIC/HTTP2 自动降级

### v6.0 (2024-02-15)
- 🎯 新增 AnyTLS 协议支持
- 🌐 完善 IPv6 单栈支持
- 🔧 重构端口跳跃实现

### v5.0 (2024-01-20)
- 🚀 初始版本发布
- 📦 支持 Reality/Hysteria2/TUIC/ShadowTLS/Trojan
- 🧩 集成 WARP 分流

[查看完整更新日志](./CHANGELOG.md)

---

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=kzhx666/sb-install&type=Date)](https://star-history.com/#kzhx666/sb-install&Date)

---

## 👥 贡献者

感谢所有为这个项目做出贡献的开发者！

<a href="https://github.com/kzhx666/sb-install/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=kzhx666/sb-install" />
</a>

### 如何贡献

1. Fork 本仓库
2. 创建你的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开一个 Pull Request

---

## 📜 许可证

本项目基于 [MIT](LICENSE) 许可证开源。

```
MIT License

Copyright (c) 2024 kzhx666

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

---

## 🙏 鸣谢

- [SagerNet/sing-box](https://github.com/SagerNet/sing-box) - 强大的代理平台核心
- [ViRb3/wgcf](https://github.com/ViRb3/wgcf) - WARP 账号管理工具
- [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) - Argo 隧道客户端
- [acmesh-official/acme.sh](https://github.com/acmesh-official/acme.sh) - ACME 协议客户端

---

<p align="center">
  <b>如果这个项目对你有帮助，请给它一个 ⭐ Star！</b>
</p>

<p align="center">
  <a href="https://github.com/kzhx666/sb-install/stargazers">⭐ Star 项目</a> •
  <a href="https://github.com/kzhx666/sb-install/issues/new">🐛 提交问题</a> •
  <a href="https://github.com/kzhx666/sb-install/fork">🔀 Fork 项目</a>
</p>
'''
