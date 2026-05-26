# Anywhere Phase 2: 安全架构与持久化连接实现计划

> 以 Paseo 为参考，结合 Anywhere 自身特点（自建 Python Relay、HarmonyOS 原生、Node.js Bridge Server）重新设计。

## 核心目标
将 Anywhere 从当前的"信任优先/明文中继"模型，平滑升级为**零信任、抗弱网、端到端加密**的稳定生产力工具。通过带外扫码 (OOB) 实现"一眼配对，绝对安全"。

---

## 设计原则：与 Paseo 的对比

Anywhere 与 Paseo 共享相同的核心架构模式——Phone ↔ Relay ↔ PC Bridge——但基础设施栈完全不同：

| 维度 | Paseo | Anywhere | 影响 |
|---|---|---|---|
| Relay 平台 | Cloudflare Workers + Durable Objects | 自建 Python 3 VPS (1GB RAM) | Anywhere 无法使用 DO 的自动弹性/WebSocket hibernation |
| 移动端 | React Native (跨平台) | HarmonyOS ArkTS | Anywhere 必须依赖 HarmonyOS 原生加密 API |
| 服务端 | Daemon (Node.js) | Bridge Server (TypeScript/Node.js) | 架构相似，可以直接借鉴设计 |
| 网络条件 | 始终公网 | 手机局域网 + 中继 | 离线和切换场景更频繁 |

---

## 架构强制约束 (Architectural Constraints)

### C1. 网络拓扑多路复用
`relay/relay.py` 必须支持多 Client 绑定同一 Host。采用 `dict[str, set[WebSocket]]` 的数据结构，Host 响应多播给所有关联的 Client。✅ 已实现（Paseo v2 协议核心特征，已采纳）。

### C2. 控制平面与数据平面两级分离
借鉴 Paseo 的 control socket + data socket 分离设计，在单 WebSocket 连接内部实现**逻辑上的控制/数据通道分离**：

```
Phone                                Bridge Server
  │                                       │
  │  ── 控制消息（握手/心跳/路由）──→     │  明文 JSON，E2EE 前即可交换
  │  ←─ 控制消息（心跳/事件通知）──       │
  │                                       │
  │  ── E2EE 握手 ──────────────────────→ │  经 E2EE 通道协商后切换
  │  ←─ E2EE 就绪 ─────────────────────── │
  │                                       │
  │  ── [加密 Payload] ──────────────────→│  全部密文
```

**具体实现**：在 `EncryptedChannel` 的 `send()` 里增加一个 `control()` 方法，不加密直接发送明文 JSON。接收端总是先检查 `type` 字段：如果是握手/心跳消息，直接处理绕过解密；否则走解密路径。Paseo 用独立 socket 实现，我们用 message type dispatch 实现（效果相同，不增加连接数）。

### C3. E2EE 边界定义
**E2EE 端点是 Phone ↔ Bridge (PC)**，不是 Phone ↔ Agent Process。

```
Phone ──AES-GCM──→ Relay ──AES-GCM──→ Bridge (PC) ──plaintext──→ Agent
   ↑                    ↑                    ↑
 加密帧              盲转发              解密 + 明文缓存
```

- Relay 全程接触密文。
- Bridge 是可信端点（如果 PC 被攻陷，E2EE 不提供额外保护）。
- Bridge 缓存明文用于断线恢复。

### C4. 带外信任根 (OOB Trust Root)
QR 码是唯一的信任锚点。`#offer=<base64url>` 格式（**从 Paseo 采纳**），QR 内容不直接暴露 JSON。

### C5. 前向保密 (Perfect Forward Secrecy, PFS)
**与 Paseo 不同：Paseo 明确放弃了 PFS。Anywhere 要求 PFS。** 每次连接生成 Ephemeral KeyPair，连接断开即销毁。这个决定增加了握手一次往返时间，但必要性高于 Paseo：

- Paseo 的 DO 端点由 Cloudflare 保护，私钥泄露概率极低。
- Anywhere 的 `.anywhere-host.json` 在用户的 PC 上，Windows 桌面普通用户环境下泄露风险更高。

### C6. 会话生命周期隔离
WebSocket 断线后不立即 kill 会话。引入 orphaned 状态 + 5 分钟存活窗口。

### C7. 协议版本号
`protocolVersion` 字段 + 双向版本协商。

### C8. 幂等消费
按 `messageId` 去重。

