#!/usr/bin/env bash
# ==============================================================================
# Sing-box 终极定制版 v2.7.1 (WARP+Gemini fix) (Fix: Firewall Logic & 1:1 Port Mapping)
# ==============================================================================

set -u

# --- 颜色 ---
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"
info(){ echo -e "${BLUE}[INFO]${PLAIN} $*"; }
ok(){ echo -e "${GREEN}[ OK ]${PLAIN} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
err(){ echo -e "${RED}[ERR ]${PLAIN} $*"; }

# --- Root 检查 ---
[[ ${EUID:-999} -ne 0 ]] && err "必须使用 root 运行此脚本！" && exit 1

# --- 全局配置 ---
SB_USER="sing-box"
SB_GROUP="sing-box"
INSTALL_PATH="/usr/local/bin/sing-box"
CONF_DIR="/etc/sing-box"
CERT_DIR="/etc/sing-box/cert"
SHORTCUT_BIN="/usr/local/bin/sb"
STATE_FILE="/etc/sing-box/.sb_state"
MIHOMO_FILE="/etc/sing-box/mihomo_proxies.yaml"

# --- Cloudflare WARP (用于解锁/避免部分服务不可用) ---
# 用法：
#   默认开启：直接运行脚本即可
#   关闭：SB_WARP=0 bash install.sh
#   修改分流域名：SB_WARP_DOMAINS="openai.com,chatgpt.com,netflix.com" bash install.sh
#   全局走 WARP：SB_WARP_MODE=all bash install.sh
SB_WARP="${SB_WARP:-1}"                     # 1=开启, 0=关闭
SB_WARP_MODE="${SB_WARP_MODE:-selective}"   # selective=仅分流指定域名, all=全局走 WARP
SB_WARP_DOMAINS="${SB_WARP_DOMAINS:-openai.com,chatgpt.com,oaistatic.com,oaiusercontent.com,chat.openai.com,anthropic.com,claude.ai,api.anthropic.com,perplexity.ai,spotify.com,netflix.com,nflxvideo.net,disneyplus.com,disney-plus.net,dssott.com,hbomax.com,max.com,hulu.com,primevideo.com,gemini.google.com,bard.google.com,aistudio.google.com,makersuite.google.com,ai.google.dev,generativelanguage.googleapis.com}"

# --- 系统识别 ---
PKG_MGR="unknown"
command -v apk >/dev/null 2>&1 && PKG_MGR="apk"
command -v apt-get >/dev/null 2>&1 && PKG_MGR="apt"
command -v yum >/dev/null 2>&1 && PKG_MGR="yum"
command -v dnf >/dev/null 2>&1 && PKG_MGR="dnf"

has_systemd(){ command -v systemctl >/dev/null 2>&1; }
has_openrc(){ command -v rc-service >/dev/null 2>&1; }

service_stop(){
  if has_systemd; then systemctl stop sing-box >/dev/null 2>&1 || true
  elif has_openrc; then rc-service sing-box stop >/dev/null 2>&1 || true
  fi
}
service_enable_restart(){
  if has_systemd; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable sing-box >/dev/null 2>&1 || true
    systemctl restart sing-box >/dev/null 2>&1 || true
  elif has_openrc; then
    rc-update add sing-box default >/dev/null 2>&1 || true
    rc-service sing-box restart >/dev/null 2>&1 || rc-service sing-box start >/dev/null 2>&1 || true
  fi
}
service_disable(){
  if has_systemd; then
    systemctl disable --now sing-box >/dev/null 2>&1 || true
  elif has_openrc; then
    rc-service sing-box stop >/dev/null 2>&1 || true
    rc-update del sing-box default >/dev/null 2>&1 || true
  fi
}

# --- 依赖安装 ---
install_pkgs(){
  case "$PKG_MGR" in
    apt)
      apt-get update -y >/dev/null 2>&1
      apt-get install -y bash curl wget tar jq openssl socat lsof net-tools file gzip grep \
        iptables iproute2 nftables ca-certificates coreutils util-linux libcap2-bin tcpdump >/dev/null 2>&1
      ;;
    yum)
      yum update -y >/dev/null 2>&1
      yum install -y bash curl wget tar jq openssl socat lsof net-tools file gzip grep \
        iptables iproute nftables ca-certificates coreutils util-linux libcap tcpdump >/dev/null 2>&1 || true
      ;;
    dnf)
      dnf update -y >/dev/null 2>&1
      dnf install -y bash curl wget tar jq openssl socat lsof net-tools file gzip grep \
        iptables iproute nftables ca-certificates coreutils util-linux libcap tcpdump >/dev/null 2>&1 || true
      ;;
    apk)
      apk add --no-cache bash curl wget tar jq openssl socat lsof net-tools file gzip grep \
        iptables ip6tables nftables iproute2 ca-certificates coreutils util-linux libcap tcpdump >/dev/null 2>&1
      ;;
    *)
      warn "未识别包管理器，跳过依赖安装"
      ;;
  esac
}

# --- WARP 辅助函数 ---
json_array_from_csv(){
  # 输入：逗号分隔字符串；输出：JSON 数组字符串（例如 ["a.com","b.com"]）
  local csv="${1:-}"
  if [[ -z "$csv" ]]; then echo '[]'; return 0; fi
  echo "$csv" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk 'NF' | jq -R . | jq -s .
}

pick_free_port(){
  # 选择一个尽量不冲突的本地监听端口（用于 WARP WireGuard endpoint）
  local p i
  for i in $(seq 1 80); do
    p=$(( (RANDOM % 20000) + 40000 ))  # 40000-59999
    if ! ss -H -lntup 2>/dev/null | awk '{print $5}' | grep -qE "[:\]]${p}$"; then
      echo "$p"; return 0
    fi
  done
  echo 51820
}

download_wgcf(){
  # 下载 wgcf 到 /usr/local/bin/wgcf（如果已存在则跳过）
  command -v wgcf >/dev/null 2>&1 && return 0
  local arch="amd64" tag url
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    i386|i686) arch="386" ;;
    armv7l|armv7) arch="armv7" ;;
    *) arch="amd64" ;;
  esac
  tag="$(curl -fsSL https://api.github.com/repos/ViRb3/wgcf/releases/latest | jq -r .tag_name 2>/dev/null || true)"
  [[ -z "${tag:-}" || "$tag" == "null" ]] && tag="v2.2.30"
  url="https://github.com/ViRb3/wgcf/releases/download/${tag}/wgcf_${tag#v}_linux_${arch}"
  info "下载 wgcf：$url"
  curl -fsSL "$url" -o /usr/local/bin/wgcf || return 1
  chmod +x /usr/local/bin/wgcf || true
  return 0
}

setup_warp(){
  # 生成 WARP WireGuard 配置，并准备 sing-box endpoints / route 片段
  # 输出变量：
  #   WARP_OK=1/0
  #   WARP_ENDPOINT_JSON（带结尾逗号）
  #   WARP_ROUTE_RULE_BOTH（用于 both 模板，带结尾逗号）
  #   WARP_ROUTE_RULE_SINGLE（用于 single 模板，不带结尾逗号）
  WARP_OK=0
  WARP_ENDPOINT_JSON=""
  WARP_ROUTE_RULE_BOTH=""
  WARP_ROUTE_RULE_SINGLE=""

  [[ "${SB_WARP:-1}" == "0" ]] && return 0

  download_wgcf || { warn "wgcf 下载失败，跳过 WARP"; return 0; }

  local warp_dir="${CONF_DIR}/warp"
  local profile="${warp_dir}/wgcf-profile.conf"
  mkdir -p "$warp_dir"

  # 如果没有 profile，则注册并生成（可重复执行，已有文件会跳过）
  if [[ ! -s "$profile" ]]; then
    info "生成 WARP 配置 (wgcf register/generate)"
    ( cd "$warp_dir" && wgcf register --accept-tos >/dev/null 2>&1 && wgcf generate >/dev/null 2>&1 ) || {
      warn "wgcf 注册/生成失败，跳过 WARP（可能是网络/Cloudflare 限制）"
      return 0
    }
  fi

  # 解析 profile
  local pri pub psk endpoint host port
  pri="$(grep -m1 '^PrivateKey' "$profile" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d '\r' || true)"
  pub="$(grep -m1 '^PublicKey' "$profile" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d '\r' || true)"
  psk="$(grep -m1 '^PresharedKey' "$profile" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d '\r' || true)"
  endpoint="$(grep -m1 '^Endpoint' "$profile" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d '\r' || true)"

  [[ -z "${pri:-}" || -z "${pub:-}" || -z "${endpoint:-}" ]] && { warn "解析 WARP 配置失败（缺少关键字段），跳过 WARP"; return 0; }

  # Address / AllowedIPs
  local addrs_json allowed_json
  addrs_json="$(grep '^Address' "$profile" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d '\r' | jq -R . | jq -s .)"
  allowed_json="$(grep '^AllowedIPs' "$profile" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d '\r' | jq -R . | jq -s .)"
  [[ -z "${addrs_json:-}" || "${addrs_json:-}" == "null" ]] && addrs_json='[]'
  [[ -z "${allowed_json:-}" || "${allowed_json:-}" == "null" ]] && allowed_json='["0.0.0.0/0","::/0"]'

  # Endpoint host/port（支持 host:port 与 [ipv6]:port）
  host="$endpoint"; port="2408"
  if [[ "$endpoint" =~ ^\[(.*)\]:(.*)$ ]]; then
    host="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"
  elif [[ "$endpoint" == *:* ]]; then
    host="${endpoint%:*}"; port="${endpoint##*:}"
  fi

  local listen_port
  listen_port="$(pick_free_port)"

  # 避免在 SB_WARP_MODE=all 时产生“走自己”的递归：让 WARP 自己的拨号固定走 direct
  local detour_tag="direct"
  [[ "${OUT_MODE:-single}" == "both" ]] && detour_tag="direct-v4"

  local psk_line=""
  [[ -n "${psk:-}" ]] && psk_line="          \"pre_shared_key\": \"${psk}\","

  # 分流域名列表
  local domains_json
  domains_json="$(json_array_from_csv "${SB_WARP_DOMAINS:-}")"
  [[ "${domains_json:-}" == "[]" ]] && domains_json='["openai.com","chatgpt.com"]'

  # 路由模式：selective / all
  if [[ "${SB_WARP_MODE:-selective}" == "all" ]]; then
    WARP_ROUTE_RULE_SINGLE='      { "outbound": "warp" }'
    WARP_ROUTE_RULE_BOTH='      { "outbound": "warp" },'
  else
    WARP_ROUTE_RULE_SINGLE="      { \"domain_suffix\": ${domains_json}, \"outbound\": \"warp\" }"
    WARP_ROUTE_RULE_BOTH="      { \"domain_suffix\": ${domains_json}, \"outbound\": \"warp\" },"
  fi

  # endpoints JSON（sing-box 1.11+ endpoint/wireguard）
  WARP_ENDPOINT_JSON="$(cat <<JSON
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp",
      "system": false,
      "mtu": 1280,
      "address": ${addrs_json},
      "private_key": "${pri}",
      "listen_port": ${listen_port},
      "detour": "${detour_tag}",
      "peers": [
        {
          "address": "${host}",
          "port": ${port},
          "public_key": "${pub}",
${psk_line}
          "allowed_ips": ${allowed_json},
          "persistent_keepalive_interval": 25
        }
      ],
      "udp_timeout": "5m"
    }
  ],
