
<div align="center">

# SB-Install

### 🚀 Sing-box 一键安装与管理脚本

一个 **简单 / 稳定 / 自动化** 的 Sing-box 安装脚本  
支持 **一键安装、管理、更新与卸载**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)]()
[![Shell](https://img.shields.io/badge/language-bash-green.svg)]()
[![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)]()
[![GitHub stars](https://img.shields.io/github/stars/kzhx666/sb-install)]()

</div>

---

# 📑 目录

- [项目介绍](#项目介绍)
- [功能特性](#功能特性)
- [系统支持](#系统支持)
- [安装前置要求](#安装前置要求)
- [一键安装](#一键安装)
- [安装路径](#安装路径)
- [使用方法](#使用方法)
- [更新脚本](#更新脚本)
- [卸载](#卸载)
- [项目结构](#项目结构)
- [常见问题](#常见问题)
- [License](#license)

---

# 📦 项目介绍

**SB-Install** 是一个用于快速部署 **Sing-box** 的自动化脚本。

项目目标：

- 极简部署
- 自动化安装
- 稳定运行
- 易于管理

适用于：

- VPS
- 云服务器
- Linux 主机

---

# ✨ 功能特性

✔ 一键安装 Sing-box  
✔ 自动检测 Linux 系统  
✔ 自动下载最新版本  
✔ 自动创建 systemd 服务  
✔ 自动生成配置目录  
✔ 快捷管理命令  
✔ 一键启动 / 停止 / 重启  
✔ 支持快速升级

---

# 💻 系统支持

| 系统 | 支持情况 |
|-----|----------|
| Ubuntu | ✅ |
| Debian | ✅ |
| CentOS | ✅ |
| AlmaLinux | ✅ |
| RockyLinux | ✅ |

推荐系统：

```
Ubuntu 22.04 / Debian 12
```

---

# ⚙ 安装前置要求

请确保服务器满足以下条件：

- Root 权限
- 已连接互联网
- GitHub 可访问

安装基础依赖：

### Debian / Ubuntu

```bash
apt update -y
apt install -y curl wget sudo bash
```

### CentOS / AlmaLinux / Rocky

```bash
yum install -y curl wget sudo bash
```

---

# 🚀 一键安装

### 方法 1（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)
```

### 方法 2

```bash
wget https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh
chmod +x install.sh
bash install.sh
```

---

# 📂 安装路径

| 类型 | 路径 |
|----|----|
| 程序文件 | `/usr/local/bin/sing-box` |
| 配置目录 | `/etc/sing-box` |
| 证书目录 | `/etc/sing-box/cert` |
| 管理命令 | `/usr/local/bin/sb` |

---

# 🧭 使用方法

安装完成后运行：

```bash
sb
```

进入 **管理菜单**。

常用命令：

```bash
sb start
sb stop
sb restart
sb status
```

---

# 🔄 更新脚本

重新运行安装命令即可更新：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)
```

---

# 🗑 卸载

如果需要卸载：

```bash
systemctl stop sing-box
rm -rf /etc/sing-box
rm -f /usr/local/bin/sing-box
rm -f /usr/local/bin/sb
```

---

# 📁 项目结构

```
sb-install
│
├── install.sh
└── README.md
```

---

# ❓ 常见问题

### 1. GitHub 无法访问

建议使用代理或镜像。

### 2. 权限不足

请使用 **root 用户运行脚本**。

```
sudo -i
```

---

# 📜 License

MIT License

---

# ⭐ 支持项目

如果这个项目对你有帮助，欢迎：

- ⭐ Star 本项目
- 🍴 Fork 项目
- 🐛 提交 Issue

---

# 🔗 项目地址

GitHub:

https://github.com/kzhx666/sb-install