### C9. 恶意中继攻击模型
| 攻击 | 缓解 |
|---|---|
| 静默丢包 | 序列号 + 超时重传 |
| 重排序 | 消息头显式序列号 |
| 重放 | 每次连接随机 nonce，序列号单调递增检测 |
| 延迟注入 | 应用层加密心跳 |

---

## 阶段一：扫码配对与长效信任链 (OOB QR-Pairing)

### 身份与公钥生成
- PC 端（Bridge Server）：`.anywhere-host.json` ➡ `{ hostId, publicKeyHex, privateKeyHex }` ✅ 已实现
- 手机端：HUKS 优先生成 ClientKeyPair → 降级为软件密钥（`software-backed`）

### Pairing Offer 数据结构（**从 Paseo 采纳 base64url encoding**）

借鉴 Paseo 的 `ConnectionOfferV2Schema` + `encodeOfferToFragmentUrl`，将 QR 码内容改为：

```typescript
// 当前：直接 JSON 字符串（暴露敏感信息）
qrData = JSON.stringify({ relayUrl, hostId, publicKey })

// 修改为：URL fragment 编码的 base64url 压缩 offer
const offer = {
  v: 1,
  hostId: "uuid",
  publicKey: "hex",
  relayUrl: "ws://host:port"
};
const encoded = Buffer.from(JSON.stringify(offer)).toString("base64url");
const url = `anywhere://connect/#offer=${encoded}`;
QR: url
```

**优势**：
1. Fragment 永不发送到服务器（Paseo 的核心安全设计）
2. base64url 比原始 JSON 节约 ~30% QR 码空间
3. 手机扫码后解析 fragment，不会产生网络请求暴露公钥

### 扫描配对流程（**从 Paseo 采纳"试探连接"模式**）

```
1. 手机扫码 → 解析 #offer= 得到 { v, hostId, publicKey, relayUrl }
2. 暂存但不保存
3. 试探连接：通过 relayUrl + role=client&targetHostId=hostId 发起 WS
4. 等待 server_info（证明 Bridge 可达、hostId 匹配）
5. 握手成功 → upsertDaemonFromOfferUrl(offerUrl) ← Paseo 模式
6. 握手失败 → 清除暂存，提示用户重新扫码
```

### QR 码重新显示机制
- `stdin` 监听 + `ANYWHERE_SHOW_QR=1` ✅ 已记录
- 长期：WS 命令远程触发

### 无感重连
手机已存 `HostPublicKey` → 通过 Relay 找到 `targetHostId` → 发起 `E2EEHello`（复用手握流程）。

---

## 阶段二：端到端加密 (E2EE)

### 加密选型

| 组件 | Paseo（参考） | Anywhere（采用） | 原因 |
|---|---|---|---|
| 密钥交换 | Curve25519 ECDH | Curve25519 ECDH | 两者相同，不需要改 |
| 认证加密 | **XSalsa20-Poly1305** | **AES-256-GCM** | HarmonyOS `@kit.CryptoArchitectureKit` 原生支持 GCM 但不一定支持 XSalsa20；Node.js 也是 GCM 更成熟 |
| Nonce | 24 字节随机 | 12 字节随机 | GCM 标准 nonce 长度 |
| Auth Tag | — | 16 字节追加在密文末尾 | GCM 标准，已在计划中 |
| 密钥派生 | `nacl.box.before` 直接输出 | **HKDF-SHA256** | **Paseo 直接用 ECDH 输出做 AES 密钥不推荐 —— 缺少密钥拉伸，多个上下文重用相同密钥。HKDF 是更好的工程实践。** |
| 库 | `tweetnacl`（纯 JS） | Node.js `crypto` / HarmonyOS `CryptoArchitectureKit` | 原生 API 零依赖，性能更好 |
| PFS | ❌ 明确放弃 | ✅ 要求 | 见 C5 |

### 加密握手协议

```
Client                              Host (Bridge)
  │                                       │
  │  (OOB: hostId, hostPublicKey)         │
  │                                       │
  │  ──── E2EEHello ────────────────────→ │
  │  { protocolVersion: 1,               │
  │    clientId: "uuid",                 │
  │    ephemeralKey: <32B hex>,          │  ← 本次连接临时 X25519 公钥
  │    hostId: "target-host-id",         │
  │    signature: <64B hex> }            │  ← sign(hostId + ephemeralKey + clientId)
  │                                       │
  │  ←─── E2EEReady ──────────────────── │
  │  { protocolVersion: 1,               │
  │    ephemeralKey: <32B hex>,          │  ← Host 的临时 X25519 公钥
  │    accepted: true,                   │
  │    signature: <64B hex> }            │  ← sign(hostId + ephemeralKey)
  │                                       │
  │  ECDH(clientEphemeral, hostEphemeral) → sharedSecret (32B)
  │  HKDF-SHA256(sharedSecret, salt=clientEphemeral[0:16], info="anywhere-e2ee-v1") → AES-256-GCM key
