

```markdown
# Gateway — N100 网关 + 多层过滤 (双网口 / 单网口)

> **方案选择**:
> - **双网口设备 (N100 软路由/多网口主机)**? 按下方主流程 (串联网关，推荐)
> - **单网口设备 (旧电脑/NAS/树莓派)**? 跳转到 [单网口旁路网关方案](#单网口旁路网关方案)

## 项目背景

家庭路由器 (Cudy WR3600E) 自带黑白名单功能不稳定，对纯 IP 地址访问经常拦截失效。孩子使用的安卓平板需要可靠的网络访问管控。

## 需求清单

| 编号 | 需求 | 实现方式 |
| :--- | :--- | :--- |
| **R1** | 域名级黑/白名单，Web GUI 管理 | AdGuard Home (Port 80) |
| **R2** | 拦截纯 IP 直连访问 | nftables IP 黑名单 + AdGuard 动态允许列表 + SNI 检查 |
| **R3** | 防止通过修改 DNS 绕过 | nftables 强制劫持 UDP/TCP 53 → 本机 |
| **R4** | 防止 DoH/DoT 绕过 | nftables 封锁 853 + AdGuard 内置 DoH 封锁清单 |
| **R5** | 查看孩子设备的历史访问记录 | AdGuard Home 查询日志 |
| **R6** | 按设备查看上网流量/活跃时长 | ntopng (Port 3001) |
| **R7** | 按时间段/网页一键控制孩子上网 | AdGuard Home 客户端时间表 & 原生阻止开关 |
| **R8** | 成人内容 + 社交媒体拦截 | AdGuard 过滤器 + nftables SNI |
| **R9** | 其他家庭成员不受影响 (分组策略) | AdGuard kids/default 客户端分组 |
| **R10** | 低成本硬件，国内易购，长期可靠 | N100 小主机 + Debian 12 |

## 设计原则

1. **多层纵深防御** —— DNS 被绕过还有 IP 黑名单，IP 被绕过还有 SNI 检查，应用层补充 DoH 域名拦截，单点失效不会导致全局暴露。
2. **Web GUI 优先** —— 使用者是家长，非技术人员，日常操作（查看记录、修改白名单、设时间表、一键断网放行）全部通过浏览器完成。
3. **Docker 解耦** —— 每个功能独立容器，替换/升级无影响，和宿主机 nftables 组合形成完整方案。
4. **性价比优先** —— N100 小主机 ~¥600，功耗 ~10W，性能可同时跑网关 + 监控 + 未来扩展（Home Assistant、NAS 等）。

---

## 硬件兼容性

### 支持
任何能装标准 Linux 的 x86_64/ARM64 设备均可：
- **x86 软路由/小主机**: N100, N95, J4125 等（双网口或单网口旁路）
- **ARM 开发板**: NanoPi R4S/R2S, 树莓派 4/5, Orange Pi 等（双网口或单网口旁路）
- **旧 PC/笔记本**: 退役台式机/笔记本 + USB 网卡（视网口数而定）
- **虚拟机**: Proxmox/ESXi/VMware 上的 Linux VM（双网口直通/桥接 或 单网口旁路）

### 不兼容：macOS / Mac Mini
macOS（包括搭载 M 芯片或 Intel 的 Mac Mini）**不能**用作此方案的网关设备。

| 问题 | 详情 |
| :--- | :--- |
| **Docker network mode: host** | macOS 上 Docker 运行在 Hypervisor 层的 Linux VM 中，容器和宿主机不在同一网络命名空间。`network_mode: host` 不生效，AdGuard 无法直接在宿主机网口上监听 53 端口。 |
| **DNS 劫持无法实现** | nftables 的 `redirect to :53` 规则将 DNS 流量转向宿主机网口的 53 端口。macOS 不具备 Linux 的 nftables，macOS 自身的 pf 防火墙不支持 redirect 表达式和 SNI 匹配。 |
| **SNI 过滤不可用** | macOS 的 pf 是 BSD 防火墙，没有 TLS SNI 匹配能力，无法在 TLS 握手阶段按域名拦截。 |
| **核心依赖全在 Linux 内核** | nftables + redirect + SNI match + netdev ingress + ipset 全部是 Linux 内核特性，macOS 一个都不支持。 |

#### 变通方案
- **Mac Mini 格掉装 Ubuntu/Debian**: 可行，方案完全一致（仅限 Intel 机型）。
- **Mac Mini 上跑 Linux 虚拟机 (UTM/Parallels)**: 仅能走单网口旁路，需多一层 bridge 配置，不推荐。
- **Mac Mini 只做监控面板 (AdGuard + ntopng)**: Web GUI 可用，但过滤和 DNS 劫持全丢失，只剩半套方案。
- **放弃 Mac Mini，另购 N100 小主机**: 极力推荐。~¥600，功耗 10W，完整功能。

> 📢 **提示**：如果你手头只有 Mac Mini，Intel 版本建议直接格掉装 Ubuntu/Debian；M 芯片版本建议拿来干别的事，网关另用 N100 或 NanoPi R4S。

---

## 硬件拓扑与目录结构

### 硬件架构
- **N100 小主机**：网关 + Docker Host (1 WAN, 1 LAN)
- **Cudy WR3600E**：纯 WiFi AP (接 N100 LAN)

### 拓扑图
```text
[ISP 光猫] → [N100 eth0 WAN (DHCP)]
                     ↓
             nftables NAT + filter
                     ↓
             [N100 eth1 LAN (10.0.0.1/24)]
                     │
                     ├─ Docker: AdGuard Home (:53, :80)
                     ├─ Docker: ntopng (:3001)
                     ↓
             [Cudy WR3600E LAN, AP Mode]
                     ↓
              WiFi + 有线设备