JSON
)"
  WARP_OK=1
  ok "WARP 已就绪：endpoint=${host}:${port} listen_port=${listen_port} 模式=${SB_WARP_MODE}"
}

# --- 用户/组 ---

group_exists(){
  local g="$1"
  if command -v getent >/dev/null 2>&1; then getent group "$g" >/dev/null 2>&1
  else grep -q "^${g}:" /etc/group 2>/dev/null
  fi
}
user_exists(){ id "$1" >/dev/null 2>&1; }

create_user_group(){
  local u="$1" g="$2"
  local NOLOGIN="/sbin/nologin"
  [[ -x "$NOLOGIN" ]] || NOLOGIN="/bin/false"

  if ! group_exists "$g"; then
    if command -v addgroup >/dev/null 2>&1; then addgroup -S "$g" >/dev/null 2>&1 || true
    elif command -v groupadd >/dev/null 2>&1; then groupadd -r "$g" >/dev/null 2>&1 || true
    fi
  fi
  if ! user_exists "$u"; then
    if command -v adduser >/dev/null 2>&1; then adduser -S -G "$g" -s "$NOLOGIN" "$u" >/dev/null 2>&1 || true
    elif command -v useradd >/dev/null 2>&1; then useradd -r -g "$g" -s "$NOLOGIN" "$u" >/dev/null 2>&1 || true
    fi
  fi
}

# --- 端口工具 ---
port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntu 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"
    return $?
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntu 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"
    return $?
  fi
  return 1
}

find_free_base_port() {
  local need="$1"
  local tries=1200
  while (( tries > 0 )); do
    local base=$(( (RANDOM % 40000) + 20000 ))
    (( base + need - 1 > 65000 )) && tries=$((tries-1)) && continue
    local okflag=1
    for ((i=0;i<need;i++)); do
      local p=$((base+i))
      [[ "$p" == "80" || "$p" == "443" ]] && okflag=0 && break
      port_in_use "$p" && okflag=0 && break
    done
    if (( okflag == 1 )); then echo "$base"; return 0; fi
    tries=$((tries-1))
  done
  return 1
}

default_iface() {
  local iface=""
  iface="$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  [[ -z "$iface" ]] && iface="eth0"
  echo "$iface"
}

# --- 性能调优 ---
apply_tuning() {
  local mem_kb buf_max backlog
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$mem_kb" -ge 2000000 ]]; then
    buf_max=67108864; backlog=50000
  elif [[ "$mem_kb" -ge 800000 ]]; then
    buf_max=33554432; backlog=20000
  else
    buf_max=16777216; backlog=12000
  fi

  mkdir -p /etc/sysctl.d >/dev/null 2>&1 || true
  cat > /etc/sysctl.d/99-singbox-tune.conf <<EOF
net.core.rmem_max=${buf_max}
net.core.wmem_max=${buf_max}
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.netdev_max_backlog=${backlog}

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
EOF
  sysctl -p /etc/sysctl.d/99-singbox-tune.conf >/dev/null 2>&1 || true

  local IFACE
  IFACE="$(default_iface)"
  ip link set dev "$IFACE" txqueuelen 10000 >/dev/null 2>&1 || true
}

# --- 防火墙放行 (Fix: 强制执行 + 步进策略) ---
fw_allow_ports(){
  local tcp_ports="$1" udp_ports="$2" udp_range="${3:-}"

  # [Fix] 删除了之前 "检测到 nft 就直接返回" 的逻辑
  # 现在无论是否有 nft，都会尝试执行 iptables

  if command -v ufw >/dev/null 2>&1; then
    ufw status >/dev/null 2>&1 || true
    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      for p in $tcp_ports; do ufw allow "${p}/tcp" >/dev/null 2>&1 || true; done
      for p in $udp_ports; do ufw allow "${p}/udp" >/dev/null 2>&1 || true; done
      [[ -n "$udp_range" ]] && ufw allow "${udp_range}/udp" >/dev/null 2>&1 || true
      ufw reload >/dev/null 2>&1 || true
      ok "已通过 ufw 放行端口"
      return 0
    fi
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state >/dev/null 2>&1; then
      for p in $tcp_ports; do firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1 || true; done
      for p in $udp_ports; do firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1 || true; done
      [[ -n "$udp_range" ]] && firewall-cmd --permanent --add-port="${udp_range}/udp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      ok "已通过 firewalld 放行端口"
      return 0
    fi
  fi

  # [Fix] 强制使用 iptables，即使底层是 nft
  if command -v iptables >/dev/null 2>&1; then
    # 清理一下旧规则防止堆积 (可选，这里只追加)
    for p in $tcp_ports; do
      iptables -C INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
    done
    for p in $udp_ports; do
      iptables -C INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
    done
    if [[ -n "$udp_range" ]]; then
      local rs="${udp_range%-*}" re="${udp_range#*-}"
      iptables -C INPUT -p udp --dport "${rs}:${re}" -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p udp --dport "${rs}:${re}" -j ACCEPT >/dev/null 2>&1 || true
    fi

# 同步放行 IPv6（ip6tables），否则 IPv6 入站可能不通
if command -v ip6tables >/dev/null 2>&1; then
  for p in $tcp_ports; do
    ip6tables -C INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
  done
  for p in $udp_ports; do
    ip6tables -C INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
  done
  if [[ -n "$udp_range" ]]; then
    local rs6="${udp_range%-*}" re6="${udp_range#*-}"
    ip6tables -C INPUT -p udp --dport "${rs6}:${re6}" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p udp --dport "${rs6}:${re6}" -j ACCEPT >/dev/null 2>&1 || true
  fi
fi
    ok "已通过 iptables 放行端口"
  else
    # [Fix] 如果真的没有 iptables，尝试直接操作 nft
    if command -v nft >/dev/null 2>&1; then

# 尽量按端口逐条添加，兼容不同 nft 语法/链名环境
for p in $tcp_ports; do
  nft add rule inet filter input tcp dport "$p" accept >/dev/null 2>&1 || true
done
for p in $udp_ports; do
  nft add rule inet filter input udp dport "$p" accept >/dev/null 2>&1 || true
done
if [[ -n "$udp_range" ]]; then
  local rs="${udp_range%-*}" re="${udp_range#*-}"
  nft add rule inet filter input udp dport "$rs"-"$re" accept >/dev/null 2>&1 || true
fi
       warn "未找到 iptables，已尝试直接添加 nft 规则"
    fi
  fi
  return 0
}

# --- 卸载 ---
do_uninstall(){
  service_disable
  rm -f /etc/systemd/system/sing-box.service >/dev/null 2>&1 || true
  rm -f /etc/init.d/sing-box >/dev/null 2>&1 || true
  rm -f /usr/local/bin/sb-hop.sh /usr/local/bin/sb-fw.sh /usr/local/bin/sb-selfcheck.sh >/dev/null 2>&1 || true
  rm -f "$SHORTCUT_BIN" >/dev/null 2>&1 || true
  rm -f "$INSTALL_PATH" >/dev/null 2>&1 || true
  rm -rf "$CONF_DIR" >/dev/null 2>&1 || true
  rm -f /etc/sysctl.d/99-singbox-tune.conf >/dev/null 2>&1 || true
  sysctl -p >/dev/null 2>&1 || true
  ok "已卸载 sing-box 相关文件与服务"
  exit 0
}

# --- 参数 ---
case "${1:-}" in
  --uninstall) do_uninstall ;;
esac

clear
echo -e "${BLUE}==============================================================${PLAIN}"
echo -e "${BLUE}   Sing-box 终极定制版 v2.7 (Fix: Firewall Logic Fix)        ${PLAIN}"
echo -e "${BLUE}==============================================================${PLAIN}"

# ============================================================
# [1] 环境初始化
# ============================================================
echo -e "${YELLOW}[1/12] 环境初始化...${PLAIN}"
service_stop
install_pkgs
command -v jq >/dev/null 2>&1 || { err "jq 安装失败"; exit 1; }
create_user_group "$SB_USER" "$SB_GROUP"
mkdir -p "$CONF_DIR" "$CERT_DIR"
chown -R root:"$SB_GROUP" "$CONF_DIR" >/dev/null 2>&1 || true
chmod 750 "$CONF_DIR" "$CERT_DIR" >/dev/null 2>&1 || true
# ============================================================
# [2] 配置收集
# ============================================================
echo -e "${YELLOW}[2/12] 配置收集...${PLAIN}"

IPV4="$(curl -s4m8 --retry 2 ip.sb || true)"
IPV6="$(curl -s6m8 --retry 2 ip.sb || true)"

HAS_V4=0; HAS_V6=0
[[ -n "$IPV4" ]] && HAS_V4=1
[[ -n "$IPV6" ]] && HAS_V6=1

if [[ "$HAS_V4" -ne 1 && "$HAS_V6" -ne 1 ]]; then
  err "无法获取公网 IP（ip.sb），请检查网络/DNS"
  exit 1
fi
echo -e "检测到公网栈：IPv4=${GREEN}${IPV4:-无}${PLAIN}  IPv6=${GREEN}${IPV6:-无}${PLAIN}"

# --- [Fix] 获取本机接口地址（用于 bind），避免在 LXC/容器里绑定公网 IP 导致 "cannot assign requested address" ---
IFACE="$(default_iface)"
LOCAL_IPV4="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
LOCAL_IPV6="$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"

# fallback: 从接口地址中提取（兼容 LXC 的 eth0@ifXXX 显示）
[[ -z "${LOCAL_IPV4:-}" ]] && LOCAL_IPV4="$(ip -4 -o addr show dev "$IFACE" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
[[ -z "${LOCAL_IPV6:-}" ]] && LOCAL_IPV6="$(ip -6 -o addr show dev "$IFACE" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"

# 最后兜底：只有当公网地址确实存在于本机接口时，才允许用公网做 bind（避免容器里绑定公网报错）
if [[ -z "${LOCAL_IPV4:-}" && -n "${IPV4:-}" ]]; then
  ip -4 addr show 2>/dev/null | grep -qw "${IPV4}" && LOCAL_IPV4="${IPV4}"
fi
if [[ -z "${LOCAL_IPV6:-}" && -n "${IPV6:-}" ]]; then
  ip -6 addr show 2>/dev/null | grep -qw "${IPV6}" && LOCAL_IPV6="${IPV6}"