```

**签名密钥**（与 Paseo 不同，Paseo 不做签名）：
- `signature` 使用**独立的 Ed25519 密钥对**（不是 ECDH 密钥——X25519 不能签名）。
- Host 的 Ed25519 公钥和 ECDH 公钥一起打包在 QR 码的 offer 中。
- Client 的 Ed25519 私钥由 HUKS 生成，公钥在 `E2EEHello` 中传输。
- Client 签名覆盖 `hostId + ephemeralKey + clientId`，防止 Relay 篡改路由。
- Host 签名覆盖 `hostId + ephemeralKey`。

为什么 Paseo 不做签名而我们要做：Paseo 在 QR 码中直接传输的是 daemon 的 ECDH 公钥，而且它们只做 key exchange 不做身份验证——信任完全建立在 QR 码的 OOB 属性上。如果 QR 被替换，只能通过视觉检查防范。Anywhere 增加签名后，即使 QR 码被篡改，手机也能在握手时检测到 Host 的身份与 QR 码内容不匹配。

### 加密消息格式

```
[12 bytes random IV]
[encrypted payload (AES-256-GCM)]
[16 bytes GCM Auth Tag]
→ base64 → WebSocket text frame
```

### Re-hello 支持（**从 Paseo 采纳**）

当 Client 重连而 Bridge Server 通过 Relay 依旧存活时，Bridge 可能收到第二个 `E2EEHello`：

```
// Paseo 的 encrypted-channel.ts: handleDaemonRehello 的精确模式
onE2EEHello(clientKey):
  if clientKey == previousClientKey → re-send E2EEReady（不重新密钥）
  if clientKey != previousClientKey → re-key, drop pending, re-send ready
```

这解决了 Paseo 在实践中遇到的竞态问题：Client 认为连接断了但其实 Bridge 的 Relay socket 还活着，Client 重连后收到旧的流式数据导致解密失败。

### 首次连接的客户端身份
- Host 不拒绝未知 `clientId`。
- 记录 `clientId → { publicKey, firstSeen }` 到内存缓存。
- 后续同一 clientId 的连接必须匹配 signature。
- **防 DoS**：同一 hostId 每秒最多 5 次握手（Bridge 侧限流）。

---

## 阶段三：断线无缝接管 (Seamless Session Recovery)

### 帧缓冲（**从 Paseo 采纳 frame buffering**）

Paseo 在 DO 中为每个 `connectionId` 缓冲最多 200 帧，解决"Client 先连接、Server Data Socket 还没就绪"的竞态条件。Anywhere 的 Relay 也需要同样的机制：

```
relay.py: pendingFrames[hostId] → list[bytes], max 200
```

当 Client 连接时，如果 `hosts[hostId]` 尚不存在（Host 还没连上来），缓冲消息。Host 连上后立即 flush。

### 间接 WebSocket 引用
```typescript
// 改造 SessionState.ws → SessionState.wsRef
interface SessionState {
  wsRef: { current: WebSocket | null };
  orphanedAt: number | null;
}
```

### cleanupWsSessions → Orphan Timeout
- WS 断开 → 标记 session orphaned → 5 分钟后清理。
- WS 重连 → 找到 `sessionId` → 接管 orphaned session → 重放缓冲区。

### Turn 级消息缓冲
与之前计划一致（滑动窗口 10 个 turn，保持 tool_call 引用完整性）。

### 游标同步
与之前计划一致（`SyncRequest` ↔ `SyncResponse`，`lastMessageId` 去重）。

---

## 阶段四：权限抢占与高危沙盒 (Permissions Sandbox)

与之前计划一致，不做变动：
- Bridge 侧危险命令正则拦截
- 分级 TTL（read=10s auto-allow → **增加敏感路径自动拒绝**、write=30s、exec=60s、global=120s）
- 重连后清理 `permission_request` 幽灵浮层

---

## 密钥管理与安全运维

### 密钥生命周期

| 密钥 | 生成方式 | 持久化 | 更换时机 |
|---|---|---|---|
| Host ECDH KeyPair | `host-identity.mts` x25519 | `.anywhere-host.json` | 删除文件后重启 |
| Host Ed25519 KeyPair | 新增，与 ECDH 一起生成 | **同 `.anywhere-host.json`** | 删除文件后重启 |
| Client KeyPair | HUKS（优先）/ 软件（降级） | HUKS 硬件 / AppStorage | 清除 App 数据 |
| Ephemeral KeyPair | 每次握手时生成 | 不持久化 | 每次新连接 |
| AES Session Key | HKDF 派生 | 不持久化 | 每次新连接 |

### 密钥泄露恢复
- **Host 私钥泄露**：删除 `.anywhere-host.json` → 重启 → 重新扫码配对。PFS 保证过去会话安全。
- **Client 私钥泄露**：清除 App 数据 → 重新扫码配对。
- **密钥轮换**：当前手动重置。长期增加 `ANYWHERE_ROTATE_KEYS=1` 开机自轮换。

---

## 实施优先级

```
优先期 1 (Phase 2a): 
  • 控制/数据通道分离改造（C2 的具体实现）
  • Pairing Offer 改为 #offer=base64url 格式
  • 手机端 HUKS ClientKeyPair 生成
  • Ed25519 签名密钥对 + host-identity.mts 改造
  • 加密握手完整实现（含 signature 校验、版本协商降级）

