# sb-install（Sing-box NAT/LXC/Alpine Ultimate）v2.0

一键部署 **sing-box**：  
**Reality / Hysteria2（端口跳跃范围） / TUIC / AnyTLS / ShadowTLS + 可选 Argo**  
适配 **NAT VPS / LXC / Alpine(OpenRC)**，支持 **IPv4 / IPv6 / 双栈输出**，并支持 **“优先 IPv6（可回落 IPv4）”出站策略**

---

## 功能概览

- ✅ **VLESS Reality**（TCP）
- ✅ **Hysteria2**（UDP）
- ✅ 支持 **端口跳跃范围**（URL 使用 `mport=起-止`）
- ✅ 范围跳跃稳定实现：将跳跃范围 UDP 端口 **REDIRECT 到 Hy2 主端口**（nft/iptables 优先）
- ✅ **TUIC**（UDP）
- ✅ **AnyTLS**
- ✅ **ShadowTLS v3**（mihomo 最兼容：`type: ss + plugin: shadow-tls`）
- ✅ **Cloudflare Argo（可选）**：本地 WS `127.0.0.1:10086` + cloudflared
- ✅ **双栈输出**：可选输出 IPv4 / IPv6 / Both（v4 与 v6 端口**顺延分配**不冲突）

---

## 出站策略：优先 IPv6（可回落 IPv4）

脚本在 `direct-v6` 出站使用 **prefer_ipv6**，在 `direct-v4` 使用 **prefer_ipv4**。  
含义是：

- 目标站点同时有 IPv4/IPv6（A/AAAA）时：**优先走 IPv6**
- 目标站点只有 IPv4（仅 A）时：会回落走 IPv4（在 **双栈 VPS** 上可用）
- 如果你的 VPS **只有 IPv6**（没有 IPv4 出站路由）：访问 IPv4-only 站点仍可能失败，除非上游提供 **NAT64/464XLAT/DNS64**。

---

## 支持系统

- Debian / Ubuntu（systemd）
- Alpine Linux（OpenRC）
- 其他发行版（yum/dnf）尽力兼容（以 Debian/Alpine 为主测试）

---

## 前置依赖（建议先装）

脚本会自动安装依赖，但建议确保至少有 **curl + bash**：

### Debian / Ubuntu
```bash
apt-get update -y
apt-get install -y curl bash
```

### Alpine
```bash
apk add --no-cache bash curl
```

---

## 一键安装

> 仓库默认：`https://raw.githubusercontent.com/kzhx666/sb-install/refs/heads/main/install.sh`

### Debian / Ubuntu / systemd
```bash
bash <(curl -Ls https://raw.githubusercontent.com/kzhx666/sb-install/refs/heads/main/install.sh)
```

### Alpine / OpenRC
```bash
bash <(curl -Ls https://raw.githubusercontent.com/kzhx666/sb-install/refs/heads/main/install.sh)
```

---

## 安装交互项（会问什么）

1. **输出地址选择**（仅双栈 VPS）：IPv4 / IPv6 / Both  
2. **起始端口**：回车则随机高位连续端口（自动避开 80/443）  
   - Reality / Hy2 / TUIC / AnyTLS / ShadowTLS  
   - 若选择 Both：端口按协议顺延分配，例如起始 `10000`：  
     - IPv4：`10000~10004`  
     - IPv6：`10005~10009`
3. **Hy2 端口跳跃范围**：支持分别输入 v4/v6（如 `30100-30200`）  
4. **证书模式**
   - 有域名：ACME（支持 **Cloudflare DNS-01**，不占用 80，适配 NPM）
   - 无域名：自签（SNI 默认 `www.bing.com`），节点自动跳过验证  
5. **Argo（可选）**：cloudflared token + Argo 域名

---

## 输出与文件位置

安装完成会打印：

- ✅ 节点 URL（含 mihomo YAML）

并写入：

- sing-box 配置：`/etc/sing-box/config.json`
- 状态文件（sb 动态读取）：`/etc/sing-box/.sb_state`
- mihomo YAML：`/etc/sing-box/mihomo_proxies.yaml`
- 动态输出命令：`/usr/local/bin/sb`
- Hy2 跳跃规则脚本：`/usr/local/bin/sb-hop.sh`

重新输出节点（动态读取 config.json）：
```bash
sb
```

---

## Hy2 跳跃范围的 URL（最兼容）

脚本输出的 Hy2 Hop 节点采用最兼容写法：

- `host:PORT` 固定为 **Hy2 主端口**
- 跳跃范围写在参数里：`mport=30100-30200`

示例：
```
hysteria2://PASSWORD@IP:40634/?insecure=0&sni=example.com&mport=30100-30200#SB_Hy2_Hop_v4
```

> 不推荐 `IP:30100-30200` 这种写法：很多客户端导入器不支持。

---

## 端口跳跃范围需要放行哪些端口？

必须同时满足：

1) 云厂商安全组/面板：放行 **Hy2 主端口 UDP**  
2) 云厂商安全组/面板：放行 **跳跃范围 UDP**（例如 `30100-30200`）  
3) VPS 内部防火墙：脚本会 best-effort 放行，但云厂商安全组仍需你手动开

---

## 验证跳跃规则是否生效

### nftables（推荐）
```bash
nft list chain inet sbhop prerouting
```

### iptables
```bash
iptables -t nat -vnL PREROUTING --line-numbers
ip6tables -t nat -vnL PREROUTING --line-numbers
```

手动下发跳跃规则（无需重装）：
```bash
/usr/local/bin/sb-hop.sh
systemctl restart sing-box 2>/dev/null || rc-service sing-box restart
```

---

## 管理命令

### Debian / Ubuntu（systemd）
```bash
systemctl status sing-box
journalctl -u sing-box -f
```

cloudflared：
```bash
systemctl status cloudflared
journalctl -u cloudflared -f
```

### Alpine（OpenRC）
```bash
rc-service sing-box status
tail -f /var/log/sing-box.err
```

cloudflared：
```bash
rc-service cloudflared status
ps aux | grep -E "cloudflared|tunnel run" | grep -v grep
```

---

## FAQ

### 1）Argo 本地 127.0.0.1 通，localhost 不通？
通常是 `localhost` 解析到了 `::1`（IPv6 loopback），而你监听的是 `127.0.0.1`。  
用：
```bash
curl -sS --max-time 2 http://127.0.0.1:10086
```

### 2）我 80 被 NPM 占用，ACME 证书怎么签？
选择 **Cloudflare DNS-01**（不占用 80/443）。脚本会提示你输入 `CF_Token`。

### 3）IPv6-only VPS 能访问 IPv4-only 站点吗？
不一定。需要上游提供 **NAT64/464XLAT/DNS64**；否则访问纯 IPv4 站点可能失败。

---

## License
MIT（若仓库另有 License 文件，以仓库声明为准）