fi
[[ -z "${LOCAL_IPV4:-}" ]] && LOCAL_IPV4="${IPV4:-}"
[[ -z "${LOCAL_IPV6:-}" ]] && LOCAL_IPV6="${IPV6:-}"
info "用于 bind 的本机地址：IPv4=${LOCAL_IPV4:-无}  IPv6=${LOCAL_IPV6:-无} (iface=${IFACE})"

OUT_MODE="ipv4"
if [[ "$HAS_V4" -eq 1 && "$HAS_V6" -eq 1 ]]; then
  echo -e "------------------------------------------------"
  echo -e "节点输出地址选择（双栈 VPS）："
  echo -e "  1) 仅输出 IPv4（默认）"
  echo -e "  2) 仅输出 IPv6"
  echo -e "  3) 同时输出 IPv4 + IPv6"
  read -r -p "请选择 [1-3] (默认1): " SEL || true
  case "${SEL:-1}" in
    2) OUT_MODE="ipv6" ;;
    3) OUT_MODE="both" ;;
    *) OUT_MODE="ipv4" ;;
  esac
else
  [[ "$HAS_V6" -eq 1 && "$HAS_V4" -ne 1 ]] && OUT_MODE="ipv6"
  [[ "$HAS_V4" -eq 1 && "$HAS_V6" -ne 1 ]] && OUT_MODE="ipv4"
fi

if [[ "$OUT_MODE" == "ipv6" ]]; then HOST_PLAIN="$IPV6"
else HOST_PLAIN="${IPV4:-$IPV6}"
fi
ok "输出模式：${OUT_MODE}"

# ------------------------------------------------------------------------------
# 出口栈偏好（解决：选 IPv6 节点但出口仍走 IPv4 的情况）
# - OUT_MODE=ipv4：优先 IPv4 出口
# - OUT_MODE=ipv6：优先 IPv6 出口
# - OUT_MODE=both：按入站(v4/v6)分流到不同 direct 出口
# ------------------------------------------------------------------------------
DIRECT_DOMAIN_STRATEGY="prefer_ipv4"
if [[ "${OUT_MODE}" == "ipv4" ]]; then
  # IPv4 节点：严格只解析 A 记录，避免域名被解析到 IPv6 后走 v6 出站
  DIRECT_DOMAIN_STRATEGY="ipv4_only"
elif [[ "${OUT_MODE}" == "ipv6" ]]; then
  # IPv6 节点：优先解析 AAAA，必要时仍可回退 IPv4（不做 strict-only）
  DIRECT_DOMAIN_STRATEGY="prefer_ipv6"
fi

# 绑定源地址（存在则写入 direct outbound），用于按节点栈优先出站
DIRECT_INET4_LINE=""
DIRECT_INET6_LINE=""
if [[ "${OUT_MODE}" == "ipv4" ]]; then
  [[ -n "${IPV4:-}" ]] && DIRECT_INET4_LINE='      "inet4_bind_address": "'"${LOCAL_IPV4}"'",'
  DIRECT_INET6_LINE=""
elif [[ "${OUT_MODE}" == "ipv6" ]]; then
  [[ -n "${IPV6:-}" ]] && DIRECT_INET6_LINE='      "inet6_bind_address": "'"${LOCAL_IPV6}"'",'
  # IPv6 节点需要访问仅 IPv4 的目标时可回退
  [[ -n "${IPV4:-}" ]] && DIRECT_INET4_LINE='      "inet4_bind_address": "'"${LOCAL_IPV4}"'",'
else
  [[ -n "${IPV4:-}" ]] && DIRECT_INET4_LINE='      "inet4_bind_address": "'"${LOCAL_IPV4}"'",'
  [[ -n "${IPV6:-}" ]] && DIRECT_INET6_LINE='      "inet6_bind_address": "'"${LOCAL_IPV6}"'",'
fi

# 单栈输出模式下的路由块（IPv4 节点：拦截/阻断直连到 IPv6 目标，防止 v6 出站）
ROUTE_SINGLE_LINE='  "route": { "final": "direct", "auto_detect_interface": true },'
if [[ "${OUT_MODE}" == "ipv4" ]]; then
  ROUTE_SINGLE_LINE=$'  "route": {\n    "auto_detect_interface": true,\n    "rules": [\n      { "ip_version": 6, "outbound": "block" }\n    ],\n    "final": "direct"\n  },'
fi


echo -e "------------------------------------------------"
read -r -p "请输入起始端口(回车随机高位): " BASE_PORT || true

NEED_SINGLE=5
NEED_PORTS=$NEED_SINGLE
[[ "$OUT_MODE" == "both" ]] && NEED_PORTS=$((NEED_SINGLE*2))
if [[ -z "${BASE_PORT:-}" ]]; then
  BASE_PORT="$(find_free_base_port "$NEED_PORTS" || true)"
else
  if ! echo "$BASE_PORT" | grep -qE '^[0-9]+$'; then
    BASE_PORT="$(find_free_base_port "$NEED_PORTS" || true)"
  fi
  if [[ "$BASE_PORT" -lt 1024 || $((BASE_PORT+NEED_PORTS-1)) -gt 65535 ]]; then
    BASE_PORT="$(find_free_base_port "$NEED_PORTS" || true)"
  else
    # 用户指定端口也要做占用/黑名单检查（避免 80/443 或已被占用）
    okflag=1
    for ((i=0;i<NEED_PORTS;i++)); do
      p=$((BASE_PORT+i))
      [[ "$p" == "80" || "$p" == "443" ]] && okflag=0 && break
      port_in_use "$p" && okflag=0 && break
    done
    if (( okflag == 0 )); then
      warn "你输入的端口段存在冲突(占用/80/443)，已自动改为随机高位端口"
      BASE_PORT="$(find_free_base_port "$NEED_PORTS" || true)"
    fi
  fi
fi

BASE_PORT_V4="$BASE_PORT"
BASE_PORT_V6=""

if [[ "$OUT_MODE" == "both" ]]; then
  # 双栈顺序端口：v4 用前 NEED_SINGLE 个端口，v6 紧接着使用后 NEED_SINGLE 个端口
  BASE_PORT_V6=$((BASE_PORT_V4 + NEED_SINGLE))
  ok "IPv6 端口组：$BASE_PORT_V6"
fi

P_REALITY4=$BASE_PORT_V4
P_HY2_4=$((BASE_PORT_V4 + 1))
P_TUIC4=$((BASE_PORT_V4 + 2))
P_ANYTLS4=$((BASE_PORT_V4 + 3))
P_SHADOWTLS4=$((BASE_PORT_V4 + 4))

P_REALITY=$P_REALITY4
P_HY2=$P_HY2_4
P_TUIC=$P_TUIC4
P_ANYTLS=$P_ANYTLS4
P_SHADOWTLS=$P_SHADOWTLS4

if [[ "$OUT_MODE" == "both" ]]; then
  P_REALITY6=$BASE_PORT_V6
  P_HY2_6=$((BASE_PORT_V6 + 1))
  P_TUIC6=$((BASE_PORT_V6 + 2))
  P_ANYTLS6=$((BASE_PORT_V6 + 3))
  P_SHADOWTLS6=$((BASE_PORT_V6 + 4))
fi

LISTEN_V4="0.0.0.0"; LISTEN_V6="::"
LISTEN_SINGLE="$LISTEN_V4"
[[ "$OUT_MODE" == "ipv6" ]] && LISTEN_SINGLE="$LISTEN_V6"

echo -e ">>> 端口分配完成"
echo -e "------------------------------------------------"
echo -e ">>> 当前分配端口详情:"
if [[ "$OUT_MODE" == "both" ]]; then
  echo -e "${BLUE}[IPv4]${PLAIN} Reality:${GREEN}${P_REALITY4}${PLAIN} Hy2:${GREEN}${P_HY2_4}${PLAIN} TUIC:${GREEN}${P_TUIC4}${PLAIN} AnyTLS:${GREEN}${P_ANYTLS4}${PLAIN} ST:${GREEN}${P_SHADOWTLS4}${PLAIN}"
  echo -e "${BLUE}[IPv6]${PLAIN} Reality:${GREEN}${P_REALITY6}${PLAIN} Hy2:${GREEN}${P_HY2_6}${PLAIN} TUIC:${GREEN}${P_TUIC6}${PLAIN} AnyTLS:${GREEN}${P_ANYTLS6}${PLAIN} ST:${GREEN}${P_SHADOWTLS6}${PLAIN}"
else
  echo -e "Reality:${GREEN}${P_REALITY}${PLAIN} / Hy2:${GREEN}${P_HY2}${PLAIN} / TUIC:${GREEN}${P_TUIC}${PLAIN} / AnyTLS:${GREEN}${P_ANYTLS}${PLAIN} / ShadowTLS:${GREEN}${P_SHADOWTLS}${PLAIN}"
fi
echo -e "------------------------------------------------"

echo -e "------------------------------------------------"
if [[ "$OUT_MODE" == "both" ]]; then
  read -r -p "请输入 IPv4 跳跃范围(如 31000-32000，回车不跳跃): " USER_HOP_INPUT_V4 || true
  read -r -p "请输入 IPv6 跳跃范围: " USER_HOP_INPUT_V6 || true
else
  read -r -p "请输入跳跃范围(如 31000-32000，回车不跳跃): " USER_HOP_INPUT || true
fi

HOP_PORTS_LINK=""; HOP_PORTS_IPT=""
HOP_MODE="none"; HOP_REDIRECT_ENABLED="0"; HOP_MULTI_ENABLED="0"; HOP_ENGINE="auto"
HOP_PORTS_LINK_V4=""; HOP_PORTS_LINK_V6=""
HOP_ANY="0"

if [[ "$OUT_MODE" == "both" ]]; then
  if [[ -n "${USER_HOP_INPUT_V4:-}" && "$USER_HOP_INPUT_V4" =~ ^[0-9]+-[0-9]+$ ]]; then
    HOP_PORTS_LINK_V4="$USER_HOP_INPUT_V4"; HOP_ANY="1"
  fi
  if [[ -n "${USER_HOP_INPUT_V6:-}" && "$USER_HOP_INPUT_V6" =~ ^[0-9]+-[0-9]+$ ]]; then
    HOP_PORTS_LINK_V6="$USER_HOP_INPUT_V6"; HOP_ANY="1"
  fi
else
  if [[ -n "${USER_HOP_INPUT:-}" && "$USER_HOP_INPUT" =~ ^[0-9]+-[0-9]+$ ]]; then
    HOP_PORTS_LINK="$USER_HOP_INPUT"; HOP_PORTS_LINK_V4="$HOP_PORTS_LINK"; HOP_ANY="1"
  fi
fi

if [[ "$HOP_ANY" == "1" ]]; then HOP_MODE="redirect"; HOP_REDIRECT_ENABLED="1"; HOP_ENGINE="auto"; fi
if [[ -n "${HOP_PORTS_LINK_V4:-}" ]]; then
  HOP_PORTS_LINK="$HOP_PORTS_LINK_V4"
  HOP_PORTS_IPT="${HOP_PORTS_LINK_V4//-/:}"
fi