优先期 2 (Phase 2b):
  • Re-hello 支持（Bridge Server 侧）
  • relay.py 帧缓冲（最多 200 帧）
  • AES-256-GCM 加密/解密通道全链路验证
  • relay.py 控制通道心跳（明文 ping/pong）

优先期 3 (Phase 3a):
  • wsRef 间接引用 + orphan timeout
  • Turn 级消息缓冲
  • Cursor sync 协议

优先期 4 (Phase 3b):
  • 二维码重新显示机制（stdin / env / WS）
  • 手机端重连状态清洗

优先期 5 (Phase 4):
  • 权限沙盒 + 分级 TTL + 敏感路径拦截
  • 锁屏保活通知
```

---

## 采用 Paseo 的设计 + 未采用及原因

### ✅ 已采纳

| 设计 | 来源 | 修改程度 | 原因 |
|---|---|---|---|
| **`#offer=<base64url>` QR 编码** | `connection-offer.ts` / `pair-scan.tsx` | 修改 | fragment 永不发送到服务器；base64url 节约 30% QR 空间 |
| **试探连接验证 offer** | `pair-scan.tsx` `connectToDaemon()` | 修改 | 扫码后先试探 WS 握手再保存，防止无效 offer 污染设备列表 |
| **帧缓冲 (Frame Buffering)** | `cloudflare-adapter.ts` `bufferFrame()` | 全量 | 解决 Client 先连接而 Host 尚未就绪的竞态条件 |
| **Re-hello 支持** | `encrypted-channel.ts` `handleDaemonRehello()` | 全量 | Relay 模式下 Host socket 保持但 Client 重连时避免密钥失步 |
| **控制/数据平面分离** | `cloudflare-adapter.ts` v2 三套接字 | 适配 | 单连接内部用 type dispatch 实现相同效果，不增加连接数 |
| **控制通道心跳** | `relay-transport.ts` ping/pong + stale detection | 全量 | Python relay 已实现 Ping/Pong 处理，Bridge 侧新增 30s 超时检测 |
| **身份与密钥分离存储** | `server-id.ts` + `daemon-keypair.ts` | 已实现 | Anywhere 的 `.anywhere-host.json` 已天然支持分离 |
| **连接存活超时级联** | `relay-transport.ts` control ready (8s) + data open (15s) + stale (30s) + backoff (1-30s) | 适配 | 重建 Backoff 策略到 Bridge 侧 RelayHost，目前随机 5s 改为指数退避 |
| **Turn 级消息缓冲粒度** | relay-architecture.md "缓存引用完整性"思路 | 已有 | 已在 Phase 3 计划中，Paseo 文档验证了方向正确 |

### ❌ 未采纳

