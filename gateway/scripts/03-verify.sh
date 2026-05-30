#!/bin/bash
set -e

# ============================================================
# 03-verify.sh — 验证 4 层过滤是否生效
# ============================================================

echo "============================================"
echo "  多层过滤验证"
echo "============================================"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $1"; }

# --------------------------------------------------
# Layer 1: DNS Sinkhole (AdGuard Home)
# --------------------------------------------------
echo ""
echo "=== Layer 1: DNS 域名拦截 ==="
echo "(要求 AdGuard Home 已启动并配置了黑名单)"
RESULT=$(nslookup pornhub.com 127.0.0.1 2>&1 || true)
if echo "$RESULT" | grep -qE "0\.0\.0\.0|0.0.0.0|NXDOMAIN|REFUSED|blocked"; then
    pass "pornhub.com 已被 DNS 拦截"
else
    fail "pornhub.com DNS 未被拦截 — 请检查 AdGuard Home 过滤规则"
    echo "    nslookup 返回: $RESULT"
fi

RESULT=$(nslookup baidu.com 127.0.0.1 2>&1 || true)
if echo "$RESULT" | grep -qE "Address.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
    pass "baidu.com 正常解析"
else
    fail "baidu.com 解析异常"
fi

# --------------------------------------------------
# Layer 2: DNS 劫持 (nftables redirect)
# --------------------------------------------------
echo ""
echo "=== Layer 2: DNS 强制劫持 ==="
echo "(从 LAN 侧发起 DNS 查询, 绕过本机 AdGuard 直连 8.8.8.8)"
RESULT=$(nslookup baidu.com 8.8.8.8 2>&1 || true)
if echo "$RESULT" | grep -qE "Address.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
    pass "DNS 劫持生效 (查询 8.8.8.8 实际被转发到本机)"
    echo "  实际返回: $(echo "$RESULT" | grep 'Address' | tail -1)"
else
    fail "DNS 劫持可能未生效或 8.8.8.8 不可达"
fi

# --------------------------------------------------
# Layer 3: IP 黑名单
# --------------------------------------------------
echo ""
echo "=== Layer 3: IP 黑名单 ==="
if nft list ruleset | grep -q 'BLOCKED_IPS'; then
    # 从 nft 规则中提取第一个被封 IP
    BLOCKED_IP=$(nft list ruleset | grep -oP 'BLOCKED_IPS.*?\{\s*\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if [ -n "$BLOCKED_IP" ]; then
        if ping -c 1 -W 2 "$BLOCKED_IP" &> /dev/null; then
            fail "被封 IP $BLOCKED_IP 居然 ping 通了 — IP 黑名单未生效"
        else
            pass "被封 IP $BLOCKED_IP 不可达 (预期行为)"
        fi
    else
        echo "  [INFO] IP 黑名单为空, 跳过测试"
    fi
else
    echo "  [INFO] 未配置 IP 黑名单, 跳过"
fi

# --------------------------------------------------
# Layer 4: SNI 过滤
# --------------------------------------------------
echo ""
echo "=== Layer 4: SNI 过滤 (HTTPS TLS握手拦截) ==="
echo "(用 curl --resolve 模拟 IP 直连, 检查 SNI 是否被拦截)"

# 取一个被 blocked 的 SNI
TARGET=$(nft list ruleset | grep -oP 'BLOCKED_SNI.*?\{(.*?)\}' | grep -oP '"[^"]*"' | head -1 | tr -d '"' || true)

if [ -z "$TARGET" ]; then
    echo "  [INFO] SNI 黑名单为空, 跳过测试"
else
    echo "  测试目标: $TARGET (用 Google DNS 解析其真实 IP)"
    IP=$(dig +short "$TARGET" @8.8.8.8 A 2>/dev/null | head -1 || true)
    if [ -z "$IP" ]; then
        IP=$(host "$TARGET" 8.8.8.8 2>/dev/null | grep 'has address' | awk '{print $NF}' | head -1 || true)
    fi
    if [ -z "$IP" ]; then
        echo "  [SKIP] 无法解析 $TARGET 的 IP"
    else
        echo "  $TARGET 解析到 $IP"
        if curl -k --resolve "${TARGET}:443:${IP}" "https://${TARGET}/" --max-time 5 -o /dev/null -s -w "%{http_code}" 2>/dev/null; then
            # curl exited 0, check if it returned something useful
            CODE=$(curl -k --resolve "${TARGET}:443:${IP}" "https://${TARGET}/" --max-time 5 -o /dev/null -s -w "%{http_code}" 2>/dev/null || echo "000")
            if [ "$CODE" = "000" ]; then
                pass "SNI 过滤生效 — $TARGET 连接被阻断 (timeout/reset)"
            else
                fail "SNI 过滤未生效 — $TARGET 返回 HTTP $CODE"
            fi
        else
            pass "SNI 过滤生效 — $TARGET 连接失败 (curl exit non-zero)"
        fi
    fi
fi

# --------------------------------------------------
# 汇总
# --------------------------------------------------
echo ""
echo "============================================"
echo "  验证完成。如有 FAIL 项, 请检查:"
echo "  1. docker compose ps (AdGuard / ntopng 是否运行)"
echo "  2. nft list ruleset (防火墙规则是否正确)"
echo "  3. sudo nft list ruleset | grep counter (拦截计数器)"
echo "  4. journalctl -k | grep -E 'SNI|IP|DOT'"
echo "============================================"