echo -e "------------------------------------------------"
echo -e "请选择证书模式:"
echo -e "  1. 有域名(ACME)"
echo -e "  2. 无域名(自签，SNI=www.bing.com)"
read -r -p "选择[1-2] 默认1: " CERT_MODE || true
[[ -z "${CERT_MODE:-}" ]] && CERT_MODE=1

DOMAIN=""; USE_ACME=false; SNI_HOST=""; CERT_INSECURE="0"
CERT_PATH="$CERT_DIR/cert.pem"; KEY_PATH="$CERT_DIR/key.pem"

if [[ "$CERT_MODE" == "1" ]]; then
  read -r -p "请输入域名: " DOMAIN || true
  if [[ -z "${DOMAIN:-}" ]]; then warn "未输入域名，切换自签模式"; CERT_MODE=2; else
    USE_ACME=true; SNI_HOST="$DOMAIN"; CERT_INSECURE="0"
    echo -e "ACME 验证方式: 1) DNS-01 (CF API)  2) Standalone HTTP-01"
    read -r -p "请选择 [1-2] (默认1): " ACME_METHOD || true
    if [[ "${ACME_METHOD:-1}" == "1" ]]; then
      ACME_MODE="dns"
      read -r -p "Cloudflare API Token: " CF_Token || true
      if [[ -z "${CF_Token:-}" ]]; then err "缺少 Token，退出"; exit 1; fi
    else ACME_MODE="standalone"; fi
  fi
fi
if [[ "$CERT_MODE" == "2" ]]; then SNI_HOST="www.bing.com"; CERT_INSECURE="1"; fi

read -r -p "Cloudflare Argo Token (不需要回车): " ARGO_TOKEN || true
ARGO_DOMAIN=""
ARGO_PORT=10086
if [[ -n "${ARGO_TOKEN:-}" ]]; then
  read -r -p "Argo 域名 (例 argo.abc.com): " ARGO_DOMAIN || true
  [[ -z "${ARGO_DOMAIN:-}" ]] && ARGO_TOKEN=""
fi

# ============================================================
# [3] 证书处理
# ============================================================
echo -e "${YELLOW}[3/12] 证书处理...${PLAIN}"
if [[ "$CERT_MODE" == "2" ]]; then
  cat > /tmp/sb_openssl.cnf <<EOF
[req]
distinguished_name=req_distinguished_name
x509_extensions=v3_req
prompt=no
[req_distinguished_name]
C=US
O=SingBox
CN=${SNI_HOST}
[v3_req]
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=@alt_names
[alt_names]
DNS.1=${SNI_HOST}
EOF
  openssl req -new -x509 -days 3650 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$KEY_PATH" -out "$CERT_PATH" -config /tmp/sb_openssl.cnf >/dev/null 2>&1 || true
  if [[ ! -s "$CERT_PATH" ]]; then
    openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 \
      -keyout "$KEY_PATH" -out "$CERT_PATH" -config /tmp/sb_openssl.cnf >/dev/null 2>&1 || true
  fi
  rm -f /tmp/sb_openssl.cnf
  ok "自签证书完成"
elif [[ "$USE_ACME" == "true" ]]; then
  curl -s https://get.acme.sh | sh >/dev/null 2>&1 || true
  ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true
  ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
  if [[ "${ACME_MODE:-}" == "dns" ]]; then
    export CF_Token="${CF_Token}"
    ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --keylength ec-256 --force >/dev/null 2>&1 || true
  else
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force >/dev/null 2>&1 || true
  fi
  SB_RELOADCMD='rc-service sing-box restart 2>/dev/null || systemctl restart sing-box'
  ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "$CERT_PATH" --key-file "$KEY_PATH" --reloadcmd "$SB_RELOADCMD" >/dev/null 2>&1 || true
  if [[ ! -s "$CERT_PATH" ]]; then err "证书签发失败"; exit 1; fi
  ok "ACME 证书完成"
fi
chmod 644 "$CERT_PATH" "$KEY_PATH" >/dev/null 2>&1 || true

# ============================================================
# [4] 安装 sing-box
# ============================================================
echo -e "${YELLOW}[4/12] 安装 sing-box...${PLAIN}"
SB_TAG="$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name || true)"
[[ -z "${SB_TAG:-}" || "$SB_TAG" == "null" ]] && SB_TAG="v1.12.0"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) SB_ARCH="amd64" ;;
  aarch64|arm64) SB_ARCH="arm64" ;;
  *) SB_ARCH="amd64" ;;
esac

TMP_DIR="$(mktemp -d 2>/dev/null || echo /tmp/sb.$$)"
mkdir -p "$TMP_DIR"
wget -q -O "$TMP_DIR/sb.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/${SB_TAG}/sing-box-${SB_TAG#v}-linux-${SB_ARCH}.tar.gz" || { err "下载失败"; exit 1; }
tar -xzf "$TMP_DIR/sb.tar.gz" -C "$TMP_DIR"
mv "$TMP_DIR"/sing-box-*/sing-box "$INSTALL_PATH"
rm -rf "$TMP_DIR"
chmod +x "$INSTALL_PATH"
command -v setcap >/dev/null 2>&1 && setcap 'cap_net_bind_service=+ep' "$INSTALL_PATH" >/dev/null 2>&1 || true
ok "sing-box 已安装: $SB_TAG"

# ============================================================
# [5] 生成 config.json
# ============================================================
echo -e "${YELLOW}[5/12] 生成配置文件...${PLAIN}"

# --- [Fix] 重跑脚本时优先复用旧配置里的关键凭据/密钥，避免客户端仍用旧信息导致 unknown user / hmac mismatch ---
OLD_CONF="$CONF_DIR/config.json"
R_PUB_FROM_STATE=""
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" >/dev/null 2>&1 || true
  R_PUB_FROM_STATE="${SB_REALITY_PBK:-}"
fi

UUID=""; TUIC_UUID=""
R_PRI=""; R_PUB=""; SHORT_ID=""
HY2_PASS=""; TUIC_PASS=""; ANYTLS_PASS=""; ST_PASS=""
ST_SS_METHOD=""; ST_SS_KEY=""
ST_LOCAL_PORT=18080
ST_HANDSHAKE_HOST="www.cloudflare.com"
ST_HANDSHAKE_PORT=443
ST_VERSION=3
REALITY_SNI="www.cloudflare.com"
REALITY_HS_SERVER="1.1.1.1"
REALITY_HS_PORT=443

if [[ -s "$OLD_CONF" ]] && jq -e . "$OLD_CONF" >/dev/null 2>&1; then
  UUID="$(jq -r '.inbounds[]? | select(.type=="vless") | .users[0].uuid' "$OLD_CONF" | head -n1)"
  TUIC_UUID="$(jq -r '.inbounds[]? | select(.type=="tuic") | .users[0].uuid' "$OLD_CONF" | head -n1)"

  HY2_PASS="$(jq -r '.inbounds[]? | select(.type=="hysteria2") | .users[0].password' "$OLD_CONF" | head -n1)"
  TUIC_PASS="$(jq -r '.inbounds[]? | select(.type=="tuic") | .users[0].password' "$OLD_CONF" | head -n1)"
  ANYTLS_PASS="$(jq -r '.inbounds[]? | select(.type=="anytls") | .users[0].password' "$OLD_CONF" | head -n1)"
  ST_PASS="$(jq -r '.inbounds[]? | select(.type=="shadowtls") | .users[0].password' "$OLD_CONF" | head -n1)"

  ST_SS_METHOD="$(jq -r '.inbounds[]? | select(.type=="shadowsocks" and .tag=="st-ss-local") | .method' "$OLD_CONF" | head -n1)"
  ST_SS_KEY="$(jq -r '.inbounds[]? | select(.type=="shadowsocks" and .tag=="st-ss-local") | .password' "$OLD_CONF" | head -n1)"

  ST_HANDSHAKE_HOST="$(jq -r '.inbounds[]? | select(.type=="shadowtls") | .handshake.server' "$OLD_CONF" | head -n1)"
  ST_HANDSHAKE_PORT="$(jq -r '.inbounds[]? | select(.type=="shadowtls") | .handshake.server_port' "$OLD_CONF" | head -n1)"
  ST_VERSION="$(jq -r '.inbounds[]? | select(.type=="shadowtls") | .version' "$OLD_CONF" | head -n1)"

  REALITY_SNI="$(jq -r '.inbounds[]? | select(.type=="vless" and (.tls.reality? != null)) | .tls.server_name' "$OLD_CONF" | head -n1)"
  REALITY_HS_SERVER="$(jq -r '.inbounds[]? | select(.type=="vless" and (.tls.reality? != null)) | .tls.reality.handshake.server' "$OLD_CONF" | head -n1)"
  REALITY_HS_PORT="$(jq -r '.inbounds[]? | select(.type=="vless" and (.tls.reality? != null)) | .tls.reality.handshake.server_port' "$OLD_CONF" | head -n1)"

  R_PRI="$(jq -r '.inbounds[]? | select(.type=="vless" and (.tls.reality? != null)) | .tls.reality.private_key' "$OLD_CONF" | head -n1)"
  SHORT_ID="$(jq -r '.inbounds[]? | select(.type=="vless" and (.tls.reality? != null)) | .tls.reality.short_id[0]' "$OLD_CONF" | head -n1)"
fi

# 兜底生成（首次安装/旧配置缺字段）
[[ -z "${UUID:-}" || "${UUID}" == "null" ]] && UUID="$(cat /proc/sys/kernel/random/uuid)"
[[ -z "${TUIC_UUID:-}" || "${TUIC_UUID}" == "null" ]] && TUIC_UUID="$(cat /proc/sys/kernel/random/uuid)"
[[ -z "${SHORT_ID:-}" || "${SHORT_ID}" == "null" ]] && SHORT_ID="$(openssl rand -hex 8)"

[[ -z "${HY2_PASS:-}" || "${HY2_PASS}" == "null" ]] && HY2_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 24)"
[[ -z "${TUIC_PASS:-}" || "${TUIC_PASS}" == "null" ]] && TUIC_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 24)"
[[ -z "${ANYTLS_PASS:-}" || "${ANYTLS_PASS}" == "null" ]] && ANYTLS_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 24)"
[[ -z "${ST_PASS:-}" || "${ST_PASS}" == "null" ]] && ST_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 24)"
[[ -z "${ST_SS_METHOD:-}" || "${ST_SS_METHOD}" == "null" ]] && ST_SS_METHOD="2022-blake3-aes-256-gcm"
[[ -z "${ST_SS_KEY:-}" || "${ST_SS_KEY}" == "null" ]] && ST_SS_KEY="$(openssl rand 32 | base64 | tr -d '\n')"

# Reality 密钥：如果旧配置可复用 private_key + state 里有 public_key，则直接复用；否则生成一套新的
if [[ -n "${R_PRI:-}" && "${R_PRI}" != "null" && -n "${R_PUB_FROM_STATE:-}" ]]; then
  R_PUB="$R_PUB_FROM_STATE"
