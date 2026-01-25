# Sing-box 终极定制版（含 Cloudflare WARP 分流 + 自愈）

一个面向 **VPS/服务器** 的一键安装脚本：自动安装 sing-box、生成完整配置、开放防火墙端口、输出节点订阅信息，并可选开启 **Cloudflare WARP** 作为分流出口（支持端口/入口轮换自愈，解决“WARP 分流网站时好时坏/超时”）。

> 适合：需要在同一台 VPS 上快速部署多协议节点，同时对 **ChatGPT / Gemini / OpenAI** 等站点进行 WARP 分流解锁的人。

---

## 功能一览

- ✅ 自动安装最新 sing-box（二进制下载安装到 `/usr/local/bin/sing-box`）
- ✅ 自动生成 `/etc/sing-box/config.json`（可重复运行脚本，尽量复用旧配置关键凭据）
- ✅ 协议入站（按脚本生成的端口）：
  - VLESS + REALITY（TCP）
  - Hysteria2（UDP/QUIC）
  - TUIC（UDP/QUIC）
  - AnyTLS（TCP）
  - ShadowTLS（TCP，带本地 Shadowsocks detour）
- ✅ 证书模式：
  - ACME（域名 + DNS/HTTP-01）
  - 自签（无域名，SNI 伪装）
- ✅ 可选 Cloudflare Argo（本地 VLESS+WS 入站供 Tunnel 反代）
- ✅ 防火墙自动放行（优先 ufw / firewalld，其次 iptables/ip6tables，最后 nft 兜底）
- ✅ 自动生成 `sb` 命令：一键打印节点链接，并生成 Mihomo YAML：
  - `/usr/local/bin/sb`
  - `/etc/sing-box/mihomo_proxies.yaml`
- ✅ **WARP 分流（重点）**
  - 使用 `wgcf` 自动生成/复用 WARP WireGuard profile
  - sing-box `endpoint/wireguard (system=true)` 创建系统接口 `sb-warp`
  - `direct` 出站通过 `bind_interface=sb-warp` 强制走 WARP
  - 支持 `split`（仅分流域名）或 `all`（全局走 WARP）
  - 自带端口探测（2408/500/1701/4500）+ **入口/端口轮换自愈**（systemd timer / cron）

---

## 支持系统

- Debian / Ubuntu（systemd）
- CentOS / Alma / Rocky（systemd）
- Fedora（systemd）
- Alpine（OpenRC）

> 必须 root 运行。

---

## 快速开始

官方脚本地址：`https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh`


### 0）前置依赖：安装 curl + bash（强烈建议先执行）

**Debian/Ubuntu**
```bash
apt-get update -y && apt-get install -y curl bash ca-certificates
```

**CentOS/Alma/Rocky**
```bash
yum install -y curl bash ca-certificates
```

**Fedora**
```bash
dnf install -y curl bash ca-certificates
```

**Alpine**
```bash
apk add --no-cache curl bash ca-certificates
```

---

### 1）安装（推荐：下载后执行）

把下面的 `SCRIPT_URL` 替换成你仓库里的 raw 地址（例如 GitHub raw）：

```bash
SCRIPT_URL="https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh"
curl -fsSL "$SCRIPT_URL" -o install.sh
chmod +x install.sh
bash install.sh
```

---

### 2）一行命令安装（curl | bash）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)"
```

> 你也可以先审计再运行：
```bash
curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh | sed -n '1,200p'
```

---

## 安装过程会问你什么？

脚本会交互询问（若在 TTY）：

- 是否启用 WARP（默认启用）
- WARP 模式：
  - `split`：仅命中的域名走 WARP（推荐）
  - `all`：所有流量走 WARP
- 双栈机器输出模式：IPv4 / IPv6 / both
- 起始端口（回车随机高位连续端口）
- 证书模式（ACME / 自签）
- 可选 Argo Token（不需要可直接回车）

---

## 非交互模式（自动化部署）

### 关闭交互
```bash
WARP_INTERACTIVE=0 bash install.sh
```

### 直接禁用 WARP
```bash
WARP_INTERACTIVE=0 WARP_ENABLE=0 bash install.sh
```

### 强制启用 WARP + 分流模式
```bash
WARP_INTERACTIVE=0 WARP_ENABLE=1 WARP_MODE=split bash install.sh
```

### 强制启用 WARP + 全局模式
```bash
WARP_INTERACTIVE=0 WARP_ENABLE=1 WARP_MODE=all bash install.sh
```

---

## WARP 相关参数（安装时生效）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `WARP_INTERACTIVE` | `1` | 是否交互询问（0/1） |
| `WARP_ENABLE_DEFAULT` | `1` | 未显式设置 `WARP_ENABLE` 时的默认值 |
| `WARP_ENABLE` | （自动） | 0/1，是否启用 WARP |
| `WARP_MODE` | `split` | `split` / `all` |
| `WARP_DOMAINS` | 见脚本 | split 分流域名（逗号分隔） |
| `WARP_INGRESS` | `engage.cloudflareclient.com` | 优先探测入口（可写域名或 IP） |
| `WARP_INGRESS_CANDIDATES` | `engage.cloudflareclient.com 162.159.192.1 162.159.193.10` | 备用入口（空格分隔） |
| `WARP_PORTS` | `2408 500 1701 4500` | 依次探测端口 |
| `WARP_MTU` | `1280` | WARP 接口 MTU |
| `WARP_KEEPALIVE` | `25` | WireGuard keepalive 秒 |
| `WARP_IFNAME` | `sb-warp` | 系统接口名 |
| `WARP_TEST_URL` | `https://www.cloudflare.com/cdn-cgi/trace` | 探测/自愈测试 URL |
| `WARP_WATCH_INTERVAL` | `120` | 自愈检测间隔（秒，systemd timer） |

