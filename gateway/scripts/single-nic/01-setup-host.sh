#!/bin/bash
set -e

# ============================================================
# 01-setup-host.sh (单网口旁路模式)
# ============================================================

echo "============================================"
echo "  单网口旁路网关 — 宿主机网络配置"
echo "============================================"

# --- 检测网口 ---
echo ""
echo ">>> 检测到的物理网口:"
mapfile -t IFACES < <(ip -br link show | grep -vE "lo|docker|veth|br-" | awk '{print $1}')
if [ ${#IFACES[@]} -eq 0 ]; then
    echo "错误: 未检测到任何网口"
    exit 1
fi

for i in "${!IFACES[@]}"; do
    ip -br addr show "${IFACES[$i]}" | head -1
done

echo ""
read -r -p "使用哪个网口 [${IFACES[0]}]: " NIC
NIC=${NIC:-${IFACES[0]}}

# --- 检测路由器 IP ---
echo ""
echo ">>> 检测当前默认网关 (路由器 IP)"
CURRENT_GW=$(ip route show default | awk '{print $3}' 2>/dev/null || true)
if [ -n "$CURRENT_GW" ]; then
    echo "  检测到: $CURRENT_GW"
else
    CURRENT_GW="192.168.1.254"
    echo "  未检测到, 默认: $CURRENT_GW"
fi

read -r -p "路由器 IP [$CURRENT_GW]: " ROUTER_IP
ROUTER_IP=${ROUTER_IP:-$CURRENT_GW}

# --- N100 自身 IP 和子网 ---
N100_IP="${ROUTER_IP%.*}.1"
read -r -p "N100 本机 IP [$N100_IP]: " INPUT_IP
N100_IP=${INPUT_IP:-$N100_IP}

echo ""
echo "  配置确认:"
echo "    网口:      $NIC"
echo "    N100 IP:   $N100_IP"
echo "    路由器 IP: $ROUTER_IP"
echo ""

# --- IP 转发 ---
echo ">>> 启用 IP 转发..."
cat > /etc/sysctl.d/99-gateway.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-gateway.conf

# --- 配置网口 ---
GATEWAY_DIR="$(dirname "$(readlink -f "$0")")/.."

if command -v netplan &> /dev/null; then
    echo ">>> 使用 netplan 配置..."

    cat > /etc/netplan/01-gateway.yaml << NETPLAN
network:
  version: 2
  renderer: networkd
  ethernets:
    ${NIC}:
      dhcp4: false
      addresses:
        - ${N100_IP}/24
      routes:
        - to: default
          via: ${ROUTER_IP}
NETPLAN

    cp -n /etc/netplan/01-gateway.yaml "${GATEWAY_DIR}/netplan-backup.yaml" 2>/dev/null || true
    netplan apply

elif [ -f /etc/network/interfaces ]; then
    echo ">>> 使用 ifupdown 配置..."
    cp /etc/network/interfaces "${GATEWAY_DIR}/interfaces-backup" 2>/dev/null || true

    cat > /etc/network/interfaces.d/gateway << IFUPDOWN
auto ${NIC}
iface ${NIC} inet static
    address ${N100_IP}/24
    gateway ${ROUTER_IP}
IFUPDOWN

    ifup "${NIC}" 2>/dev/null || echo "请手动重启网络"
else
    echo ">>> 手动配置..."
    ip addr add "${N100_IP}/24" dev "${NIC}" || true
    ip link set "${NIC}" up
    ip route add default via "${ROUTER_IP}" || true
    echo "请自行将以上命令持久化"
fi

# --- 更新 nftables 配置中的变量 ---
echo ""
echo ">>> 更新 nftables-single-nic.conf..."
sed -i "s/define LAN_IF   = eth0/define LAN_IF   = ${NIC}/" "${GATEWAY_DIR}/nftables-single-nic.conf"
sed -i "s/define ROUTER_IP = 192.168.1.254/define ROUTER_IP = ${ROUTER_IP}/" "${GATEWAY_DIR}/nftables-single-nic.conf"

# --- 更新 docker-compose.yml ---
sed -i "s/-i=eth1/-i=${NIC}/" "${GATEWAY_DIR}/docker-compose.yml"

echo ""
echo "============================================"
echo "  配置完成!"
echo "  网口:  ${NIC}"
echo "  IP:    ${N100_IP}"
echo "  路由:  via ${ROUTER_IP}"
echo "============================================"
echo ""
echo "下一步:"
echo "  1. 运行 bash scripts/single-nic/02-nftables-apply.sh"
echo "  2. 去路由器 DHCP 设置中:"
echo "     - 网关 指向 ${N100_IP}"
echo "     - DNS   指向 ${N100_IP}"
echo "  3. 启动 docker compose up -d"