else
  REALITY_KEY="$($INSTALL_PATH generate reality-keypair 2>&1)"
  echo "$REALITY_KEY" | grep -qi "Usage:" && REALITY_KEY="$($INSTALL_PATH generate reality-key 2>&1)"
  R_PRI="$(echo "$REALITY_KEY" | grep -i "Private" | awk '{print $2}')"
  R_PUB="$(echo "$REALITY_KEY" | grep -i "Public" | awk '{print $2}')"
fi

HOP_EXTRA_INBOUNDS=""; HOP_MAX=1000; HOP_SAMPLE_NOTE=""
append_hop_range() {
  local range="$1" listen="$2" tagprefix="$3"
  [[ -z "${range:-}" ]] && return 0
  [[ "$range" =~ ^[0-9]+-[0-9]+$ ]] || return 0
  local HS="${range%-*}" HE="${range#*-}"
  local count=$((HE - HS + 1)); local step=1
  # [Fix] Native Multi-port: Must ensure step=1 to match client hopping logic
  # Limit to 1000 ports max to prevent huge config
  if [[ "$count" -gt "$HOP_MAX" ]]; then
    warn "跳跃端口范围过大 ($count > $HOP_MAX)，已自动限制为前 $HOP_MAX 个端口"
    HE=$((HS + HOP_MAX - 1))
  fi
  
  for ((p=HS; p<=HE; p+=step)); do
    HOP_EXTRA_INBOUNDS="${HOP_EXTRA_INBOUNDS},
    {
      \"type\": \"hysteria2\",
      \"tag\": \"${tagprefix}-${p}\",
      \"listen\": \"${listen}\",
      \"listen_port\": ${p},
      \"users\": [{ \"password\": \"${HY2_PASS}\" }],
      \"ignore_client_bandwidth\": true,
      \"tls\": { \"enabled\": true, \"alpn\": [\"h3\"], \"certificate_path\": \"${CERT_PATH}\", \"key_path\": \"${KEY_PATH}\" }
    }"
  done
}

# Force Native Multi-port Logic
if [[ "$HOP_MODE" == "multiport" ]]; then
  if [[ "$OUT_MODE" == "both" ]]; then
    append_hop_range "${HOP_PORTS_LINK_V4:-}" "$LISTEN_V4" "hy2-hop-v4"
    append_hop_range "${HOP_PORTS_LINK_V6:-}" "$LISTEN_V6" "hy2-hop-v6"
  else
    append_hop_range "${HOP_PORTS_LINK_V4:-}" "$LISTEN_SINGLE" "hy2-hop"
  fi
fi

ARGO_INB=""
if [[ -n "$ARGO_TOKEN" && -n "$ARGO_DOMAIN" ]]; then
  ARGO_INB=",
    {
      \"type\": \"vless\",
      \"tag\": \"vless-argo-in\",
      \"listen\": \"127.0.0.1\",
      \"listen_port\": ${ARGO_PORT},
      \"users\": [{ \"uuid\": \"${UUID}\" }],
      \"transport\": {
        \"type\": \"ws\",
        \"path\": \"/argo\"
      }
    }"
fi


# ============================================================
# [WARP] 生成 WARP endpoint（可选）
# ============================================================
setup_warp

# 单栈模式：如果启用了 WARP，则给 route 加入分流/全局规则
if [[ "${WARP_OK:-0}" -eq 1 ]]; then
  ROUTE_SINGLE_LINE="$(cat <<EOF
  "route": {
    "auto_detect_interface": true,
    "rules": [
${WARP_ROUTE_RULE_SINGLE}
    ],
    "final": "direct"
  },
EOF
)"
fi

if [[ "$OUT_MODE" == "both" ]]; then
cat > "$CONF_DIR/config.json" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "dns": { "servers": [ { "type": "local", "tag": "local" } ] },
  ${WARP_ENDPOINT_JSON}  "route": {
    "auto_detect_interface": true,
    "rules": [
${WARP_ROUTE_RULE_BOTH}
      { "inbound": ["vless-reality-v4","hy2-in-v4","tuic-in-v4","anytls-in-v4","shadowtls-in-v4"], "ip_version": 6, "outbound": "block" },
      { "inbound": ["vless-reality-v6","hy2-in-v6","tuic-in-v6","anytls-in-v6","shadowtls-in-v6"], "outbound": "direct-v6" },
      { "inbound": ["vless-reality-v4","hy2-in-v4","tuic-in-v4","anytls-in-v4","shadowtls-in-v4"], "outbound": "direct-v4" },
      { "inbound": ["vless-argo-in"], "outbound": "direct-v4" }
    ],
    "final": "direct-v4"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-v4",
      "listen": "${LISTEN_V4}",
      "listen_port": ${P_REALITY4},
      "users": [{ "uuid": "${UUID}", "flow": "xtls-rprx-vision" }],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${REALITY_HS_SERVER}", "server_port": ${REALITY_HS_PORT} },
          "private_key": "${R_PRI}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality-v6",
      "listen": "${LISTEN_V6}",
      "listen_port": ${P_REALITY6},
      "users": [{ "uuid": "${UUID}", "flow": "xtls-rprx-vision" }],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${REALITY_HS_SERVER}", "server_port": ${REALITY_HS_PORT} },
          "private_key": "${R_PRI}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in-v4",
      "listen": "${LISTEN_V4}",
      "listen_port": ${P_HY2_4},
      "users": [{ "password": "${HY2_PASS}" }],
      "ignore_client_bandwidth": true,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in-v6",
      "listen": "${LISTEN_V6}",
      "listen_port": ${P_HY2_6},
      "users": [{ "password": "${HY2_PASS}" }],
      "ignore_client_bandwidth": true,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    }${HOP_EXTRA_INBOUNDS},
    {
      "type": "tuic",
      "tag": "tuic-in-v4",
      "listen": "${LISTEN_V4}",
      "listen_port": ${P_TUIC4},
      "users": [{ "uuid": "${TUIC_UUID}", "password": "${TUIC_PASS}" }],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-in-v6",
      "listen": "${LISTEN_V6}",
      "listen_port": ${P_TUIC6},
      "users": [{ "uuid": "${TUIC_UUID}", "password": "${TUIC_PASS}" }],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-in-v4",
      "listen": "${LISTEN_V4}",
      "listen_port": ${P_ANYTLS4},
      "users": [{ "name": "user", "password": "${ANYTLS_PASS}" }],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "alpn": ["h2", "http/1.1"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-in-v6",
      "listen": "${LISTEN_V6}",
      "listen_port": ${P_ANYTLS6},
      "users": [{ "name": "user", "password": "${ANYTLS_PASS}" }],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "alpn": ["h2", "http/1.1"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "st-ss-local",
      "listen": "127.0.0.1",
      "listen_port": ${ST_LOCAL_PORT},
      "method": "${ST_SS_METHOD}",
      "password": "${ST_SS_KEY}",
      "network": "tcp"
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-in-v4",
      "listen": "${LISTEN_V4}",
      "listen_port": ${P_SHADOWTLS4},
      "version": ${ST_VERSION},
      "users": [{ "password": "${ST_PASS}" }],
      "handshake": { "server": "${ST_HANDSHAKE_HOST}", "server_port": ${ST_HANDSHAKE_PORT} },
      "detour": "st-ss-local"
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-in-v6",
      "listen": "${LISTEN_V6}",
      "listen_port": ${P_SHADOWTLS6},
      "version": ${ST_VERSION},
      "users": [{ "password": "${ST_PASS}" }],
      "handshake": { "server": "${ST_HANDSHAKE_HOST}", "server_port": ${ST_HANDSHAKE_PORT} },
      "detour": "st-ss-local"
    }${ARGO_INB}
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-v4",
      "inet4_bind_address": "${LOCAL_IPV4}",
      "domain_resolver": { "server": "local", "strategy": "ipv4_only" }
    },
    {
      "type": "direct",
      "tag": "direct-v6",
      "inet6_bind_address": "${LOCAL_IPV6}",
      "domain_resolver": { "server": "local", "strategy": "prefer_ipv6" }
    },
    { "type": "block", "tag": "block" }
  ]
}
EOF
else
cat > "$CONF_DIR/config.json" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "dns": { "servers": [ { "type": "local", "tag": "local" } ] },
  ${WARP_ENDPOINT_JSON}  ${ROUTE_SINGLE_LINE}
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "${LISTEN_SINGLE}",
      "listen_port": ${P_REALITY},
      "users": [{ "uuid": "${UUID}", "flow": "xtls-rprx-vision" }],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${REALITY_HS_SERVER}", "server_port": ${REALITY_HS_PORT} },
          "private_key": "${R_PRI}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "${LISTEN_SINGLE}",
      "listen_port": ${P_HY2},
      "users": [{ "password": "${HY2_PASS}" }],
      "ignore_client_bandwidth": true,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    }${HOP_EXTRA_INBOUNDS},
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "${LISTEN_SINGLE}",
      "listen_port": ${P_TUIC},
      "users": [{ "uuid": "${TUIC_UUID}", "password": "${TUIC_PASS}" }],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "${LISTEN_SINGLE}",
      "listen_port": ${P_ANYTLS},
      "users": [{ "name": "user", "password": "${ANYTLS_PASS}" }],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "alpn": ["h2", "http/1.1"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "st-ss-local",
      "listen": "127.0.0.1",
      "listen_port": ${ST_LOCAL_PORT},
      "method": "${ST_SS_METHOD}",
      "password": "${ST_SS_KEY}",
      "network": "tcp"
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-in",
      "listen": "${LISTEN_SINGLE}",
      "listen_port": ${P_SHADOWTLS},
      "version": ${ST_VERSION},
      "users": [{ "password": "${ST_PASS}" }],
      "handshake": { "server": "${ST_HANDSHAKE_HOST}", "server_port": ${ST_HANDSHAKE_PORT} },
      "detour": "st-ss-local"
    }${ARGO_INB}
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
${DIRECT_INET4_LINE}
${DIRECT_INET6_LINE}
      "domain_resolver": { "server": "local", "strategy": "${DIRECT_DOMAIN_STRATEGY}" }
    },
    { "type": "block", "tag": "block" }
  ]
}
EOF
fi

chown root:"$SB_GROUP" "$CONF_DIR/config.json" >/dev/null 2>&1 || true
chmod 640 "$CONF_DIR/config.json" >/dev/null 2>&1 || true
if ! jq . "$CONF_DIR/config.json" >/dev/null 2>&1; then
  err "config.json JSON 格式错误，已停止（避免启动失败）。请检查脚本输出，或把 /etc/sing-box/config.json 发我排查。"
  exit 1
fi
ok "配置已生成"