> **提示**：你遇到“WARP 时好时坏”的场景，最有效的组合通常是：`keepalive=25 + 多端口(2408/500/1701/4500) + 多入口候选`。

---

## 端口分配规则（重要）

脚本使用 **连续端口段**：

单栈（ipv4 或 ipv6）默认 5 个端口：
- base+0：VLESS+REALITY（TCP）
- base+1：Hysteria2（UDP）
- base+2：TUIC（UDP）
- base+3：AnyTLS（TCP）
- base+4：ShadowTLS（TCP）

双栈（both）为两组连续端口（共 10 个）：
- IPv4：base+0 ~ base+4
- IPv6：base+5 ~ base+9

---

## 安装完成后怎么拿节点？

安装结束会自动打印节点链接，并生成：

- `sb`：打印全部节点链接 + 生成 Mihomo YAML  
  ```bash
  sb
  ```
- Mihomo YAML 输出文件：  
  - `/etc/sing-box/mihomo_proxies.yaml`

---

## 常用运维命令

### 查看服务状态 / 日志
```bash
systemctl status sing-box -l --no-pager
journalctl -u sing-box -f --no-pager
```

### 配置校验
```bash
sing-box check -c /etc/sing-box/config.json
```

### 关键文件路径
- 主配置：`/etc/sing-box/config.json`
- 状态文件：`/etc/sing-box/.sb_state`
- WARP profile：`/etc/sing-box/warp/wgcf-profile.conf`
- 快捷输出：`/usr/local/bin/sb`
- Mihomo YAML：`/etc/sing-box/mihomo_proxies.yaml`

---

## WARP 排障（分流的网站打不开/超时）

### 1）确认 WARP 接口存在
```bash
ip link show sb-warp
```

### 2）强制走 WARP 接口测试出网
```bash
curl -fsSL --interface sb-warp --connect-timeout 4 --max-time 9 https://www.cloudflare.com/cdn-cgi/trace | head
```

### 3）看 sing-box 是否在和 WARP 端点通信（UDP）
```bash
ss -uapn | grep sing-box | egrep '2408|500|1701|4500|162\.159\.19[23]\.'
```

### 4）查看 WARP 自愈守护是否启用
**systemd**
```bash
systemctl status sb-warp-watch.timer --no-pager
systemctl list-timers | grep sb-warp-watch
```

**无 systemd/OpenRC（cron）**
```bash
cat /etc/cron.d/sb-warp-watch
```

### 5）如果你想手动改 WARP 入口/端口

- 修改配置（推荐用 jq 修改 endpoint）：
```bash
jq '(.endpoints[] | select(.tag=="warp-ep") | .peers[0].address)="engage.cloudflareclient.com"
    |(.endpoints[] | select(.tag=="warp-ep") | .peers[0].port)=2408' \
  /etc/sing-box/config.json > /tmp/c.json && mv /tmp/c.json /etc/sing-box/config.json
systemctl restart sing-box
```

- 或者编辑状态文件，影响自愈轮换顺序：
  - `/etc/sing-box/.sb_state` 里有 `SB_WARP_INGRESS / SB_WARP_PORT / SB_WARP_INGRESS_CANDIDATES / SB_WARP_PORTS`

---

## 卸载

脚本支持一键卸载（会删除 `/etc/sing-box` 等文件）：

```bash
bash install.sh --uninstall
```

如果你是 curl|bash 方式运行，可这样传参：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install/main/install.sh)" -- --uninstall
```

---

## 安全提示

- 建议先下载脚本到本地查看再运行，确认符合你的预期。
- 脚本会修改防火墙规则、安装系统服务、写入配置文件，请确保在你可控的服务器上使用。
- WARP 使用 `wgcf` 生成 consumer profile；某些机房/线路对 UDP 端口可能存在间歇性干扰，因此脚本内置了端口/入口轮换自愈。

---

## License

按你的项目实际 License 填写（例如 MIT / GPL-3.0 等）。