```

### 目录结构

```text
/opt/gateway/
├── docker-compose.yml
├── nftables.conf               # 双网口防火墙规则
├── nftables-single-nic.conf    # 单网口防火墙规则
├── scripts/
│   ├── 01-setup-host.sh
│   ├── 02-nftables-apply.sh
│   ├── 03-verify.sh
│   └── single-nic/
│       ├── 01-setup-host.sh
│       ├── 02-nftables-apply.sh
│       └── 03-verify.sh
├── adguard/
│   ├── work/                   # (bind mount, 自动创建)
│   └── conf/                   # (bind mount, 自动创建)
└── ntopng/
    └── data/                   # (bind mount, 自动创建)

```

---

## 快速部署 (7 步)

### Step 1: N100 装好 Debian 12

```bash
# 更新并安装依赖
apt update && apt upgrade -y
apt install -y docker.io docker-compose-v2 nftables curl

# 确保当前用户能跑 docker
usermod -aG docker $USER
newgrp docker

```

### Step 2: 把本项目拷贝到 N100

```bash
scp -r gateway/ root@n100.lan:/opt/
# 或者在 N100 上 git clone / U 盘拷贝。

```

### Step 3: 配置网口

```bash
cd /opt/gateway/scripts
chmod +x *.sh
bash 01-setup-host.sh

```

脚本会自动：

1. 检测所有网口并让你确认哪个是 WAN/LAN。
2. 配置 WAN (DHCP) + LAN (静态 `10.0.0.1/24`)。
3. 启用 IP 转发 (`ip_forward`)。
4. 自动更新 `nftables.conf` 和 `docker-compose.yml` 中的接口名。

### Step 4: 加载防火墙

```bash
bash 02-nftables-apply.sh

```

### Step 5: 启动 Docker 容器

```bash
cd /opt/gateway
docker compose up -d

# 确认容器状态
docker compose ps

```

### Step 6: 配置 AdGuard Home

1. 浏览器打开 `http://10.0.0.1:3000`（首次设置向导）。
2. 根据向导配置：
* 管理界面端口：`80`
* DNS 监听：`All interfaces`
* 上游 DNS：`223.5.5.5`, `119.29.29.29`
* 设置管理员账号密码。


3. 添加过滤器列表：
* AdGuard DNS filter
* HaGeZi Multi PRO
* OISD Big
* blocklistproject: Adult / Gambling / TikTok / Facebook


4. **加固防绕过（针对 R4 缺陷）**：进入“过滤器” -> “DNS 封锁清单” -> “添加阻止列表”，勾选 **AdGuard 官方的公共 DoH/DoT 封锁清单**。从 DNS 根源阻断浏览器内置的 443 端口 DoH 逃逸。
5. 添加孩子设备：
* 设置 → 客户端设置 → 添加客户端。
* 标识符：孩子的平板 WLAN MAC 地址（**注意：必须先在平板的 Wi-Fi 设置中将随机 MAC 改为“使用设备 MAC”**）。
* 标签：`kids`
* 勾选“屏蔽成人内容” + “使用安全搜索”。
* 添加时间表（例：每天 21:00-07:00 拦截所有流量）。


6. 配置 DHCP（可选）：如果 Cudy 关了 DHCP，在这里开启 AdGuard 的 DHCP：
* 范围：`10.0.0.100 - 10.0.0.200`
* 网关：`10.0.0.1`



### Step 7: 配置 Cudy WR3600E (AP 模式)

1. 登录 Cudy 后台。
2. 网络 → LAN：
* IP: `10.0.0.2`
* 掩码: `255.255.255.0`
* 网关: `10.0.0.1`
* DNS: `10.0.0.1`


3. **DHCP 服务器：关闭**。
4. 保存重启。
5. **物理换线**：N100 LAN 口 → **Cudy 的 LAN 口**（注意：绝对不能接 Cudy 的 WAN 口）。