# ============================================================
# [6] Cloudflared
# ============================================================
if [[ -n "${ARGO_TOKEN:-}" && -n "${ARGO_DOMAIN:-}" ]]; then
  echo -e "${YELLOW}[6/12] 配置 cloudflared...${PLAIN}"
  if ! command -v cloudflared >/dev/null 2>&1; then
    wget -q -O /usr/local/bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${SB_ARCH}" || true
    chmod +x /usr/local/bin/cloudflared >/dev/null 2>&1 || true
  fi
  if command -v cloudflared >/dev/null 2>&1; then
    if has_systemd; then
      cloudflared service install "$ARGO_TOKEN" >/dev/null 2>&1 || true

      # --- QUIC 优先，失败自动降级 HTTP2（解决 UDP/QUIC 不通导致 systemd 15s 超时） ---
      cf_write_override() {
        local proto="$1"
        mkdir -p /etc/systemd/system/cloudflared.service.d >/dev/null 2>&1 || true
        cat > /etc/systemd/system/cloudflared.service.d/override.conf <<EOF
[Service]
# 用 simple 避免 notify + TimeoutStartSec=15 导致启动被 systemd 判定超时
Type=simple
TimeoutStartSec=0

# 覆盖 ExecStart（必须先清空再写）
ExecStart=
ExecStart=/usr/local/bin/cloudflared --no-autoupdate tunnel run --protocol ${proto} --token ${ARGO_TOKEN}

Restart=on-failure
RestartSec=5s
EOF
      }

      cf_connected() {
        journalctl -u cloudflared -n 160 --no-pager 2>/dev/null | grep -Eqi           "Registered tunnel connection|Connection.*registered|Connected to.*edge|Tunnel.*connected|Serve tunnel|Started.*tunnel"
      }

      cf_quic_failed() {
        journalctl -u cloudflared -n 160 --no-pager 2>/dev/null | grep -Eqi           "Failed to dial a quic connection|timeout: no recent network activity|timeout.*quic|quic.*timeout"
      }

      cf_try_proto() {
        local proto="$1" wait_s="${2:-20}"
        cf_write_override "$proto"
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl restart cloudflared >/dev/null 2>&1 || true
        for ((i=0; i<wait_s; i++)); do
          cf_connected && return 0
          sleep 1
        done
        return 1
      }

      # 先尝试 QUIC
      if cf_try_proto "quic" 15; then
        ok "cloudflared 已通过 QUIC 连接"
      else
        if cf_quic_failed; then
          warn "cloudflared QUIC 连接失败，自动切换到 HTTP2"
        else
          warn "cloudflared QUIC 未在限定时间内连上，尝试切换到 HTTP2"
        fi
        if cf_try_proto "http2" 25; then
          ok "cloudflared 已通过 HTTP2 连接"
        else
          warn "cloudflared HTTP2 也未能连上：journalctl -u cloudflared -n 200 --no-pager"
        fi
      fi
    elif has_openrc; then
      cat > /etc/init.d/cloudflared <<EOF
#!/sbin/openrc-run
name="cloudflared"
command="/usr/local/bin/cloudflared"
command_args="tunnel run --protocol http2 --token ${ARGO_TOKEN}"
command_background=true
pidfile="/run/cloudflared.pid"
depend() { need net; }
EOF
      chmod +x /etc/init.d/cloudflared; rc-update add cloudflared default; rc-service cloudflared restart
    fi
    ok "cloudflared 已配置"
  else
    warn "cloudflared 安装失败"
  fi
fi

# ============================================================
# [7] Hy2 端口跳跃 (推荐：Redirect NAT，范围才稳定)
# ============================================================
echo -e "${YELLOW}[7/12] Hy2 端口跳跃处理...${PLAIN}"

# 说明：
# - Hysteria2 的 mport(端口跳跃)在多数客户端是“会在范围内切换目的端口”，
#   仅靠 sing-box 多端口监听通常无法保持同一条 QUIC 连接稳定（范围越大越容易掉）。
# - 最稳定做法：把跳跃范围的 UDP 端口【重定向】到主 Hy2 端口（目的端口保持不变）。
# - 优先使用 nftables，其次 iptables；若内核无 NAT（裁剪/LXC），自动降级为 socat 中继（可用但性能略差）。

cat > /usr/local/bin/sb-hop.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

# 说明：
# - Hysteria2 的 mport(端口跳跃)在多数客户端会在范围内切换“目的端口”
# - 最稳定做法：将跳跃范围 UDP 端口 REDIRECT 到主 Hy2 端口（端口映射 1:N）
# - 优先 nftables，其次 iptables；若内核无 NAT（裁剪/LXC），降级为 socat 中继（可用但性能略差）
#
# 关键修复：
# - 定时任务/多次运行不再 flush 整条链，避免“短暂无规则/偶发失败导致整段失效”
# - OUT_MODE=ipv6 时也会为 IPv6 安装跳跃规则（之前只在 both 时装 v6，容易导致 v6 间歇/失效）

HOP_V4="${HOP_PORTS_LINK_V4:-}"
HOP_V6="${HOP_PORTS_LINK_V6:-}"
OUT_MODE="${OUT_MODE}"
HY2_V4="${P_HY2_4}"
HY2_V6="${P_HY2_6:-${P_HY2_4}}"

# 清理旧的 socat 中继
PIDF="/run/sb-hop-relay.pids"
if [[ -f "\$PIDF" ]]; then
  while read -r p; do kill "\$p" >/dev/null 2>&1 || true; done < "\$PIDF"
  rm -f "\$PIDF" >/dev/null 2>&1 || true
fi

range_to_hilo() {
  local s="\$1"
  if [[ "\$s" =~ ^[0-9]+$ ]]; then
    echo "\$s \$s"
    return 0
  fi
  if [[ "\$s" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    local a="\${BASH_REMATCH[1]}" b="\${BASH_REMATCH[2]}"
    if (( a > b )); then echo "\$b \$a"; else echo "\$a \$b"; fi
    return 0
  fi
  return 1
}

_need_v4=0; _need_v6=0
R4=""; R6=""; P4=""; P6=""
case "\$OUT_MODE" in
  ipv4)
    [[ -n "\$HOP_V4" ]] && _need_v4=1 && R4="\$HOP_V4" && P4="\$HY2_V4"
    ;;
  ipv6)
    # 只有 ipv6 输出时，跳跃输入沿用 HOP_V4（用户只输入一份），规则安装到 IPv6
    [[ -n "\$HOP_V4" ]] && _need_v6=1 && R6="\$HOP_V4" && P6="\$HY2_V6"
    ;;
  both)
    [[ -n "\$HOP_V4" ]] && _need_v4=1 && R4="\$HOP_V4" && P4="\$HY2_V4"
    [[ -n "\$HOP_V6" ]] && _need_v6=1 && R6="\$HOP_V6" && P6="\$HY2_V6"
    ;;
esac

# 未启用跳跃直接退出
if (( _need_v4==0 && _need_v6==0 )); then
  exit 0
fi

nft_add_or_replace_rule() {
  local nfproto="\$1" comment="\$2" range="\$3" toport="\$4"
  [[ -z "\$range" ]] && return 0
  read -r HS HE < <(range_to_hilo "\$range") || return 1

  local want_dport
  if [[ "\$HS" == "\$HE" ]]; then
    want_dport="udp dport \$HS"
  else
    want_dport="udp dport \$HS-\$HE"
  fi

  local cur
  cur="\$(nft -a list chain inet sbhop prerouting 2>/dev/null || true)"

  # 已存在且匹配则不动（避免定时运行破坏连接）
  if echo "\$cur" | grep -F "comment \"\$comment\"" | grep -F "meta nfproto \$nfproto" | grep -F "\$want_dport" | grep -F "redirect to :\$toport" >/dev/null 2>&1; then
    return 0
  fi

  # 先尝试添加新规则；成功后再清理旧规则（避免“先删后加”造成窗口期/失败导致失效）
  if [[ "\$HS" == "\$HE" ]]; then
    nft add rule inet sbhop prerouting meta nfproto "\$nfproto" udp dport "\$HS" redirect to ":\$toport" comment "\$comment" >/dev/null 2>&1 || return 1
  else
    nft add rule inet sbhop prerouting meta nfproto "\$nfproto" udp dport "\$HS-\$HE" redirect to ":\$toport" comment "\$comment" >/dev/null 2>&1 || return 1
  fi

  # 删除旧的同 comment 规则（只删同 nfproto 的）
  echo "\$cur" | awk -v c="\$comment" -v p="\$nfproto" '
    \$0 ~ "comment \\""c"\\"" && \$0 ~ "meta nfproto "p {
      for(i=1;i<=NF;i++) if(\$i=="handle") print \$(i+1)
    }' | while read -r h; do
      [[ -n "\$h" ]] && nft delete rule inet sbhop prerouting handle "\$h" >/dev/null 2>&1 || true
    done

  return 0
}

nft_apply() {
  command -v nft >/dev/null 2>&1 || return 1

  nft list table inet sbhop >/dev/null 2>&1 || nft add table inet sbhop >/dev/null 2>&1 || return 1
  if ! nft list chain inet sbhop prerouting >/dev/null 2>&1; then
    nft add chain inet sbhop prerouting '{ type nat hook prerouting priority -100; }' >/dev/null 2>&1 || return 1
  fi

  # 规则尽量只“补齐/替换”，不 flush
  if (( _need_v4==1 )); then
    nft_add_or_replace_rule ipv4 "sb-hop-v4" "\$R4" "\$P4" || return 1
  fi
  if (( _need_v6==1 )); then
    nft_add_or_replace_rule ipv6 "sb-hop-v6" "\$R6" "\$P6" || return 1
  fi
  return 0
}

ipt_apply() {
  command -v iptables >/dev/null 2>&1 || return 1

  # v4
  if (( _need_v4==1 )); then
    read -r HS HE < <(range_to_hilo "\$R4") || return 1
    local R="\${HS}:\${HE}"
    iptables -t nat -C PREROUTING -p udp --dport "\$R" -j REDIRECT --to-ports "\$P4" 2>/dev/null || \
      iptables -t nat -A PREROUTING -p udp --dport "\$R" -j REDIRECT --to-ports "\$P4"
  fi

  # v6
  if (( _need_v6==1 )) && command -v ip6tables >/dev/null 2>&1; then
    read -r HS HE < <(range_to_hilo "\$R6") || return 1
    local R="\${HS}:\${HE}"
    ip6tables -t nat -C PREROUTING -p udp --dport "\$R" -j REDIRECT --to-ports "\$P6" 2>/dev/null || \
      ip6tables -t nat -A PREROUTING -p udp --dport "\$R" -j REDIRECT --to-ports "\$P6"
  fi
  return 0
}

socat_fallback() {
  command -v socat >/dev/null 2>&1 || return 1
  : > "\$PIDF"

  # v4 中继
  if (( _need_v4==1 )); then
    read -r HS HE < <(range_to_hilo "\$R4") || return 1
    for ((p=HS; p<=HE; p++)); do
      socat -T120 UDP4-RECVFROM:"\$p",fork,reuseaddr UDP4:127.0.0.1:"\$P4" >/dev/null 2>&1 &
      echo "\$!" >> "\$PIDF"
    done
  fi

  # v6 中继
  if (( _need_v6==1 )); then
    read -r HS HE < <(range_to_hilo "\$R6") || return 1
    for ((p=HS; p<=HE; p++)); do
      socat -T120 UDP6-RECVFROM:"\$p",fork,reuseaddr UDP6:[::1]:"\$P6" >/dev/null 2>&1 &
      echo "\$!" >> "\$PIDF"
    done
  fi

  return 0
}