| 设计 | 不采用原因 |
|---|---|
| **Cloudflare Workers + Durable Objects** | Anywhere 运行在自建 Python VPS（1GB RAM），无法使用 CF Workers。DO 的 WebSocket hibernation、自动弹性、per-serverId 单例都是 PaaS 能力。我们的 `dict[str, set[WebSocket]]` 在单机 VPS 上足够。 |
| **tweetnacl / XSalsa20-Poly1305** | 需要跨 Node.js ↔ HarmonyOS `@kit.CryptoArchitectureKit` 互通。AES-256-GCM 是两者都原生支持的算法，引入 tweetnacl 会多一层 JS 实现绑定，无端增加跨平台兼容风险。 |
| **无 PFS（Paseo 的故意取舍）** | Paseo 承认这个取舍但选择了简单。Anywhere 目标场景中 PC 是用户个人设备，私钥泄露风险高于 Paseo 的 CF DO 安全边界。增加一次握手往返换 PFS 是值得的。 |
| **长期密钥直接做 ECDH（无签名）** | Paseo 的握手不做签名，完全依赖 QR 的 OOB 安全性。Anywhere 增加了 Ed25519 签名层——多一层防御。如果 QR 被屏幕截图泄露，签名能阻断中间人。Paseo 对此的回复是"QR 码视同密码"，但移动端 QR 码被截屏或拍照转发的可能性不可忽视。 |
| **ConnectionOfferSchema (Zod 验证)** | Paseo 使用 Zod 做编译时 + 运行时 schema 校验。Anywhere 的前端是 ArkTS（不是 TypeScript runtime），后端是 TypeScript。Zod 在前端不可用，手动 parse 更简单统一。 |
| **E2E 测试套件** | Paseo 有 `encrypted-channel.test.ts`、`dist-handshake-parity.test.ts`、`live-relay.e2e.test.ts` 等丰富测试。Anywhere 受限于 HarmonyOS 构建环境（hvigor 无标准 test runner），测试暂不纳入计划。 |
| **QR 码仅在 TTY 输出** | Paseo 默认不在非 TTY 环境打印 QR。Anywhere 的场景中用户可能通过远程桌面或 SSH 启动服务端，非 TTY 也需要显示 QR。改为始终打印。 |
| **Durable Object 自动故障恢复** | DO 自带跨区域自动故障转移。自建 Python relay 没有这个能力——一台 VPS 挂了服务就不可用。这是基础设施层面的差距，架构层面无解。 |

---

### 环境依赖
- **Bridge Server (Node.js)**：`qrcode-terminal` ✅，需要新增 Ed25519 密钥生成依赖（Node.js `crypto` 已原生支持 Ed25519，无需额外包）。
- **Relay Server**：Python 3.10+ ✅，帧缓冲仅需新增一个 `defaultdict(list)`，零新依赖。
- **HarmonyOS 客户端**：`@kit.ScanKit` ✅，`@kit.CryptoArchitectureKit`（已内置）。

---

## 与 Paseo 的架构差异对比总结

```
Paseo:                                  Anywhere:
┌──────────────────────┐                ┌──────────────────────┐
│  Phone (React Native)│                │  Phone (ArkTS)       │
│  tweetnacl           │                │  CryptoArchitectureKit│
│  Zod + base64url     │                │  manual parse        │
└──────┬───────────────┘                └──────┬───────────────┘
       │ E2EE (XSalsa20-Poly1305)              │ E2EE (AES-256-GCM)
       │ 无 PFS                                │ PFS 强制
       │ 无签名                                │ Ed25519 签名
       ▼                                      ▼
┌──────────────────────┐                ┌──────────────────────┐
│  CF Workers + DO     │                │  Python relay.py     │
│  DO per serverId     │                │  dict[hostId] set[WS]│
│  自动弹性/故障恢复    │                │  单机 VPS            │
│  WebSocket hibernation│               │  无 hibernation      │
└──────┬───────────────┘                └──────┬───────────────┘
       │ 控制通道 / 数据通道分离                │ 单 WS type dispatch
       │ 帧缓冲 200 帧                         │ 帧缓冲 200 帧
       ▼                                      ▼
┌──────────────────────┐                ┌──────────────────────┐
│  Daemon (Node.js)    │                │  Bridge (Node.js)    │
│  server-id + keypair │                │  host-identity.mts  │
│  独立身份/密钥文件    │                │  合并文件             │
│  无 PFS              │                │  PFS 强制            │
│  无签名              │                │  Ed25519 签名        │
└──────────────────────┘                └──────────────────────┘
```