---

## 验证与日常运维

### 验证脚本

```bash
bash scripts/03-verify.sh

```

或手动验证：

```bash
# Layer 1: DNS 域名拦截（应返回 0.0.0.0）
nslookup pornhub.com 10.0.0.1

# Layer 2: DNS 强制劫持（仍能解析，说明被强行劫持回本机 AdGuard）
nslookup baidu.com 8.8.8.8

# Layer 3: SNI 过滤与纯 IP 拦截（应连接超时/重置）
curl -k --resolve "tiktok.com:443:157.240.0.1" [https://tiktok.com/](https://tiktok.com/)

```

### 日常运维命令

```bash
# 查看拦截统计
nft list ruleset | grep counter

# 查看防火墙日志 (最近 100 条拦截)
journalctl -k --since "1 hour ago" | grep -E 'SNI|IP|DOT' | tail -n 100

# 重载防火墙规则
systemctl reload nftables-gateway

# 更新 AdGuard Home / ntopng
docker compose pull && docker compose up -d

```

### Web 面板地址

* **AdGuard Home**：`http://10.0.0.1`（DNS 过滤、查询日志、客户端规则、限时开关）
* **ntopng**：`http://10.0.0.1:3001`（实时流量、设备活跃时长、带宽统计）

---

## 设备管理与网页端“一键控制”

### 客户端生命周期管理

1. **获取设备真实 MAC**：
* 安卓：设置 → 关于手机 → 状态信息 → WLAN MAC 地址。
* iOS：设置 → 通用 → 关于本机 → Wi-Fi 地址。
* **前置防逃逸配置**：进入平板已连 Wi-Fi 的高级设置，将“隐私/MAC 地址类型”由“使用随机 MAC”手动修改为“使用设备 MAC”。


2. **入库绑定**：在 AdGuard Home → 客户端 → 添加客户端，绑定 MAC 并贴上 `kids` 标签。
3. **固定 IP**：在 AdGuard Home 的 DHCP 设置中添加静态租约绑定，方便 ntopng 精准对应。

### 🌐 家长网页端“一键禁止/解禁”指南（无需改动时间表）

为了让非技术人员（家长）可以随时在手机浏览器上快速对孩子“一键断网”或“恢复放行”，直接使用 AdGuard Home 网页端的原生功能：

* **一键禁止（立即断网）**：
1. 用手机打开 AdGuard Home 网页后台，进入 **“设置” -> “客户端设置”**。
2. 找到孩子的设备（`kids` 标签），点击右侧的 **“编辑”**。
3. 在弹出的窗口中，勾选 **“阻止该客户端”** (Block this client) 并保存。
4. **效果**：该设备的所有 DNS 解析请求会被瞬间锁死，表现为立即断网。


* **一键解禁（恢复上网）**：
1. 重新进入该设备编辑弹窗，**取消勾选** “阻止该客户端”并保存，网络瞬间恢复。



---

## 防绕过策略矩阵与安全性评估

| 场景 | 是否可绕过 | 防御原理与底层机制 |
| --- | --- | --- |
| **改平板的 IP 地址** | **否** | AdGuard 绑定 MAC 识别；且未登记的静态 IP 无法匹配网关路由。 |
| **改平板的 MAC 地址** | **否** | **前置锁死设备 MAC。** 若孩子强行重置网络生成新随机 MAC，配合 nftables 底部 netdev 严格白名单模式，未登记 MAC 直接 `DROP` 全盘无法连网。 |
| **手动修改 DNS 为 8.8.8.8** | **否** | nftables PREROUTING 链强行重定向：`udp dport 53 redirect to :53`。 |
| **使用 DoH / DoT 绕过** | **否** | nftables 阻断 853 端口 (DoT)；AdGuard 规则库阻断公共 DoH 域名，阻断 443 端口的隐蔽外发。 |
| **用 IP 直连不良网站** | **否** | 1. nftables 阻断黑名单 IP；<br>

<br>2. **(加固)** nftables SNI 检查。针对逐渐普及的 **TLS 1.3 ECH (加密 SNI)** 导致内核无法读取域名的风险，由第一道防线 AdGuard 开启“拦截未经 DNS 解析的 IP 直连”实现闭环。 |
| **使用 VPN / 代理** | **部分** | 需在 nftables.conf 的 forward 链追加端口拦截：`tcp/udp dport {1194, 1723, 500, 4500, 1701} log drop`。 |
| **改路由器配置还原** | **否** | Cudy 路由器已降级为纯二层 AP，不具备任何路由、NAT 或 DHCP 权限，改动无效。 |

---

## 单网口旁路网关方案

当硬件只有一个网口（老旧笔记本、NAS、树莓派、单网口小主机），无法做串联网关时，使用此方案。

### 拓扑对比

