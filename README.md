# jiankong (监控) — 家庭网络内容过滤网关

为孩子提供可靠的安卓平板上网管控，解决家用路由器黑白名单不稳定、
纯 IP 访问无法拦截的问题。

## 一句话

一台 Linux 小主机 (N100/R4S/树莓派)，串在路由器前面做多层过滤网关。

## 核心能力

- **DNS 域名拦截** — AdGuard Home + 社区 blocklist
- **DNS 强制劫持** — 孩子改 DNS 也没用
- **IP 黑名单** — 直连 IP 访问也能阻断
- **SNI 过滤** — HTTPS 握手阶段按域名拦截
- **Web GUI** — 黑白名单管理、查看上网记录、一键断网/放行
- **按设备分组** — 只管控孩子的平板，不影响家长设备

## 支持两种硬件模式

| 模式 | 硬件要求 | 说明 |
|------|---------|------|
| 双网口串联 (推荐) | 双网口 N100 / 软路由 | 物理接在光猫和路由器之间，全流量过网关 |
| 单网口旁路 | 旧电脑 / NAS / 树莓派 | 只需改路由器 DHCP 设置，性能基本无损 |

## 快速开始

```bash
git clone https://github.com/likesoap/jiankong.git
cd jiankong/gateway
```

## 技术栈

| 层 | 工具 |
|---|------|
| DNS Sinkhole | AdGuard Home (Docker) |
| 流量监控 | ntopng (Docker) |
| 防火墙 | nftables (内核原生) |
| 宿主机 | Debian 12 x86_64 / ARM64 |
