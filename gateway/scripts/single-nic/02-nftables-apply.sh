#!/bin/bash
set -e

# ============================================================
# 02-nftables-apply.sh (单网口旁路模式)
# ============================================================

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONF="${SCRIPT_DIR}/../../nftables-single-nic.conf"

if [ ! -f "$CONF" ]; then
    echo "错误: 未找到 $CONF"
    exit 1
fi

echo ">>> 检查 nft..."
if ! command -v nft &> /dev/null; then
    echo "安装 nftables..."
    apt update && apt install -y nftables
fi

echo ">>> 加载 nftables 规则..."
nft -f "$CONF"
echo "  已加载 $(nft list ruleset | wc -l) 行规则"

# 禁用 Debian 原生 nftables.service, 避免和我们的规则冲突
systemctl disable --now nftables 2>/dev/null || true

echo ""
echo ">>> 持久化 (systemd)..."
cat > /etc/systemd/system/nftables-gateway.service << SVC
[Unit]
Description=Gateway nftables rules (single-nic bypass mode)
Documentation=file:${CONF}
Before=network.target
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f ${CONF}
ExecReload=/usr/sbin/nft -f ${CONF}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable --now nftables-gateway.service

echo ""
echo "============================================"
echo "  nftables 已加载并持久化"
echo ""
echo "  常用命令:"
echo "  nft list ruleset                   查看全部规则"
echo "  systemctl reload nftables-gateway  重新加载"
echo "  journalctl -k | grep -E 'SNI|IP|DOT'  查看拦截日志"
echo "============================================"