# 优先 nft，其次 iptables，最后 socat
if nft_apply; then
  exit 0
fi
if ipt_apply; then
  exit 0
fi
socat_fallback || true
exit 0
EOF
chmod +x /usr/local/bin/sb-hop.sh
/usr/local/bin/sb-hop.sh >/dev/null 2>&1 || true

chmod +x /usr/local/bin/sb-hop.sh >/dev/null 2>&1 || true

if [[ "$HOP_ANY" == "1" ]]; then
  ok "Hy2 跳跃已启用：将通过 nft/iptables REDIRECT(优先) 或 socat(降级) 实现"
else
  info "未启用端口跳跃"
fi

# ============================================================
# [8] 防火墙

# ============================================================
echo -e "${YELLOW}[8/12] 防火墙放行...${PLAIN}"
TCP_ALLOW="${P_REALITY} ${P_ANYTLS} ${P_SHADOWTLS}"
UDP_ALLOW="${P_HY2} ${P_TUIC}"
UDP_RANGE_ALLOW=""
[[ -n "${HOP_PORTS_LINK_V4:-}" ]] && UDP_RANGE_ALLOW="${HOP_PORTS_LINK_V4}"
if [[ "$OUT_MODE" == "both" ]]; then
  TCP_ALLOW="$TCP_ALLOW ${P_REALITY6} ${P_ANYTLS6} ${P_SHADOWTLS6}"
  UDP_ALLOW="$UDP_ALLOW ${P_HY2_6} ${P_TUIC6}"
fi
fw_allow_ports "$TCP_ALLOW" "$UDP_ALLOW" "$UDP_RANGE_ALLOW"
if [[ "$OUT_MODE" == "both" && -n "${HOP_PORTS_LINK_V6:-}" ]]; then
  fw_allow_ports "" "" "${HOP_PORTS_LINK_V6}"
fi

# ============================================================
# [9] 调优 & [10] State
# ============================================================
echo -e "${YELLOW}[9/12] 调优...${PLAIN}"
apply_tuning
echo -e "${YELLOW}[10/12] 写入状态...${PLAIN}"
cat > "$STATE_FILE" <<EOF
SB_HOST_IP="${HOST_PLAIN}"
SB_IPV4="${IPV4}"
SB_IPV6="${IPV6}"
SB_OUT_MODE="${OUT_MODE}"
SB_HY2_PORT4="${P_HY2_4}"
SB_HY2_PORT6="${P_HY2_6:-}"
SB_TUIC_PORT4="${P_TUIC4}"
SB_TUIC_PORT6="${P_TUIC6:-}"
SB_SNI_HOST="${SNI_HOST}"
SB_CERT_INSECURE="${CERT_INSECURE}"
SB_REALITY_PBK="${R_PUB}"
SB_ARGO_DOMAIN="${ARGO_DOMAIN}"
SB_ARGO_PORT="${ARGO_PORT}"
SB_HOP_PORTS="${HOP_PORTS_LINK_V4}"
SB_HOP_PORTS_V6="${HOP_PORTS_LINK_V6}"
SB_HOP_MODE="${HOP_MODE}"
SB_HOP_MULTI_ENABLED="${HOP_MULTI_ENABLED}"
SB_HOP_REDIRECT_ENABLED="${HOP_REDIRECT_ENABLED}"
SB_HOP_ENGINE="${HOP_ENGINE}"
EOF
chmod 600 "$STATE_FILE"

# ============================================================
# [11] 服务
# ============================================================
echo -e "${YELLOW}[11/12] 安装服务...${PLAIN}"
if has_systemd; then
  cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target
[Service]
User=root
Group=root
LimitNOFILE=1048576
ExecStartPre=-/usr/local/bin/sb-hop.sh
ExecStart=$INSTALL_PATH run -c $CONF_DIR/config.json
Restart=on-failure
RestartSec=1
[Install]
WantedBy=multi-user.target
EOF
elif has_openrc; then
  cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
name="sing-box"
command="$INSTALL_PATH"
command_args="run -c $CONF_DIR/config.json"
command_background=true
pidfile="/run/sing-box.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.err"
rc_ulimit="-n 1048576"
start_pre() { /usr/local/bin/sb-hop.sh >/dev/null 2>&1 || true; }
depend() { need net; }
EOF
  chmod +x /etc/init.d/sing-box
fi
service_enable_restart

# ============================================================
# [12] SB 脚本
# ============================================================
echo -e "${YELLOW}[12/12] 生成 sb 命令...${PLAIN}"
cat > "$SHORTCUT_BIN" <<'EOSB'
#!/usr/bin/env bash
set -u
CONF="/etc/sing-box/config.json"
STATE="/etc/sing-box/.sb_state"
MIHOMO_FILE="/etc/sing-box/mihomo_proxies.yaml"
command -v jq >/dev/null 2>&1 || { echo "jq missing"; exit 1; }
[[ -f "$CONF" ]] || exit 1
[[ -f "$STATE" ]] && source "$STATE"
SB_HOST_IP="${SB_HOST_IP:-}"
SB_IPV4="${SB_IPV4:-}"
SB_IPV6="${SB_IPV6:-}"
SB_OUT_MODE="${SB_OUT_MODE:-}"
SB_SNI_HOST="${SB_SNI_HOST:-www.bing.com}"
SB_ARGO_DOMAIN="${SB_ARGO_DOMAIN:-}"
SB_HOP_PORTS="${SB_HOP_PORTS:-}"
SB_HOP_PORTS_V6="${SB_HOP_PORTS_V6:-}"
SB_HOP_MODE="${SB_HOP_MODE:-none}"
SB_HOP_MULTI_ENABLED="${SB_HOP_MULTI_ENABLED:-0}"
SB_HOP_REDIRECT_ENABLED="${SB_HOP_REDIRECT_ENABLED:-0}"
SB_HOP_ENGINE="${SB_HOP_ENGINE:-none}"
SB_CERT_INSECURE="${SB_CERT_INSECURE:-1}"
SB_REALITY_PBK="${SB_REALITY_PBK:-}"

urlsafe_base64() {
  if command -v base64 >/dev/null 2>&1; then
    if base64 --help 2>&1 | grep -q ' -w '; then base64 -w 0 | tr '+/' '-_' | tr -d '='; else base64 | tr -d '\n' | tr '+/' '-_' | tr -d '='; fi
  else cat; fi
}
url_host() { local h="$1"; [[ "$h" == *:* ]] && echo "[$h]" || echo "$h"; }
yaml_host() { local h="$1"; echo "\"$h\""; }

HOSTS=(); LABELS=()
mode="${SB_OUT_MODE:-}"
if [[ -z "$mode" ]]; then [[ -n "$SB_HOST_IP" ]] && HOSTS+=("$SB_HOST_IP") && LABELS+=(""); else
  case "$mode" in
    both)
      [[ -n "$SB_IPV4" ]] && HOSTS+=("$SB_IPV4") && LABELS+=("v4")
      [[ -n "$SB_IPV6" ]] && HOSTS+=("$SB_IPV6") && LABELS+=("v6")
      ;;
    ipv6) [[ -n "$SB_IPV6" ]] && HOSTS+=("$SB_IPV6") && LABELS+=("");;
    ipv4|*) [[ -n "$SB_IPV4" ]] && HOSTS+=("$SB_IPV4") && LABELS+=("");;
  esac
fi
[[ "${#HOSTS[@]}" -eq 0 && -n "$SB_HOST_IP" ]] && HOSTS+=("$SB_HOST_IP") && LABELS+=("")

INSECURE="$SB_CERT_INSECURE"
SNI_HOST="$SB_SNI_HOST"

UUID_R="$(jq -r '.inbounds[] | select(.tag|test("^vless-reality")) | .users[0].uuid' "$CONF" | head -n1)"
SNI_R="$(jq -r  '.inbounds[] | select(.tag|test("^vless-reality")) | .tls.server_name' "$CONF" | head -n1)"
SID_R="$(jq -r  '.inbounds[] | select(.tag|test("^vless-reality")) | .tls.reality.short_id[0]' "$CONF" | head -n1)"
PORT_R_SINGLE="$(jq -r '.inbounds[] | select(.tag=="vless-reality") | .listen_port' "$CONF" | head -n1)"
PORT_R4="$(jq -r '.inbounds[] | select(.tag=="vless-reality-v4") | .listen_port' "$CONF" | head -n1)"
PORT_R6="$(jq -r '.inbounds[] | select(.tag=="vless-reality-v6") | .listen_port' "$CONF" | head -n1)"
[[ -z "$PORT_R4" ]] && PORT_R4="$PORT_R_SINGLE"
[[ -z "$PORT_R6" ]] && PORT_R6="$PORT_R_SINGLE"

HY_PWD="$(jq -r '.inbounds[] | select(.tag|test("^hy2-in")) | .users[0].password' "$CONF" | head -n1)"
PORT_H_SINGLE="$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .listen_port' "$CONF" | head -n1)"
PORT_H4="$(jq -r '.inbounds[] | select(.tag=="hy2-in-v4") | .listen_port' "$CONF" | head -n1)"
PORT_H6="$(jq -r '.inbounds[] | select(.tag=="hy2-in-v6") | .listen_port' "$CONF" | head -n1)"
[[ -z "$PORT_H4" ]] && PORT_H4="$PORT_H_SINGLE"
[[ -z "$PORT_H6" ]] && PORT_H6="$PORT_H_SINGLE"

TU_UUID="$(jq -r '.inbounds[] | select(.tag|test("^tuic-in")) | .users[0].uuid' "$CONF" | head -n1)"
TU_PWD="$(jq -r  '.inbounds[] | select(.tag|test("^tuic-in")) | .users[0].password' "$CONF" | head -n1)"
PORT_T_SINGLE="$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .listen_port' "$CONF" | head -n1)"
PORT_T4="$(jq -r '.inbounds[] | select(.tag=="tuic-in-v4") | .listen_port' "$CONF" | head -n1)"
PORT_T6="$(jq -r '.inbounds[] | select(.tag=="tuic-in-v6") | .listen_port' "$CONF" | head -n1)"
[[ -z "$PORT_T4" ]] && PORT_T4="$PORT_T_SINGLE"
[[ -z "$PORT_T6" ]] && PORT_T6="$PORT_T_SINGLE"

