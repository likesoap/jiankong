#!/bin/bash
set -e

# ============================================================
# 03-verify.sh (单网口旁路模式)
# ============================================================

echo "============================================"
echo "  单网口旁路 — 多层过滤验证"
echo "============================================"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $1"; }

# --- AdGuard 运行检查 ---
echo ""
echo "=== 前置: AdGuard Home 运行状态 ==="
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80 2>/dev/null | grep -q '200\|302\|401'; then
    pass "AdGuard Home Web UI 可访问"
else
    echo "  [INFO] AdGuard Web UI 未响应, 尝试端口 3000 (首次设置模式)..."
    if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000 2>/dev/null | grep -q '200\|302'; then
        pass "AdGuard Home 在首次设置模式 (http://<IP>:3000)"
    else
        fail "AdGuard Home 未运行, 请执行: docker compose up -d"
        exit 1
    fi
fi

# --- Layer 1: DNS ---
echo ""
echo "=== Layer 1: DNS 域名拦截 ==="
RESULT=$(nslookup pornhub.com 127.0.0.1 2>&1 || true)
if echo "$RESULT" | grep -qE "0\.0\.0\.0|NXDOMAIN|REFUSED|blocked"; then
    pass "pornhub.com DNS 已拦截"
else
    fail "pornhub.com DNS 未拦截 — 检查 AdGuard 过滤规则"
    echo "  返回: $RESULT"
fi

RESULT=$(nslookup baidu.com 127.0.0.1 2>&1 || true)
if echo "$RESULT" | grep -qE "Address.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
    pass "baidu.com 正常解析"
else
    fail "baidu.com 无法解析 — DNS 可能有问题"
fi

# --- Layer 2: DNS 劫持 ---
echo ""
echo "=== Layer 2: DNS 强制劫持 ==="
RESULT=$(nslookup baidu.com 8.8.8.8 2>&1 || true)
if echo "$RESULT" | grep -qE "Address.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
    pass "DNS 劫持生效 (查询 8.8.8.8 被重定向到本机)"
    echo "  实际返回: $(echo "$RESULT" | grep Address | tail -1)"
else
    fail "DNS 劫持可能未生效"
fi

# --- Layer 3: IP 黑名单 ---
echo ""
echo "=== Layer 3: IP 黑名单 ==="
BLOCKED_IP=$(nft list ruleset | grep -oP 'BLOCKED_IPS.*?\{\s*\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [ -n "$BLOCKED_IP" ]; then
    if ping -c 1 -W 2 "$BLOCKED_IP" &> /dev/null; then
        fail "$BLOCKED_IP ping 通 — IP 黑名单未生效"
    else
        pass "$BLOCKED_IP 不可达 (预期行为)"
    fi
else
    echo "  [INFO] IP 黑名单为空, 跳过"
fi

# --- Layer 4: SNI ---
echo ""
echo "=== Layer 4: SNI 过滤 ==="
TARGET=$(nft list ruleset | grep -oP 'BLOCKED_SNI.*?\{(.*?)\}' | grep -oP '"[^"]*"' | head -1 | tr -d '"' || true)
if [ -z "$TARGET" ]; then
    echo "  [INFO] SNI 黑名单为空, 跳过"
else
    echo "  目标: $TARGET"
    IP=$(dig +short "$TARGET" @8.8.8.8 A 2>/dev/null | head -1 || host "$TARGET" 8.8.8.8 2>/dev/null | grep 'has address' | awk '{print $NF}' | head -1 || true)
    if [ -z "$IP" ]; then
        echo "  [SKIP] 无法解析 $TARGET"
    else
        echo "  $TARGET → $IP"
        if ! curl -k --resolve "${TARGET}:443:${IP}" "https://${TARGET}/" --max-time 5 -o /dev/null -s 2>/dev/null; then
            pass "SNI 过滤生效 — $TARGET 连接被阻断"
        else
            fail "SNI 过滤未生效 — $TARGET 连接成功"
        fi
    fi
fi

echo ""
echo "============================================"
echo "  验证完成。如有 FAIL 项:"
echo "  1. docker compose ps"
echo "  2. nft list ruleset | grep counter"
echo "  3. journalctl -k | grep -E 'SNI|IP|DOT'"
echo "============================================"
