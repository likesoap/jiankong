#!/bin/bash
set -e

# ============================================================
# 01-setup-host.sh — N100 宿主机初始网络配置
# ============================================================

echo "============================================"
echo "  Gateway Host 网络配置脚本"
echo "============================================"

# --- 检测网口 ---
echo ""
echo ">>> 检测到的物理网口:"
mapfile -t IFACES < <(ip -br link show | grep -vE "lo|docker|veth|br-" | awk '{print $1}')
for i in "${!IFACES[@]}"; do
    ip -br addr show "${IFACES[$i]}" | head -1
done

if [ ${#IFACES[@]} -lt 2 ]; then
    echo "错误: 至少需要 2 个网口 (WAN + LAN)"
    exit 1
fi

echo ""
echo ">>> 请确认网口角色:"
echo "    WAN 口 (接光猫/上游路由器) —— 通常已获取到 IP 的那个"
echo "    LAN 口 (接 Cudy AP / 交换机) —— 通常尚未配置 IP"
echo ""

read -r -p "WAN 口名称 [${IFACES[0]}]: " WAN_IF
WAN_IF=${WAN_IF:-${IFACES[0]}}

read -r -p "LAN 口名称 [${IFACES[1]}]: " LAN_IF
LAN_IF=${LAN_IF:-${IFACES[1]}}

if [ "$WAN_IF" = "$LAN_IF" ]; then
    echo "错误: WAN 和 LAN 不能是同一个网口"
    exit 1
fi

# --- IP 转发 ---
echo ""
echo ">>> 启用 IP 转发..."
cat > /etc/sysctl.d/99-gateway.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-gateway.conf

# --- 检测 netplan 还是 ifupdown ---
GATEWAY_DIR="$(dirname "$(readlink -f "$0")")"

if command -v netplan &> /dev/null; then
    echo ">>> 使用 netplan 配置..."

    cat > /etc/netplan/01-gateway.yaml << NETPLAN
network:
  version: 2
  renderer: networkd
  ethernets:
    ${WAN_IF}:
      dhcp4: true
      dhcp4-overrides:
        use-dns: false
    ${LAN_IF}:
      dhcp4: false
      addresses:
        - 10.0.0.1/24
NETPLAN

    # 备份旧 netplan
    cp -n /etc/netplan/01-gateway.yaml "${GATEWAY_DIR}/netplan-backup.yaml" 2>/dev/null || true

    netplan apply
    echo "netplan 配置完成"

elif [ -f /etc/network/interfaces ]; then
    echo ">>> 使用 ifupdown 配置..."

    cp /etc/network/interfaces "${GATEWAY_DIR}/interfaces-backup" 2>/dev/null || true

    cat > /etc/network/interfaces.d/gateway << IFUPDOWN
auto ${LAN_IF}
iface ${LAN_IF} inet static
    address 10.0.0.1/24
IFUPDOWN

    ifup "${LAN_IF}" 2>/dev/null || echo "请手动重启网络或执行: ifup ${LAN_IF}"
else
    echo ">>> 未检测到 netplan/ifupdown, 手动配置 ${LAN_IF}..."
    ip addr add 10.0.0.1/24 dev "${LAN_IF}" || true
    ip link set "${LAN_IF}" up
    echo "手动配置了 ${LAN_IF}，请自行持久化到对应网络管理工具"
fi

# --- 更新 nftables.conf 中的接口变量 ---
echo ""
echo ">>> 更新 nftables.conf..."
sed -i "s/define LAN_IF   = eth1/define LAN_IF   = ${LAN_IF}/" "${GATEWAY_DIR}/nftables.conf"
sed -i "s/define WAN_IF   = eth0/define WAN_IF   = ${WAN_IF}/" "${GATEWAY_DIR}/nftables.conf"

# --- 更新 docker-compose.yml 中的 ntopng 监听接口 ---
sed -i "s/-i=eth1/-i=${LAN_IF}/" "${GATEWAY_DIR}/docker-compose.yml"

echo ""
echo "============================================"
echo "  配置完成!"
echo "  WAN:  ${WAN_IF} (DHCP)"
echo "  LAN:  ${LAN_IF} (10.0.0.1/24)"
echo "============================================"
echo ""
echo "下一步: 运行 02-nftables-apply.sh"