ANY_PWD="$(jq -r '.inbounds[] | select(.tag|test("^anytls-in")) | .users[0].password' "$CONF" | head -n1)"
PORT_A_SINGLE="$(jq -r '.inbounds[] | select(.tag=="anytls-in") | .listen_port' "$CONF" | head -n1)"
PORT_A4="$(jq -r '.inbounds[] | select(.tag=="anytls-in-v4") | .listen_port' "$CONF" | head -n1)"
PORT_A6="$(jq -r '.inbounds[] | select(.tag=="anytls-in-v6") | .listen_port' "$CONF" | head -n1)"
[[ -z "$PORT_A4" ]] && PORT_A4="$PORT_A_SINGLE"
[[ -z "$PORT_A6" ]] && PORT_A6="$PORT_A_SINGLE"

ST_PWD="$(jq -r '.inbounds[] | select(.tag|test("^shadowtls-in")) | .users[0].password' "$CONF" | head -n1)"
ST_HOST="$(jq -r '.inbounds[] | select(.tag|test("^shadowtls-in")) | .handshake.server' "$CONF" | head -n1)"
ST_VER="$(jq -r '.inbounds[] | select(.tag|test("^shadowtls-in")) | .version' "$CONF" | head -n1)"
ST_PORT_SINGLE="$(jq -r '.inbounds[] | select(.tag=="shadowtls-in") | .listen_port' "$CONF" | head -n1)"
ST_PORT4="$(jq -r '.inbounds[] | select(.tag=="shadowtls-in-v4") | .listen_port' "$CONF" | head -n1)"
ST_PORT6="$(jq -r '.inbounds[] | select(.tag=="shadowtls-in-v6") | .listen_port' "$CONF" | head -n1)"
[[ -z "$ST_PORT4" ]] && ST_PORT4="$ST_PORT_SINGLE"
[[ -z "$ST_PORT6" ]] && ST_PORT6="$ST_PORT_SINGLE"

SS_M=$(jq -r '.inbounds[] | select(.tag=="st-ss-local") | .method' "$CONF")
SS_P=$(jq -r '.inbounds[] | select(.tag=="st-ss-local") | .password' "$CONF")
SS_BASE=$(echo -n "${SS_M}:${SS_P}" | urlsafe_base64)
PLUGIN_URL="shadow-tls;host=${ST_HOST};password=${ST_PWD};version=${ST_VER}"
PLUGIN_URL="${PLUGIN_URL//;/\%3B}"
PLUGIN_URL="${PLUGIN_URL//=/\%3D}"

LINK_ARGO=""
if [[ -n "$SB_ARGO_DOMAIN" ]]; then
  LINK_ARGO="vless://${UUID_R}@${SB_ARGO_DOMAIN}:443?encryption=none&security=tls&type=ws&host=${SB_ARGO_DOMAIN}&path=%2Fargo#SB_Argo"
fi

LINKS=()
add_link(){ LINKS+=("$1"); echo "$1"; }
multi=0; [[ "${#HOSTS[@]}" -gt 1 ]] && multi=1

for i in "${!HOSTS[@]}"; do
  HOST_IP="${HOSTS[$i]}"; HOST_URL="$(url_host "$HOST_IP")"
  if [[ "$HOST_IP" == *:* ]]; then
    PORT_R="$PORT_R6"; PORT_H="$PORT_H6"; PORT_T="$PORT_T6"; PORT_A="$PORT_A6"; ST_PORT="$ST_PORT6"; HOP_RANGE="${SB_HOP_PORTS_V6:-$SB_HOP_PORTS}"
  else
    PORT_R="$PORT_R4"; PORT_H="$PORT_H4"; PORT_T="$PORT_T4"; PORT_A="$PORT_A4"; ST_PORT="$ST_PORT4"; HOP_RANGE="$SB_HOP_PORTS"
  fi
  suf=""; if [[ "$multi" -eq 1 ]]; then lab="${LABELS[$i]}"; [[ -n "$lab" ]] && suf="_${lab}"; fi

  add_link "vless://${UUID_R}@${HOST_URL}:${PORT_R}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI_R}&fp=chrome&pbk=${SB_REALITY_PBK}&sid=${SID_R}&type=tcp&headerType=none#SB_Reality${suf}"
  if [[ -n "$HOP_RANGE" ]]; then
    add_link "hysteria2://${HY_PWD}@${HOST_URL}:${PORT_H}?insecure=${INSECURE}&sni=${SNI_HOST}&mport=${HOP_RANGE}#SB_Hy2_Hop${suf}"
  else
    add_link "hysteria2://${HY_PWD}@${HOST_URL}:${PORT_H}?insecure=${INSECURE}&sni=${SNI_HOST}#SB_Hy2${suf}"
  fi
  add_link "tuic://${TU_UUID}:${TU_PWD}@${HOST_URL}:${PORT_T}?congestion_control=bbr&alpn=h3&sni=${SNI_HOST}&allow_insecure=${INSECURE}#SB_Tuic${suf}"
  add_link "anytls://${ANY_PWD}@${HOST_URL}:${PORT_A}?sni=${SNI_HOST}&insecure=${INSECURE}#SB_AnyTLS${suf}"
  add_link "ss://${SS_BASE}@${HOST_URL}:${ST_PORT}?plugin=${PLUGIN_URL}#SB_ShadowTLS${suf}"
done
[[ -n "$LINK_ARGO" ]] && add_link "$LINK_ARGO"

{
  echo; echo "========== Mihomo Proxies YAML =========="
  [[ -n "$SB_HOP_PORTS" || -n "$SB_HOP_PORTS_V6" ]] && echo "# Hop: mode=${SB_HOP_MODE} multi=${SB_HOP_MULTI_ENABLED}"
  for i in "${!HOSTS[@]}"; do
    HOST_IP="${HOSTS[$i]}"; HOST_YAML="$(yaml_host "$HOST_IP")"
    if [[ "$HOST_IP" == *:* ]]; then
      PORT_R="$PORT_R6"; PORT_H="$PORT_H6"; PORT_T="$PORT_T6"; PORT_A="$PORT_A6"; ST_PORT="$ST_PORT6"; HOP_RANGE="${SB_HOP_PORTS_V6:-$SB_HOP_PORTS}"
    else
      PORT_R="$PORT_R4"; PORT_H="$PORT_H4"; PORT_T="$PORT_T4"; PORT_A="$PORT_A4"; ST_PORT="$ST_PORT4"; HOP_RANGE="$SB_HOP_PORTS"
    fi
    suf=""; if [[ "$multi" -eq 1 ]]; then lab="${LABELS[$i]}"; [[ -n "$lab" ]] && suf="_${lab}"; fi

cat <<YAML
- name: SB_Reality${suf}
  type: vless
  server: ${HOST_YAML}
  port: ${PORT_R}
  uuid: ${UUID_R}
  udp: true
  network: tcp
  flow: xtls-rprx-vision
  tls: true
  servername: ${SNI_R}
  client-fingerprint: chrome
  reality-opts: { public-key: ${SB_REALITY_PBK}, short-id: ${SID_R} }
YAML
    if [[ -n "$HOP_RANGE" ]]; then
cat <<YAML
- name: SB_Hy2_Hop${suf}
  type: hysteria2
  server: ${HOST_YAML}
  ports: "${HOP_RANGE}"
  password: ${HY_PWD}
  sni: ${SNI_HOST}
  skip-cert-verify: $( [[ "$INSECURE" == "1" ]] && echo "true" || echo "false" )
  alpn: [h3]
  udp: true
YAML
    else
cat <<YAML
- name: SB_Hy2${suf}
  type: hysteria2
  server: ${HOST_YAML}
  port: ${PORT_H}
  password: ${HY_PWD}
  sni: ${SNI_HOST}
  skip-cert-verify: $( [[ "$INSECURE" == "1" ]] && echo "true" || echo "false" )
  alpn: [h3]
  udp: true
YAML
    fi
cat <<YAML
- name: SB_Tuic${suf}
  type: tuic
  server: ${HOST_YAML}
  port: ${PORT_T}
  uuid: ${TU_UUID}
  password: ${TU_PWD}
  alpn: [h3]
  sni: ${SNI_HOST}
  skip-cert-verify: $( [[ "$INSECURE" == "1" ]] && echo "true" || echo "false" )
  udp-relay-mode: native
  congestion-controller: bbr
YAML
cat <<YAML
- name: SB_AnyTLS${suf}
  type: anytls
  server: ${HOST_YAML}
  port: ${PORT_A}
  password: ${ANY_PWD}
  client-fingerprint: chrome
  udp: true
  sni: ${SNI_HOST}
  alpn: [h2, http/1.1]
  skip-cert-verify: $( [[ "$INSECURE" == "1" ]] && echo "true" || echo "false" )
YAML
cat <<YAML
- name: SB_ShadowTLS${suf}
  type: ss
  server: ${HOST_YAML}
  port: ${ST_PORT}
  cipher: ${SS_M}
  password: "${SS_P}"
  udp: false
  plugin: shadow-tls
  client-fingerprint: chrome
  plugin-opts: { host: "${ST_HOST}", password: "${ST_PWD}", version: ${ST_VER} }
YAML
  done
  if [[ -n "$SB_ARGO_DOMAIN" ]]; then
cat <<YAML
- name: SB_Argo
  type: vless
  server: ${SB_ARGO_DOMAIN}
  port: 443
  uuid: ${UUID_R}
  udp: true
  tls: true
  servername: ${SB_ARGO_DOMAIN}
  network: ws
  ws-opts: { path: /argo, headers: { Host: ${SB_ARGO_DOMAIN} } }
YAML
  fi
} | tee "$MIHOMO_FILE" >/dev/null
EOSB
chmod +x "$SHORTCUT_BIN"
ok "SB 脚本生成完毕"

# ============================================================
# [自检]
# ============================================================
echo -e "${YELLOW}[自检] 安装后自检...${PLAIN}"
set +u
cat > /usr/local/bin/sb-selfcheck.sh <<EOF
#!/usr/bin/env bash
set -u
CONF="${CONF_DIR}/config.json"
STATE="${STATE_FILE}"
echo "== sing-box check =="
"${INSTALL_PATH}" check -c "\$CONF" 2>&1 || true
echo "== service status =="
if command -v systemctl >/dev/null 2>&1; then systemctl is-active sing-box 2>/dev/null || true
else rc-service sing-box status 2>/dev/null || true; fi

echo
echo "== Argo Check =="
if [[ -f "\$STATE" ]]; then source "\$STATE"; fi
if [[ -n "\${SB_ARGO_DOMAIN:-}" ]]; then
  echo "Argo Enabled. Please ensure Cloudflare Tunnel points to: http://localhost:\${SB_ARGO_PORT:-10086}"
  curl -sS --max-time 1 http://127.0.0.1:\${SB_ARGO_PORT:-10086} >/dev/null && echo "Local WS Port Open: YES" || echo "Local WS Port Open: NO (Check Service)"
fi
EOF
chmod +x /usr/local/bin/sb-selfcheck.sh
/usr/local/bin/sb-selfcheck.sh 2>/dev/null || true

echo -e "\n${GREEN}=== 部署完成 ===${PLAIN}"
echo -e ">>> 输入 ${GREEN}sb${PLAIN} 查看节点链接"
"$SHORTCUT_BIN"
