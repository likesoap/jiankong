#!/bin/bash
set -e

# ============================================================
# 02-nftables-apply.sh — 加载防火墙规则并持久化
# ============================================================

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONF="${SCRIPT_DIR}/../nftables.conf"

if [ ! -f "$CONF" ]; then
    echo "错误: 未找到 nftables.conf"
    exit 1
fi

echo ">>> 检查 nft 命令..."
if ! command -v nft &> /dev/null; then
    echo "nft 未安装, 正在安装..."
    apt update && apt install -y nftables
fi

echo ">>> 加载 nftables 规则..."
nft -f "$CONF"
echo "  已加载 $(nft list ruleset | grep -c 'define\|chain\|rule') 条规则"

# 禁用 Debian 原生 nftables.service, 避免和我们的规则冲突
systemctl disable --now nftables 2>/dev/null || true

echo ""
echo ">>> 持久化 (systemd service)..."
cat > /etc/systemd/system/nftables-gateway.service << 'SVC'
[Unit]
Description=Gateway nftables rules (DNS hijack + IP/SNI filter)
Documentation=file:/opt/gateway/nftables.conf
Before=network.target
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /opt/gateway/nftables.conf
ExecReload=/usr/sbin/nft -f /opt/gateway/nftables.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC

# 如果脚本目录不是 /opt/gateway, 修正路径
sed -i "s|/opt/gateway/nftables.conf|$CONF|g" /etc/systemd/system/nftables-gateway.service

systemctl daemon-reload
systemctl enable --now nftables-gateway.service

echo "nftables 持久化完成"
echo ""
echo "============================================"
echo "  常用管理命令:"
echo "  nft list ruleset             查看全部规则"
echo "  systemctl reload nftables-gateway   重新加载"
echo "  journalctl -k | grep -E 'SNI|IP|DOT'   查看拦截日志"
echo "============================================"
