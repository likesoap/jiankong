# 不吵架的上网管理：家用网络内容过滤与监控

> **方案选择**:
> - **零改动，纯 DNS 过滤**? 跳转到 [纯 DNS 模式 (零部署)](#纯-dns-模式-零部署)
> - **单网口设备 (旧电脑/NAS/树莓派)**? 跳转到 [单网口旁路网关方案](#单网口旁路网关方案)
> - **双网口设备 (N100 软路由/多网口主机)**? 按下方主流程 (串联网关，最完整)

## 项目初衷

在家庭环境中，孩子正处于身心发展的关键阶段，自控力尚在培养，
更容易被短视频、游戏、社交网络等内容吸引，难以专注于学习任务。

作为家长，我们不希望每天因为"该关掉平板了"而和孩子反复争执，
也不想一刀切地禁止所有电子设备使用——那既不现实，也不是教育的初衷。

因此，这个项目的目标不是"一刀切断网"，而是在**网络层面建立一个
透明、可调节的辅助工具**：

- 家长可以通过 Web 面板查看孩子访问了哪些网站，了解上网习惯
- 自动拦截不适合未成年人的内容（成人网站、赌博等）
- 为学习时段和休息时段设置不同的规则
- 让孩子在一个相对安全、有限的网络环境中，逐步培养自我管理的能力

这个方案**不依赖孩子的配合**（不需安装任何 app），所有过滤在
网络层完成，孩子无法绕过设备上的家长控制。

## 前置条件

以下条件缺一不可。如果某项不满足，该模式无法正常运行，请先确认再开始部署。

> **说明**: 笔者使用 Cudy WR3600E WiFi 6 路由器作为家庭无线接入点，
> 下文统一简称为 **Cudy**。其他品牌路由器只要支持 DHCP 自定义配置，
> 均可按相同思路部署。

### 硬件

| 条件 | 说明 |
|------|------|
| Linux 宿主机 (x86_64/ARM64) | N100 小主机、NanoPi R4S/R2S、树莓派、退役 PC、虚拟机均可 |
| 至少 1 个以太网口 | 双网口模式需 2 个；单网口旁路和纯 DNS 模式 1 个即可 |
| 网线 ×2 | 设备 ↔ 交换机、交换机 ↔ 路由器各一条 |
| 7×24 开机 | 宿主机关机 = 过滤失效 (双网口模式还会导致全家断网) |

### 网络环境

| 条件 | 说明 |
|------|------|
| 路由器后台可登录 | 需要修改 DHCP 设置 (DNS、网关等)；家用路由器一般均可 |
| 路由器支持 AP/Bridge 模式 | 仅双网口模式需要；将路由器降级为纯 WiFi 接入点 |
| ISP 已通网 | 光猫/路由器已拨号，下游设备 DHCP 可获取 IP |

### 技术能力

| 条件 | 说明 |
|------|------|
| Linux CLI 基本操作 | ssh、apt install、systemctl、nft 等 |
| 能给硬件安装操作系统 | 在物理机或虚拟机安装 Debian 12 / Ubuntu |
| 理解基础网络概念 | IP、子网掩码、网关、DHCP、DNS、MAC 地址 |
| Docker 基本使用 | `docker compose up -d`、`docker compose ps` |

### 平板/被控设备

| 条件 | 说明 |
|------|------|
| 禁用随机 MAC | 安卓: Wi-Fi → 隐私 → "使用设备 MAC"；iOS: 关 "私有 Wi-Fi 地址"。不关则 AdGuard 无法持续识别设备 |
| 能获取设备 MAC 地址 | 安卓: 设置→关于→WLAN MAC; iOS: 通用→关于→Wi-Fi 地址 |
| 设备在家长物理控制范围内 | 网络过滤无法管控离线行为、本地应用或设备刷机 |

### 不满足时

| 缺什么 | 替代方案 |
|--------|---------|
| 没有 Linux 宿主机 | NextDNS / AdGuard DNS 云服务 (订阅制) |
| 不想手动部署 | GL.iNet 预装 OpenWRT 路由器，开机即用 |
| 孩子能反编译/刷机 | 本方案不适合 → Google Family Link / iOS 屏幕时间 |

## 项目背景

家庭路由器 (Cudy WR3600E) 自带黑白名单功能不稳定，对纯 IP 地址
访问经常拦截失效。孩子使用的安卓平板需要可靠的网络访问管控。

### DNS 过滤方案选型

在确定技术路线时，我们评估了以下自托管 DNS 过滤方案：

| 方案 | Web GUI | Docker | 客户端分组 | 时段管控 | 价格 | 结论 |
|------|:---:|:---:|:---:|:---:|------|------|
| **Pi-hole** | ✅ 功能全但 UI 偏老 | ✅ | ✅ | ❌ 无原生支持 | 免费 | UI 对非技术人员不够友好 |
| **Technitium DNS** | ✅ 现代 UI | ✅ | ✅ 极为丰富 | ✅ | 免费 | 功能最强但配置复杂度高，家长难以日常操作 |
| **Blocky** | ❌ 无 GUI (纯 YAML) | ✅ | ❌ | ❌ | 免费 | 命令行运维，不适合家长场景 |
| **NextDNS** | ✅ 优秀 | ❌ SaaS | ✅ | ✅ | ~¥200/年 | 付费 + 数据在云端 + 无法按设备做 nftables 加固 |

**最终选择 AdGuard Home** 的原因:

- **开箱即用的 Web 面板** — 现代化 Material Design 风格，查询日志、
  黑白名单、过滤器订阅全部在浏览器里完成，无技术门槛
- **原生家长控制** — "屏蔽成人内容" + "强制安全搜索" 一键开关，
  客户端分组可精细区分孩子和大人
- **灵活的时段调度** — 时间表规则可设"每天 21:00-07:00 拦截"，
  比手动断网省事
- **一键禁止/解禁** — "阻止该客户端" 复选框，手机浏览器即可操作，
  适合家长快速应对 (比进时间表编辑快得多)
- **自托管无订阅** — 完全免费，数据留在本地 N100
- 配合 nftables 多层过滤，是唯一能从
  [纯 DNS](#纯-dns-模式-零部署) 平滑升级到 [旁路网关](#单网口旁路网关方案) / [双网口串联](#双网口串联网关方案推荐) 的方案

如果需要从 AdGuard 切换到 Pi-hole 或 Technitium，改 `docker-compose.yml`
替换容器即可，nftables 规则完全不受影响。

## 需求清单

| 编号 | 需求 | 实现方式 |
|------|------|----------|
| R1 | 域名级黑/白名单，Web GUI 管理 | AdGuard Home (Port 80) |
| R2 | 拦截纯 IP 直连访问 | nftables IP 黑名单 + SNI 检查 |
| R3 | 防止通过修改 DNS 绕过 | nftables 强制劫持 UDP/TCP 53 → 本机 |
| R4 | 防止 DoH/DoT 绕过 | nftables 封锁 853 + AdGuard DNS 劫持 |
| R5 | 查看孩子设备的历史访问记录 | AdGuard Home 查询日志 |
| R6 | 按设备查看上网流量/活跃时长 | ntopng (Port 3001) |
| R7 | 按时间段限制孩子可上网时段 | AdGuard Home 客户端时间表 |
| R8 | 成人内容 + 社交媒体拦截 | AdGuard 过滤器 + nftables SNI |
| R9 | 其他家庭成员不受影响 (分组策略) | AdGuard kids/default 客户端分组 |
| R10 | 低成本硬件，国内易购，长期可靠 | N100 小主机 + Debian 12 |

## 设计原则

1. **多层纵深防御** — DNS 被绕过还有 IP 黑名单，IP 被绕过还有 SNI
   检查，单点失效不会导致全局暴露
2. **Web GUI 优先** — 使用者是家长，非技术人员，日常操作 (查看记录、
   修改白名单、设时间表) 全部通过浏览器完成
3. **Docker 解耦** — 每个功能独立容器，替换/升级无影响，和宿主机
   nftables 组合形成完整方案
4. **性价比优先** — N100 小主机 ~¥600，功耗 ~10W，性能可同时跑
   网关 + 监控 + 未来扩展 (Home Assistant、NAS 等)

## 三种模式功能对比

| 功能 | 双网口串联 | 单网口旁路 | 纯 DNS |
|------|:---:|:---:|:---:|
| DNS 域名黑/白名单 | ✅ | ✅ | ✅ |
| 纯 IP 直连拦截 | ✅ | ✅ | ❌ |
| IP 黑名单 (nftables) | ✅ | ✅ | ❌ |
| SNI 过滤 (TLS 握手域名匹配) | ✅ | ✅ | ❌ |
| DNS 强制劫持 (防改 8.8.8.8) | ✅ | ✅ | ❌ |
| DoH / DoT 端口封锁 | ✅ | ✅ | ❌ |
| MAC 白名单 (严格模式) | ✅ | ✅ | ❌ |
| AdGuard Web GUI 管理 | ✅ | ✅ | ✅ |
| 查询日志 / 上网记录 | ✅ | ✅ | ✅ |
| 客户端分组 (kids / default) | ✅ | ✅ | ✅ |
| 时间段控制 (限时上网) | ✅ | ✅ | ✅ |
| 一键禁止 / 解禁 | ✅ | ✅ | ✅ |
| ntopng 流量监控 | ✅ | ✅ | ✅ |
| 需要双网口硬件 | 是 | 否 | 否 |
| 需要物理改线 | 是 | 否 | 否 |
| 需要改路由器 DHCP | NAT 接管 | 网关 + DNS | 仅 DNS |
| 对网速影响 | 无 | 上行 hairpin ~20% | 零 |
| 部署复杂度 | 高 | 中 | 低 |

## 硬件兼容性

### 支持的设备

任何能装标准 Linux 的 x86_64 / ARM64 设备均可:

| 类别 | 举例 | 适用模式 |
|------|------|----------|
| x86 软路由/小主机 | N100, N95, J4125 | 双网口(串联) 或 单网口(旁路) |
| ARM 开发板 | NanoPi R4S/R2S, 树莓派 4/5, Orange Pi | 双网口 或 单网口(旁路) |
| 旧 PC/笔记本 | 退役台式机/笔记本 + USB 网卡 | 视网口数而定 |
| 虚拟机 | Proxmox/ESXi/VMware 上的 Linux VM | 双网口(直通/桥接) 或 单网口(旁路) |

<details>
<summary>⚠️ 不兼容: macOS / Mac Mini (点击展开)</summary>

**macOS (包括搭载 M 芯片或 Intel 的 Mac Mini) 不能用作此方案的网关设备。**

| 问题 | 详情 |
|------|------|
| Docker `network_mode: host` | macOS 上 Docker 运行在 Hypervisor 层的 Linux VM 中, 容器和宿主机不在同一网络命名空间。`network_mode: host` 不生效, AdGuard 无法直接在宿主机网口上监听 53 端口 |
| DNS 劫持无法实现 | nftables 的 `redirect to :53` 规则将 DNS 流量转向宿主机网口的 53 端口。macOS 不具备 Linux 的 nftables, macOS 自身的 `pf` 防火墙不支持 `redirect` 表达式和 SNI 匹配 |
| SNI 过滤不可用 | macOS 的 `pf` 是 BSD 防火墙, 没有 `tls sni` 匹配能力, 无法在 TLS 握手阶段按域名拦截 |
| 核心依赖全在 Linux 内核 | nftables + redirect + SNI match + netdev ingress + ipset 全部是 Linux 内核特性, macOS 一个都不支持 |

**变通方案:**

| 方法 | 评估 |
|------|------|
| Mac Mini 格掉装 Ubuntu/Debian (仅 Intel 机型) | ✅ 可行, 方案完全一致 |
| Mac Mini 上跑 Linux 虚拟机 (UTM/Parallels) | ⚠️ 仅能走单网口旁路, 需多一层 bridge 配置, 不推荐 |
| Mac Mini 只做监控面板 (AdGuard + ntopng) | ⚠️ Web GUI 可用, 但过滤和 DNS 劫持全丢失, 只剩半套方案 |
| 放弃 Mac Mini, 另购 N100 小主机 | ✅ ~¥600, 功耗 10W, 完整功能 |

**如果你手头只有 Mac Mini:** Intel 版本建议直接格掉装 Ubuntu/Debian, M 芯片版本建议拿来干别的事,
网关另用 N100 或 NanoPi R4S。

</details>

## 硬件拓扑

| 设备 | 角色 | 网口 |
|------|------|------|
| N100 小主机 | 网关 + Docker Host | 1 WAN, 1 LAN |
| Cudy WR3600E | 纯 WiFi AP | 接 N100 LAN 口 |

```
[ISP 光猫] → [N100 eth0 WAN (DHCP)]
                   ↓ nftables NAT + filter
              [N100 eth1 LAN (10.0.0.1/24)]
                   │
     ┌─────────────┴─────────────┐
     │  Docker:                  │
     │  AdGuard Home  :53 :80    │
     │  ntopng        :3001      │
     └───────────────────────────┘
                   │
            [Cudy WR3600E LAN 口, AP Mode]
                   │
              WiFi + 有线设备
```

## 项目文件结构

```
gateway/
├── docker-compose.yml
├── nftables.conf              # 双网口防火墙规则
├── nftables-single-nic.conf   # 单网口防火墙规则
├── scripts/
│   ├── 01-setup-host.sh
│   ├── 02-nftables-apply.sh
│   ├── 03-verify.sh
│   └── single-nic/
│       ├── 01-setup-host.sh
│       ├── 02-nftables-apply.sh
│       └── 03-verify.sh
├── adguard/
│   ├── work/    (bind mount, 自动创建)
│   └── conf/    (bind mount, 自动创建)
└── ntopng/
    └── data/    (bind mount, 自动创建)
```

## 双网口串联网关方案（推荐）

最完整的多层过滤方案，适合双网口设备 (N100 软路由 / R4S)。
需要物理改线，部署后不可绕过。

### Step 1: N100 装好 Debian 12

```bash
apt update && apt upgrade -y
apt install -y docker.io docker-compose-v2 nftables curl
usermod -aG docker $USER
newgrp docker
```

### Step 2: 把本项目拷到 N100

```bash
git clone https://github.com/likesoap/jiankong.git
cp -r jiankong/gateway /opt/
```

### Step 3: 配置网口

```bash
cd /opt/gateway/scripts
chmod +x *.sh
bash 01-setup-host.sh
```

脚本会：
- 自动检测所有网口并让你确认哪个是 WAN / LAN
- 配置 WAN (DHCP) + LAN (静态 10.0.0.1/24)
- 启用 IP 转发
- 自动更新 `nftables.conf` 和 `docker-compose.yml` 中的接口名

### Step 4: 加载防火墙

```bash
bash 02-nftables-apply.sh
```

### Step 5: 启动 Docker 容器

```bash
cd /opt/gateway
docker compose up -d
docker compose ps
```

### Step 6: 配置 AdGuard Home

1. 浏览器打开 `http://10.0.0.1:3000` (首次设置向导)
2. 根据向导配置:
   - 管理界面端口: **80**
   - DNS 监听: **All interfaces**
   - 上游 DNS: `223.5.5.5` `119.29.29.29`
   - 设置管理员账号密码

3. 添加过滤器列表:
   ```
   AdGuard DNS filter
   HaGeZi - Multi PRO
   OISD - Big
   blocklistproject - Adult
   blocklistproject - Gambling
   blocklistproject - TikTok
   blocklistproject - Facebook
   ```

4. 加固防 DoH 绕过: 过滤器 → DNS 封锁清单 → 添加阻止列表 →
   勾选 **AdGuard 官方 DoH/DoT 公共封锁清单**，从 DNS 根源
   阻断浏览器内置的 443 端口 DoH 逃逸（配合 nftables 双保险）。

5. 添加孩子设备:
   - 设置 → 客户端设置 → 添加客户端
   - MAC 地址: 平板 WLAN MAC
   - **⚠️ 关键: 先在平板 Wi-Fi 设置中将"隐私/MAC 地址类型"由"使用随机 MAC"改为"使用设备 MAC"，否则 AdGuard 换 MAC 后无法持续识别**
   - 标签: `kids`
   - 勾选 "屏蔽成人内容"
   - 勾选 "使用安全搜索"
   - 添加时间表 (例: 每天 21:00-07:00 拦截所有流量)

6. 配置 DHCP (可选):
   - 如果 Cudy 关了 DHCP，在这里开启 AdGuard 的 DHCP
   - 范围: `10.0.0.100 - 10.0.0.200`
   - 网关: `10.0.0.1`

### Step 7: 配置 Cudy WR3600E (AP 模式)

1. 登录 Cudy 后台
2. 网络 → LAN:
   - IP: `10.0.0.2`
   - 掩码: `255.255.255.0`
   - 网关: `10.0.0.1`
   - DNS: `10.0.0.1`
3. DHCP 服务器: **关闭**
4. 保存重启
5. **物理换线**: N100 LAN 口 → Cudy 的** LAN 口** (非 WAN 口)

---

## 验证

```bash
cd /opt/gateway
bash scripts/03-verify.sh
```

或手动:
```bash
# Layer 1: DNS 域名拦截
nslookup pornhub.com 10.0.0.1    # 应返回 0.0.0.0

# Layer 2: DNS 强制劫持
nslookup baidu.com 8.8.8.8       # 仍能解析 (被劫持到本机)

# Layer 3: IP 黑名单
ping <在黑名单里的IP>             # 应超时

# Layer 4: SNI 过滤
curl -k --resolve "tiktok.com:443:157.240.0.1" https://tiktok.com/
# 应 connection timeout/reset
```

---

## 日常运维

```bash
# 查看拦截统计
nft list ruleset | grep counter

# 查看防火墙日志 (最近 100 条拦截)
journalctl -k --since "1 hour ago" | grep -E 'SNI|IP|DOT' | tail -100

# 重载防火墙
systemctl reload nftables-gateway

# 更新 AdGuard Home
cd /opt/gateway && docker compose pull && docker compose up -d

# 更新 ntopng
docker compose pull ntopng && docker compose up -d ntopng
```

### 调整过滤规则

#### 增加 SNI 黑名单域名

编辑 `nftables.conf`，在 `BLOCKED_SNI` 中添加域名，然后:

```bash
systemctl reload nftables-gateway
```

#### 增加 IP 黑名单

编辑 `nftables.conf`，在 `BLOCKED_IPS` 中添加 IP/网段:

```nft
define BLOCKED_IPS = {
    1.2.3.4,
    5.6.7.0/24,
}
```

#### 按时间段限制 (AdGuard Home Web UI)

客户端设置 → 选择 kids 设备 → 时间表:
- 上学日: 07:00-08:00 / 18:00-21:00 (仅允许这些时段)
- 周末: 07:00-21:00

#### 扩展监控仪表盘 (可选)

无需此步骤 Web GUI (AdGuard + ntopng) 即可正常使用。
以下用于将多套监控整合为一个 Grafana 聚合仪表盘。

```bash
cd /opt/gateway
docker compose -f docker-compose.extend.yml up -d
```

**启动后**:
- Grafana: `http://10.0.0.1:3200` (匿名登录，只读 Viewer 角色)
- Prometheus 自动采集 AdGuard 的 DNS 查询指标
  (请求量 / 拦截率 / 延迟 / 客户端排行 / 上游 DNS 响应时间)
- AdGuard + ntopng 已有独立 Web 面板，Grafana 为可选的聚合视图

> **提示**: 如果不需要聚合仪表盘，`docker-compose.extend.yml` 完全可跳过。
> `docker-compose.yml` 已提供 AdGuard Home + ntopng 两个独立 Web 面板。

## Web 面板地址

| 面板 | 地址 | 用途 |
|------|------|------|
| AdGuard Home | `http://10.0.0.1` | DNS 过滤, 查询日志, 黑白名单, 客户端规则 |
| ntopng | `http://10.0.0.1:3001` | 实时流量, per-device 统计, 活跃时长估算 |
| Grafana | `http://10.0.0.1:3200` | AdGuard DNS 聚合仪表盘 (需 `-f docker-compose.extend.yml`) |

## 设备管理

### 添加新设备到监控

1. **前置: 禁用随机 MAC** — 安卓默认启用随机 MAC, 必须先关掉:
   - 安卓: Wi-Fi 设置 → 已连 Wi-Fi → 隐私 → 选择 "使用设备 MAC"
   - iOS: 设置 → 无线局域网 → 已连网络 → 关闭 "私有 Wi-Fi 地址"
   - **不关意味着 MAC 随时变化 → AdGuard 识别丢失 → 孩子逃逸到 default 组无法管控**

2. 获取设备真实 MAC 地址:
   - 安卓平板: 设置 → 关于 → WLAN MAC 地址
   - iOS: 设置 → 通用 → 关于本机 → Wi-Fi 地址
3. AdGuard Home → 客户端 → 添加客户端:
   - 标识符: `AA:BB:CC:DD:EE:FF`
   - 标签: `kids`
   - 勾选 "屏蔽成人内容" + "使用安全搜索"
   - 设置时间表 (如: 每天 21:00-07:00 拦截)
4. 如需固定 IP (方便 ntopng 对应): DNS → DHCP → 静态租约 → 添加 MAC→IP 绑定
5. 自此该设备所有 DNS 查询走 kids 策略，**改 IP 不影响规则** (识别基于 MAC)

### 移除设备

1. AdGuard Home → 客户端 → 选中设备 → 删除
2. 设备退回 default 全局规则 (仅拦截广告/恶意软件，不拦截社交/成人)
3. 若配过静态 DHCP 租约，一并删除

### 查看某个设备的上网记录

1. AdGuard Home → 查询日志 → 客户端筛选 → 选目标设备
2. 显示该设备所有 DNS 查询时间线 (域名 / 时间 / 是否被拦截)
3. ntopng → Hosts → 选目标 IP → 查看实时流量 + 历史流量趋势

### 家长一键禁止/解禁

无需进时间表编辑, 适合即时操作:

**一键禁止 (立即断网):**
1. 手机浏览器打开 AdGuard Home 后台
2. 设置 → 客户端设置 → 找到孩子设备 → 编辑
3. 勾选 **"阻止该客户端"** (Block this client) 并保存
4. 效果: 该设备所有 DNS 请求瞬间锁死, 表现为立即断网

**一键解禁 (恢复上网):**
1. 同路径, **取消勾选** "阻止该客户端" 并保存
2. 网络瞬间恢复

## 防绕过策略

本方案的核心防御点是**强制所有 DNS 查询经过 AdGuard Home**，
结合多层过滤应对各种绕过企图。

| 场景 | 是否可绕过 | 原因 |
|------|:---:|------|
| 改平板的 IP 地址 | 否 | AdGuard 用 **MAC** 而非 IP 识别客户端; MAC 不变, 策略不变 |
| 改平板的 MAC 地址 | 否 | 前置锁死设备 MAC (关闭随机 MAC 功能); 若强行重置生成新 MAC, 启用 nftables netdev MAC 白名单后未登记设备直接 DROP |
| 手动设 DNS 为 8.8.8.8 | 否 | nftables 劫持所有 53 端口流量 → AdGuard Home |
| 使用 DoH (DNS over HTTPS) | 否 | nftables 封锁 853 端口; AdGuard 内置 DoH/DoT 封锁清单阻断 443 端口隐蔽外发, 双重保险 |
| 用 IP 直连不良网站 | 否 | nftables SNI 检查: TLS 握手阶段读取 Server Name → 匹配黑名单 → DROP |
| 使用 VPN/代理 | 部分 | 需手动添加 VPN IP 到 BLOCKED_IPS; 可封锁常见 VPN 端口 (1194/1723/500/4500) |
| 改路由器配置还原 | 否 | Cudy 已降级为纯 AP, DHCP/NAT/路由功能全部由 N100 接管 |

## 单网口旁路网关方案

当硬件只有一个网口 (老旧笔记本、NAS、树莓派、单网口小主机)，
无法做串联网关时，使用此方案。

### 拓扑对比

```
双网口 (串联)                         单网口 (旁路)
┌──────────────┐                      ┌──────────────────────────┐
│ N100         │                      │ Cudy 路由器 (正常模式)    │
│ eth0→WAN     │                      │ DHCP/DNS/Gateway/NAT      │
│ eth1→LAN     │                      │ 192.168.1.254             │
│ NAT + filter │                      └────────┬─────────────────┘
└──────────────┘                               │
                                       同一 L2 广播域
                                      ┌────────┴─────────────────┐
                                      │ N100 单网口               │
                                      │ IP: 192.168.1.1           │
                                      │ filter only, 无 NAT       │
                                      │ 路由: 0/0→192.168.1.254   │
                                      └──────────────────────────┘
```

### 关键差异

| | 双网口 (串联) | 单网口 (旁路) |
|---|---|---|
| N100 角色 | 主路由 (NAT+DHCP+DNS) | 旁路网关 (纯 filter, 路由器承担 NAT/DHCP) |
| NAT | N100 做 SNAT/Masquerade | 路由器做 NAT, N100 不做 |
| 回程流量 | 必经 N100 (对称) | 绕过 N100 直接回设备 |
| Cudy 角色 | 纯 AP (DHCP 关闭) | 正常路由 (DHCP 开启) |
| 部署复杂度 | 需物理改线 | 只改路由器 DHCP 设置 |
| DNS 劫持 | ✅ | ✅ |
| SNI 拦截 | ✅ | ✅ (SYN 经过 N100) |
| IP 黑名单 | ✅ | ✅ (同上) |
| 对外网影响 | 光猫断则全网断 | N100 宕机不影响外网 (回退到路由器) |

### 非对称路由的影响

```
出站: 平板 → N100 (过滤) → 路由器 → Internet   ✅
回程: Internet → 路由器 → 平板                  ⚠️
```

回程流量直接回到平板不经过 N100，但**不影响过滤功能**:
- **DNS** — AdGuard 收到查询后直接回复，请求/响应都在同一 L2
- **SNI** — TLS 握手首个 SYN 即被 DROP，连接无法建立
- **IP 黑名单** — 出站包命中即 DROP，无回程也无妨

### 单网口性能分析

单网口旁路模式下, 上行流量在同一 NIC 进出两次 (hairpin), 带宽占用翻倍:

```
上行: 设备 → 交换机 → N100 eth0(进) → filter → N100 eth0(出) → 交换机 → 路由器 → Internet
下行: Internet → 路由器 → 交换机 → 设备          ← 不经过 N100
```

| 宽带套餐 | 上行速率 | NIC 实际负载 | 1GbE 占比 | 瓶颈？ |
|---------|---------|------------|---------|:---:|
| 100M↓ / 20M↑ | 20M | 40M | 4% | 否 |
| 300M↓ / 30M↑ | 30M | 60M | 6% | 否 |
| 500M↓ / 50M↑ | 50M | 100M | 10% | 否 |
| 1000M↓ / 100M↑ | 100M | 200M | 20% | 否 |
| 1000M↑↓ 对称 | 1000M | **2000M** | **200%** | **是** |

**结论**: 99% 的家用宽带 (上行 ≤100M) 仅占 1GbE 带宽的 <20%,
日常使用无感知折扣。唯一有影响的场景是千兆对称宽带, 此时需 2.5GbE
单网口或切回双网口串联模式。

nftables forward 规则为 O(1) 内核级处理, N100 可线速转发数 Gbps;
SNI 匹配仅检查 TCP SYN 包, 不碰后续数据流; conntrack 表高峰 5000-10000
并发连接, N100 16GB 内存完全无感。

### 部署步骤 (5 步)

#### Step 1: 装好系统 + 依赖

```bash
apt update && apt upgrade -y
apt install -y docker.io docker-compose-v2 nftables curl
usermod -aG docker $USER
```

#### Step 2: 拷入项目文件

```bash
git clone https://github.com/likesoap/jiankong.git
cp -r jiankong/gateway /opt/
cd /opt/gateway
```

#### Step 3: 配置网口 (单网口版)

```bash
cd /opt/gateway/scripts/single-nic
chmod +x *.sh
bash 01-setup-host.sh
```

脚本会:
- 检测单网口并确认
- 自动检测路由器 IP (当前默认网关)
- 设置 N100 静态 IP (路由器网段 .1 地址)
- 添加默认路由指向路由器
- 停用 DHCP client (避免 IP 冲突)
- 启用 IP 转发
- 更新 `nftables-single-nic.conf` 和 `docker-compose.yml` 中的接口名

**⚠️ 执行后 N100 的 IP 会变成静态** (默认 `192.168.1.1`), 如果已通过 DHCP 连入, 连接会断。去路由器后台确认无误后继续。

#### Step 4: 加载防火墙 + 启动容器

```bash
bash 02-nftables-apply.sh
cd /opt/gateway
docker compose up -d
```

#### Step 5: 配置路由器 DHCP (Cudy WR3600E)

**Cudy 保持路由模式** (不切 AP), 修改:

```
网络 → LAN:
  IP:        192.168.1.254
  掩码:      255.255.255.0

DHCP 服务器:
  DHCP 范围:  192.168.1.100 - 200
  默认网关:  192.168.1.1      (N100 IP)
  DNS 服务器: 192.168.1.1      (N100 + AdGuard Home)
```

**工作原理**:
1. 设备 DHCP 拿到网关 = 192.168.1.1 (N100)
2. 设备 DNS = 192.168.1.1 (N100 + AdGuard)
3. 设备访问外网 → 先经过 N100 (filter 生效) → 再经路由器出去

> ⚠️ **重要**: DNS 服务器**必须**填 `192.168.1.1` (AdGuard Home)。
> 切勿填写 `223.5.5.5` 等外网 DNS, 否则终端直接绕开 AdGuard,
> 客户端识别、分组策略、查询日志全部失效。

改动后重启路由器, 所有设备重新获取 DHCP 即生效。

#### 配置 AdGuard Home

同双网口方案 [Step 6](#step-6-配置-adguard-home), 区别:
- 管理界面地址变为 `http://192.168.1.1:3000`
- **不需要开启 AdGuard 内置 DHCP** (由路由器担任)

### 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| N100 宕机 | 所有设备的网关和 DNS 都指向 N100 → **全网断网** | 路由器 DHCP 设 **备用 DNS** 为 `223.5.5.5`; 切网关需手动去路由器改回 `0.0.0.0` (自动探测 N100 存活可写 cron 脚本) |
| N100 IP 被路由器 DHCP 分配给别人 | IP 冲突, 网关不可达 | 将 N100 的 MAC 在路由器 DHCP 中设为保留/排除, 或 N100 IP 放在 DHCP 范围外 |
| AdGuard 容器未启动 | DNS 无法解析 | 建议 `systemctl enable docker` + `restart: unless-stopped` |
| ntopng 全流量审计消耗 IO/内存 | SSD 磨损, 内存耗尽 | docker-compose.yml 已设 `mem_limit: 1g` + JSON 日志轮转 (`max-size: 10m, max-file: 3`) |

### 验证

```bash
bash scripts/single-nic/03-verify.sh
```

### 单网口模式 vs 双网口模式切换

如需从单网口升级到双网口:
1. 停止 nftables: `nft flush ruleset && systemctl stop nftables-gateway`
2. 换用 `nftables.conf` (双网口版)
3. 运行 `scripts/01-setup-host.sh` (双网口版, 配置 eth0/eth1)
4. Cudy 切 AP 模式 + 物理换线
5. `scripts/02-nftables-apply.sh` (双网口版)

反向同理: 双网口降级到单网口即可撤下物理改线。

## 纯 DNS 模式 (零部署)

当只想用 DNS 过滤、不将设备流量经过 N100 时使用此模式。
零硬件要求、零网络改动、零性能影响。

### 拓扑

```
  [平板] ←──→ [Cudy 路由器] ←──→ [Internet]
                DHCP DNS:
                N100 IP           ↑ 流量不经过 N100
                  ↓
             [N100 单网口]
             AdGuard Home (纯 DNS)
```

### 谁适合

- 孩子不会 / 还没学会改网络设置
- 不想花一分钱、不想改任何线、今天就跑起来
- **随时可升级**: 跑 `nftables-apply.sh` + 改路由器 DHCP 网关即切到[单网口旁路模式](#单网口旁路网关方案)

### 部署 (仅 2 步)

**Step 1:** N100 部署 Docker + AdGuard Home (参照[双网口方案 Step 1-6](#双网口串联网关方案推荐)，**跳过** Step 3-4 的网络和防火墙配置)

```bash
apt update && apt install -y docker.io docker-compose-v2 curl
git clone https://github.com/likesoap/jiankong.git
cp -r jiankong/gateway /opt/
cd /opt/gateway
docker compose up -d
# 浏览器打开 http://<N100-IP>:3000 配置 AdGuard Home
```

**Step 2:** 路由器 DHCP DNS 指向 N100 IP

```
Cudy 后台 → DHCP 服务器 → DNS 服务器:
  主 DNS: <N100 的 IP>
```

> ⚠️ **限制**: 孩子手动改 DNS 为 8.8.8.8、使用 Chrome 内置 DoH、
> 或用纯 IP 直连——全部绕开。上述场景出现时需升级到单网口旁路模式。

### 升级路径

```
纯 DNS ──→ 单网口旁路 (加 nftables 防火墙)
         ──→ 双网口串联 (加物理改线 + 第二个网口)
```

```bash
# 从纯 DNS 升级到单网口旁路:
cd /opt/gateway/scripts/single-nic
bash 02-nftables-apply.sh                    # 加载防火墙
# 然后改路由器 DHCP: 网关 → N100 IP，DNS → N100 IP
```

## 回滚

```bash
# 停止防火墙
nft flush ruleset
systemctl stop nftables-gateway

# 停止容器
cd /opt/gateway && docker compose down

# 恢复 Cudy 路由模式
# 登录 Cudy → 开启 DHCP → WAN 口接回光猫 → LAN IP 改回原值

# 恢复 N100 网口
# 删除 /etc/netplan/01-gateway.yaml 或恢复备份
```

## 扩展阅读

<details>
<summary>TLS 1.3 ECH (加密 SNI) 风险说明</summary>

TLS 1.3 逐步推广 ECH (Encrypted ClientHello), 会将 SNI 加密, 导致
nftables 内核级 SNI 匹配失效。这是未来潜在风险, 当前覆盖率为:
- **国内主流网站** — 绝大多数未启用 ECH, SNI 匹配有效
- **国外大站** (Google/Cloudflare) — 部分已启用, 靠第一道防线兜底:
  AdGuard DNS 已拦截域名 → 无法解析 IP → 无从直连

应对方案: 当 ECH 普及后, 可叠加 DNS-over-HTTPS 劫持 (443 端口 SNI 匹配
已知 DoH 域名) 或在 N100 上部署透明代理做 SSL 中间人检测。

</details>

<details>
<summary>核心: MAC 识别，非 IP 识别</summary>

AdGuard Home 通过 **MAC 地址**追踪设备。只要 AdGuard 的 DHCP 服务运行，
它维护的是 MAC→IP 映射表。**孩子改了 IP 地址不会逃出 kids 分组的规则**。

</details>

<details>
<summary>为什么 AP 模式下 MAC 透传有效</summary>

关键在于 Cudy 的工作模式：

```
路由模式 (NAT)                       AP 模式 (Bridge/L2)
┌─────────────────┐                  ┌─────────────────┐
│ 平板 MAC: AA    │                  │ 平板 MAC: AA    │
│       ↓         │                  │       ↓         │
│   Cudy NAT      │                  │   Cudy L2 桥    │
│  源MAC → BB     │  ← 被替换        │  源MAC → AA     │  ← 原样保留
│       ↓         │                  │       ↓         │
│  N100 看到: BB  │                  │  N100 看到: AA  │
└─────────────────┘                  └─────────────────┘
  所有 WiFi 设备                       每个设备独立 MAC
  对外显示同一个 MAC
```

路由器在 **路由/NAT 模式**下是三层设备，会对出站帧做 SNAT/Masquerade，
**源 MAC 被替换为路由器自身的 WAN 口 MAC**。此时 N100 看到的永远是 Cudy
的 MAC，无法区分不同设备。

而 **AP 模式**下 Cudy 退化为纯二层交换机：WiFi 帧转以太网帧时
**源 MAC 地址原样保留**，不做任何改写。N100 的 eth1 可以直接看到每个
WiFi 客户端的真实 MAC，MAC filter 完全有效。

部署后可在 N100 上验证:
```bash
ip neigh show dev eth1    # 应看到所有 WiFi 设备的 MAC + IP
```

</details>

<details>
<summary>可选: MAC 白名单 (严格模式)</summary>

如需拒绝未登记的陌生设备 (如孩子的第二台平板), 编辑 `nftables.conf`,
取消底部 `table netdev filter` 的注释。效果:

```
已登记 MAC → 正常上网 (走对应分组策略)
未登记 MAC → 所有流量 DROP, 连不上网
```

访客需家长手动在 nftables 中添加 MAC 才能联网。

</details>

<details>
<summary>常见 VPN 端口速查</summary>

如需封锁 VPN, 在 `nftables.conf` 的 `chain forward` 中追加:

```nft
# VPN 端口封锁
tcp dport { 1194, 1723, 500, 4500, 1701 } log prefix "VPN-blocked: " drop
udp dport { 1194, 500, 4500, 1701 } log prefix "VPN-blocked: " drop
```

然后 `systemctl reload nftables-gateway`。

</details>

<details>
<summary>技术说明: nftables vs iptables</summary>

本方案全程使用 **nftables**，不使用 iptables:

| | iptables | nftables |
|---|---|---|
| 内核状态 | 遗留框架，走兼容层 | Linux 3.13+ 原生主框架，iptables 底层也已是 nf_tables |
| SNI/TLS 过滤 | ❌ 不支持 | ✅ `tls sni` 表达式，TLS 握手阶段域名匹配 |
| 规则性能 | 逐条遍历 O(n) | 集合匹配 O(1)，规则集原子更新 |
| 语法 | 链式调用，工具分散 (iptables/ip6tables/arptables/ebtables) | 统一框架，一个 `nft` 命令管所有 |
| 发行版支持 | Debian 10+ / Ubuntu 20.04+ 已默认迁移到 nftables | ✅ |

我们涉及 DNS 劫持 (`redirect`)、IP 黑名单 (`ip daddr`)、SNI 匹配 (`tls sni`)、
MAC 白名单 (`ethernet saddr`) 四种过滤，全部由 nftables 一个框架完成，
iptables 在 IPv4/IPv6 间还需要分 `iptables` 和 `ip6tables` 两套规则。

部署时 `02-nftables-apply.sh` 会自动禁用 Debian 原生 `nftables.service`
（如果存在），避免和我们的规则冲突。

</details>