#### 双网口 (串联模式)

```text
[光猫] → [N100 eth0 (WAN)] ➔ NAT+Filter ➔ [N100 eth1 (LAN)] → [Cudy AP] → [设备]

```

#### 单网口 (旁路网关模式)

```text
                  [ISP 光猫]
                      ↓ (WAN)
             [Cudy 路由器 (正常路由模式)] 192.168.1.254
                      ↕ (LAN 广播域)
             ┌────────┴────────┬────────┐
             ▼                 ▼        ▼
       [N100 单网口]        [平板]    [其他设备]
       192.168.1.1
    (纯 filter, 无 NAT)

```

### 关键差异对比

| 特性 | 双网口 (串联) | 单网口 (旁路) |
| --- | --- | --- |
| **N100 角色** | 主路由 (NAT + DHCP + DNS) | 旁路网关 (纯 filter，路由器承担 NAT) |
| **NAT 转发** | N100 执行 `masquerade` | Cudy 路由器执行 NAT，N100 不做 NAT |
| **流量路径** | 进出双向必经 N100 (对称) | 出站经 N100 过滤，回程流量绕过 N100 直达设备 (非对称) |
| **Cudy 角色** | 纯 AP 模式 (关闭 DHCP) | 正常路由模式 (开启 DHCP，充当外网出口) |
| **DNS 劫持** | 完美支持 | **(修复)** 强力支持。出站首个 SYN 包经由 N100 时被拦截。 |
| **对外网影响** | N100 宕机则全网断网 | N100 宕机可通过脚本使路由器回退，不影响大人上网。 |

### 旁路非对称路由防绕过有效性证明

虽然回程流量直回平板不经 N100，但过滤的核心在出站阶段：

* **DNS 拦截**：AdGuard 收到请求后在同一 L2 广播域直接响应阻断，不需要经过外网回程。
* **SNI / IP 黑名单**：出站的首个 TCP SYN 报文在经过 N100 时直接被 nftables 执行 `DROP`，三次握手无法建立，连接直接死在起点。

### 部署步骤 (5 步)

#### Step 1: 装好系统与依赖

```bash
apt update && apt upgrade -y
apt install -y docker.io docker-compose-v2 nftables curl
usermod -aG docker $USER

```

#### Step 2: 拷入项目文件

```bash
scp -r gateway/ root@<n100-ip>:/opt/
cd /opt/gateway

```

#### Step 3: 配置网口 (单网口版)

```bash
cd /opt/gateway/scripts/single-nic
chmod +x *.sh
bash 01-setup-host.sh

```

脚本会自动启用 IP 转发，停用本地 DHCP client，并将 N100 的 IP 设置为静态 `192.168.1.1`，默认网关指向路由器 `192.168.1.254`。

#### Step 4: 加载防火墙与容器

```bash
bash 02-nftables-apply.sh
cd /opt/gateway
docker compose up -d

```

#### Step 5: 配置 Cudy WR3600E 路由器的 DHCP (核心逻辑修正)

Cudy 保持路由模式，修改局域网 LAN 设置：

* **LAN IP**: `192.168.1.254`
* **子网掩码**: `255.255.255.0`
* **DHCP 范围**: `192.168.1.100 - 192.168.1.200`
* **默认网关**: 修改为 `192.168.1.1` (强制将终端出站流量引向 N100 进行过滤)
* **DNS 服务器**: 修改为 `192.168.1.1` (确保终端解析走 AdGuard，**切勿填写 223.5.5.5 等外网 IP**，否则会导致 AdGuard 无法精准识别客户端分组和历史记录)。

> ⚠️ **配置区别**：单网口方案下的 AdGuard Home 首次设置向导在 `http://192.168.1.1:3000`。**不需要**开启 AdGuard 的内置 DHCP，统一由 Cudy 路由器担任 DHCP 服务。

### 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| **N100 宕机** | 局域网出站流量中断 → **全网断网** | 在 Cudy 路由器上运行定时脚本持续 Ping `192.168.1.1`，一旦不通则自动将 Cudy 自身的 DHCP 网关和 DNS 切回本地 `192.168.1.254`，实现无感旁路回退。 |
| **流量审计导致硬件过度损耗** | ntopng 全流量审计极耗 IO 与内存 | 在 `docker-compose.yml` 中对 `ntopng` 服务施加 `mem_limit: 1g` 限制；同时在宿主机 `/etc/docker/daemon.json` 中配置日志轮转（如 `"max-size": "10m"`），防止 N100 固态硬盘被日志塞满。 |

#### 一键完全回滚命令

```bash
nft flush ruleset
systemctl stop nftables-gateway
cd /opt/gateway && docker compose down
# 随后登录 Cudy 路由器，把 DHCP 网关和 DNS 恢复为 192.168.1.254 即可。

```

```

```