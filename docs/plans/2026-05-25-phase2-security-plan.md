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
`relay/relay.py` 必须支持多 Client 绑定同一 Host。采用 `dict[str, set[WebSocket]]` 的数据结构，Host 响应多播给所有关联的 Client。✅ 已实现。

### C2. 控制平面与数据平面分离 — 帧级区分

借鉴 Paseo 的 control socket + data socket 分离设计，在单 WebSocket 连接上使用**帧类型区分**实现逻辑分离：

```
Phone                                Bridge Server
  │                                       │
  │  ── [text frame] 控制消息 ──────→    │  明文 JSON，E2EE 前即可交换
  │  ←─ [text frame] 控制消息 ──────     │
  │                                       │
  │  ── [text frame] E2EE 握手 ───────→  │  握手仍为明文 text frame
  │  ←─ [text frame] E2EE 就绪 ────────  │
  │                                       │
  │  ── [binary frame] 加密消息 ──────→  │  E2EE 建立后全部走 binary
```

**确切约定**（不可违反，否则解密逻辑歧义）：

| 帧类型 | WS opcode | 内容 | 处理方式 |
|---|---|---|---|
| text | 0x01 | 明文 JSON (控制/握手) | 直接 JSON.parse，不解密 |
| binary | 0x02 | nonce(12B) + ciphertext + tag(16B) | 走 AES-256-GCM 解密路径 |

加密通道建立后，**所有业务 payload 走 binary frame**。控制消息（心跳、`relay_client_connected`、`server_info`）仍走 text frame。接收方根据 frame type 决定是否解密，不依赖内容解析。

**`EncryptedChannel` 新增控制方法：**

```typescript
interface EncryptedChannel {
  /** 发送控制消息（明文 text frame），不受加密状态影响 */
  control(type: string, payload: Record<string, unknown>): void;

  /** 发送加密消息（binary frame），channel 必须是 open 状态 */
  send(data: string | ArrayBuffer): Promise<void>;
}
```
```

**`control()` 的序列化约定**：
```
control("heartbeat", { ts: 1234 })
  → text frame payload: {"type": "heartbeat", "ts": 1234}
```
`type` 参数和 `payload` 字典合并为一个扁平 JSON 对象，`type` 成为顶层字段。接收端解析后据此路由。

**接收端事件**：`EncryptedChannel` 收到 text frame 时路由到 `oncontrol`，收到 binary frame 时解密后路由到 `onmessage`。暴露对称回调：

```typescript
interface EncryptedChannelEvents {
  /** 收到控制消息（text frame） */
  oncontrol?: (type: string, payload: Record<string, unknown>) => void;
  /** 收到加密消息（binary frame，已解密为明文） */
  onmessage?: (data: string | ArrayBuffer) => void;
  onopen?: () => void;
  onclose?: (code: number, reason: string) => void;
  onerror?: (error: Error) => void;
}
```

注意 `control()` 与 `oncontrol` 的配对是 send/receive 关系，不是 request/response。心跳的 request/response 由业务层自行约定（见下）。

控制消息类型（预定义）：

| type | 方向 | 用途 |
|---|---|---|
| `heartbeat` | 双向 | 应用层 keepalive。Bridge 每 10s 发 `{"type":"heartbeat","ts":…}`，手机回复相同格式。Bridge 30s 无回复→判定手机断连；手机 45s 无收到→判定 Bridge 断连。 |
| `e2ee_hello` | Client→Host | ECDH 握手第一步 |
| `e2ee_ready` | Host→Client | ECDH 握手第二步 |
| `server_info` | Host→Client | 主机信息（不走控制通道就收不到） |

注意 `server_info` **属于控制消息**走 text frame，不等 E2EE 建立就能发送。这避免了"E2EE 握手完成前客户端收不到 `server_info`"的竞态问题。

### C3. E2EE 边界定义
**E2EE 端点是 Phone ↔ Bridge (PC)**，不是 Phone ↔ Agent Process。

```
Phone ──AES-GCM──→ Relay ──AES-GCM──→ Bridge (PC) ──plaintext──→ Agent
   ↑                    ↑                    ↑
 binary frame          盲转发              解密 + 明文缓存
```

- Relay 全程接触密文 binary，无法解密。
- Bridge 是可信端点（如果 PC 被攻陷，E2EE 不提供额外保护）。
- Bridge **在内存中缓存明文**用于断线恢复。Bridge 进程重启后缓存丢失，Agent 需重建 turn。这是设计已知限制。
- 不会将明文缓存持久化到磁盘（避免引入新的泄露面）。

### C4. 带外信任根 (OOB Trust Root)
QR 码是唯一的信任锚点。`#offer=<base64url>` 格式，fragment 永不发送到服务器。

**Relay 层无访问控制**：知道 `hostId` 即可通过 Relay 向 Host 发起连接。这不是安全漏洞——E2EE 握手前 Host 不处理任何业务请求，非法客户端无法完成 ECDH 签名验证。如果攻击者只是建立裸 WS 连接但不完成握手，每秒最多 5 次握手尝试的限流可以缓解 DoS。

### C5. 前向保密 (Perfect Forward Secrecy, PFS)
**与 Paseo 不同：Paseo 明确放弃了 PFS。Anywhere 要求 PFS。**

每次连接生成 Ephemeral KeyPair，连接断开即销毁。增加一次握手往返时间，但必要性高于 Paseo：
- Paseo 的 DO 端点由 Cloudflare 保护，私钥泄露概率极低。
- Anywhere 的 `.anywhere-host.json` 在用户的 PC 上，Windows 桌面普通用户环境下泄露风险更高。

### C6. 会话生命周期隔离
WebSocket 断线后不立即 kill 会话。引入 orphaned 状态 + 5 分钟存活窗口。最多同时保留 10 个 orphan session，超出时淘汰最旧的。

### C7. 协议版本号与协商
所有握手消息必须包含 `protocolVersion` 字段。协商逻辑：

```
Client sends E2EEHello.protocolVersion = C.version
Server receives:
  if C.version < Server.minVersion → reject (E2EEReady.accepted=false, error="version_too_old")
  if C.version ≥ Server.minVersion → accept, E2EEReady.protocolVersion = min(C.version, Server.version)
  (Server.maxVersion = Server.version, Server.minVersion = 1)
```

当前版本：`protocolVersion = 1`, `minProtocolVersion = 1`。

### C8. 幂等消费
按 `messageId` 去重。**服务端保证**回放时不发送重复条目；客户端防御性跳过 `messageId ≤ lastProcessedMessageId` 的条目。

`messageId` 生成规则：`<sessionId>:<seq>`，其中 `seq` 是 session 内递增的 uint64。这保证了跨 session 不会碰撞。

### C9. 恶意中继攻击模型

| 攻击 | 缓解 | 状态 |
|---|---|---|
| 静默丢包 | 序列号 + 超时重传 | **已知限制**：当前无显式 ACK 协议，依赖 WebSocket 的 TCP 保底（WebSocket 内建 TCP ACK，静默丢包在 TCP 层面很少发生）。若需完全防御需引入应用层 ACK——推迟到 Phase 3 实现。 |
| 重排序 | binary frame + 消息头 8 字节 sequence number | ✅ 已规划 |
| 重放 | 每次连接随机 nonce + 序列号单调递增检测 | ✅ 已规划 |
| 延迟注入 | 控制通道加密心跳（`heartbeat` text frame, 30s 超时） | ✅ 已规划 |

---

## 阶段一：扫码配对与长效信任链 (OOB QR-Pairing)

### 身份与公钥生成
- PC 端（Bridge Server）：`.anywhere-host.json` 持久化以下结构：

```json
{
  "schemaVersion": 1,
  "hostId": "uuid",
  "ecdhPublicKeyHex": "x25519 public key (32 bytes hex)",
  "ecdhPrivateKeyHex": "x25519 private key (32 bytes hex)",
  "ed25519PublicKeyHex": "ed25519 public key (32 bytes hex)",
  "ed25519PrivateKeyHex": "ed25519 private key (32 bytes hex)"
}
```

- `schemaVersion` 确保未来兼容，旧代码读到高版本字段时不会误处理。
- ✅ ECDH 密钥对已实现。新增 Ed25519 密钥对。
- 手机端：HUKS 优先生成 Ed25519 ClientKeyPair → 降级为软件密钥（标记 `software-backed`）。

### Pairing Offer 数据结构

```typescript
// QR 码内容（修改前：直接 JSON 暴露敏感信息）
qrData = JSON.stringify({ relayUrl, hostId, publicKey })

// 修改为：URL fragment 编码的 base64url 压缩 offer
const offer = {
  v: 1,
  hostId: "uuid",
  ecdhPublicKeyHex: "32 bytes hex",
  ed25519PublicKeyHex: "32 bytes hex",
  relayUrl: "ws://host:port"
};
const encoded = Buffer.from(JSON.stringify(offer)).toString("base64url");
const url = `anywhere://pair/#offer=${encoded}`;
```

**优势**：
1. Fragment 永不发送到服务器（Paseo 的核心安全设计）
2. base64url 节约 ~30% QR 码空间
3. 两个公钥分开放置，无歧义

### 扫描配对流程

```
1. 手机扫码 → 提取 #offer= 后的 base64url → decode → JSON.parse
2. 校验: { v, hostId, ecdhPublicKeyHex, ed25519PublicKeyHex, relayUrl } 字段完整性
3. 暂存 offer 数据（不保存到设备列表）
4. 试探连接：relayUrl + "?role=client&targetHostId=" + hostId
   → 等待 server_info 或 10s 超时
5. [超时] → 清理暂存，提示"服务器不可达，请确认 PC 已启动 Bridge Server"
6. [收到 server_info] → 验证 hostId 匹配 → 握手成功 → 保存到设备列表
```

### QR 码重新显示机制
- `stdin` 监听 + `ANYWHERE_SHOW_QR=1` 环境变量
- 长期：WS 命令远程触发

### 无感重连
手机已存 `ecdhPublicKeyHex` + `ed25519PublicKeyHex` → 通过 Relay 找到 `targetHostId` → 发起 `E2EEHello`。

---

## 阶段二：端到端加密 (E2EE)

### 加密选型

| 组件 | Paseo（参考） | Anywhere（采用） | 原因 |
|---|---|---|---|
| 密钥交换 | Curve25519 ECDH | Curve25519 ECDH | 两者相同 |
| 认证加密 | XSalsa20-Poly1305 | AES-256-GCM | HarmonyOS `@kit.CryptoArchitectureKit` 原生支持 GCM |
| Nonce | 24 字节随机 | 12 字节随机 | GCM 标准 nonce 长度 |
| Auth Tag | — | 16 字节追加在密文末尾 | GCM 标准 |
| 密钥派生 | `nacl.box.before` 直接输出 | HKDF-SHA256 | HKDF 提供密钥拉伸 + 上下文分离 |
| 库 | `tweetnacl` | Node.js `crypto` / HarmonyOS `CryptoArchitectureKit` | 原生 API，零依赖 |
| PFS | ❌ 放弃 | ✅ 要求 | 见 C5 |

### EncryptedChannel 状态机

```
connecting → handshaking → open → closed
                  ↑             │
                  └─────────────┘  (re-hello: Client 重连而 Host 通道存活)
```

| 状态 | 行为 |
|---|---|
| `connecting` | 底层传输未就绪（WS 正在连接）。手机端 WS timeout=10s。任何 `send()` 调用 buffer 到 pending queue（上限 200 条）。超时未连接→`connecting → closed`。 |
| `handshaking` | WS 已就绪，正在等待/处理 E2EE 握手。`send()` 继续 buffer。`control()` 立即发送（明文 text）。 |
| `open` | E2EE 已建立。`send()` 加密后发 binary frame。`control()` 明文发 text frame。 |
| `closed` | 传输已关闭。`send()`/`control()` 静默丢弃。 |

状态转换：
- `connecting → closed`：WS 连接超时（手机端 WS timeout 设为 10s，超时后回到配对界面）。
- `connecting → handshaking`：WebSocket open 事件触发。Client 侧立即发 `E2EEHello`。
- `handshaking → open`：(a) Host 侧收到 `E2EEHello` → 验证 sign → 派生密钥 → 发送 `E2EEReady`。(b) Client 侧收到 `E2EEReady(accepted=true)` → 派生密钥 → flush pending queue。
- `handshaking → closed`：(a) WS close 或握手超时（15s）。(b) Client 侧收到 `E2EEReady(accepted=false, error=…)` → 记录 error 原因，关闭通道，通知 UI 层，不重试。
- `open → handshaking`：收到 re-hello（不同密钥），重新派生密钥，drop pending queue。
- `open → closed`：WS close。

### 加密握手协议

```
Client                              Host (Bridge)
  │                                       │
  │  ──── E2EEHello ────────────────────→ │  [text frame]
  │  { protocolVersion: 1,               │
  │    clientId: "uuid",                 │
  │    clientPublicKey: <32B hex>,       │  ← Ed25519 长期公钥，用于验签
  │    ephemeralKey: <32B hex>,          │  ← 本次连接临时 X25519 公钥
  │    hostId: "target-host-id",         │
  │    signature: <64B hex> }            │  ← Ed25519 sign(hostId + ephemeralKey + clientId)
  │                                       │
  │  ←─── E2EEReady ──────────────────── │  [text frame]
  │  { protocolVersion: 1,               │
  │    ephemeralKey: <32B hex>,          │  ← Host 临时 X25519 公钥
  │    accepted: true,                   │
  │    signature: <64B hex> }            │  ← Ed25519 sign(hostId + ephemeralKey + clientId)
  │  -- 或 --                            │
  │  { protocolVersion: 1,               │
  │    accepted: false,                  │
  │    error: "version_too_old" }        │
  │                                       │
  │  ECDH(clientEphemeral, hostEphemeral) → sharedSecret (32B)
  │  HKDF-SHA256(sharedSecret, salt=clientEphemeral[0:16], info="anywhere-e2ee-v1") → AES-256-GCM key
  │                                       │
  │  ── [binary frame] 加密消息 ────────→│  AES-256-GCM
  │  ←─ [binary frame] 加密消息 ──────── │
```

**签名覆盖逻辑**：Client 和 Host 都签名 `hostId + ephemeralKey + clientId`。对称设计——双方签名覆盖相同的三个字段，不存在哪一方少绑一个字段的不对称问题。

**验签约束**：
- Client 在发送 `E2EEHello` 前已知 Host 的 Ed25519 公钥（来自 QR offer）。
- Host 在收到 `E2EEHello` 后首次获得 Client 的 Ed25519 公钥（`clientPublicKey` 字段）。记录 `clientId → { ed25519PublicKey, firstSeen }` 到内存缓存。
- 后续同 `clientId` 的连接，Host 根据缓存寻找公钥验签。如果查不到（缓存因重启丢失），使用本次 `clientPublicKey` 重新记录（首次连接逻辑）。

### 加密消息格式

```
binary frame payload:
  [8 bytes sequence number (uint64, big-endian, monotonic per-connection)]
  [12 bytes random IV]
  [encrypted payload (AES-256-GCM)]
  [16 bytes GCM Auth Tag]
```

发送方在 `handshaking → open` 时将序列号重置为 0。接收方校验序列号严格单调递增，异常值断开连接。

### Re-hello 支持（从 Paseo 采纳）

```
onE2EEHello(clientEphemeralKey):
  if same key as current → re-send E2EEReady（不重新密钥）
  if different key → re-key, drop pending queue, re-send E2EEReady, state → open
```

### 首次连接的客户端身份
- Host 不拒绝未知 `clientId`。
- 记录 `clientId → { ed25519PublicKey, firstSeen }` 到内存缓存。
- 后续同 `clientId` 连接必须匹配 signature。
- **防 DoS**：同一 hostId 每秒最多 5 次握手尝试（Bridge 侧限流）。

---

## 阶段三：断线无缝接管 (Seamless Session Recovery)

### 帧缓冲（从 Paseo 采纳）

```
relay.py: pendingFrames[hostId] → list[bytes], max 200
```

当 Client 连接时，如果 `hosts[hostId]` 尚不存在（Host 还没连上来），缓冲消息。Host 连上后立即 flush。

**关于多 Client 交织**：当前 Anywhere 的 relay 中 Host 全量广播给所有 Client，因此多个 Client 的帧被缓冲到同一个 `pendingFrames[hostId]` 是可以接受的——它们本来就是全部发给 Host 的。Host 侧根据消息内容（如 `sessionId`）自行分发到对应的 ACP session。

### 间接 WebSocket 引用

```typescript
interface SessionState {
  wsRef: { current: WebSocket | null };
  orphanedAt: number | null;
}
```

### cleanupWsSessions → Orphan Timeout
- WS 断开 → 标记 session orphaned → 5 分钟后清理（最多 10 个 orphan，超出淘汰最旧）。
- WS 重连 → 找到 `sessionId` → 接管 orphaned session → 重放缓冲区。

### Turn 级消息缓冲
滑动窗口 10 个 turn，保持 tool_call 引用完整性。同上一个版本。

### 游标同步

```
Client → SyncRequest:  { protocolVersion, sessionId, lastMessageId }
Bridge → SyncResponse: { entries: BufferEntry[] }
```

数据流：
1. 客户端传入 `lastMessageId`（客户端已处理的最后一条 `messageId`）。
2. 服务端返回 `lastMessageId` **之后**的所有 `BufferEntry`（按 `seq` 顺序）。
3. 服务端保证不返回重复条目（每个条目对应唯一的 `messageId`）。
4. 客户端防御性跳过 `messageId ≤ lastMessageId` 的条目（防御重复）。
5. 客户端更新 `lastMessageId = 最新条目的 messageId`。

---

## 阶段四：权限抢占与高危沙盒 (Permissions Sandbox)

- Bridge 侧危险命令正则拦截（配置在 `config.json` 或环境变量中）
- **分级 TTL**：

| 权限类型 | TTL | 超时行为 | 敏感路径例外 |
|---|---|---|---|
| `read_file` | 10s | 允许（读文件不破坏系统） | 匹配黑名单 → 自动拒绝 |
| `write_file` | 30s | 拒绝 | — |
| `execute_command` | 60s | 拒绝 | — |
| `global_modification` | 120s | 拒绝 | — |

敏感路径黑名单：`/etc/shadow`, `/etc/sudoers`, `~/.ssh/*`, `~/.gnupg/*`, 以及 `ANYWHERE_BLOCKED_PATHS` 环境变量扩展。

- 重连后清理 `permission_request` 幽灵浮层。与 Phase 3 cursor sync 耦合，cursor sync 完成后统一清理。

---

## 密钥管理与安全运维

### 密钥生命周期

| 密钥 | 生成方式 | 持久化 | 更换时机 |
|---|---|---|---|
| Host ECDH KeyPair | `host-identity.mts` x25519 | `.anywhere-host.json` | 删除文件后重启 |
| Host Ed25519 KeyPair | `host-identity.mts` ed25519 | 同 `.anywhere-host.json` | 删除文件后重启 |
| Client KeyPair | HUKS（优先）/ 软件（降级） | HUKS / AppStorage | 清除 App 数据 |
| Ephemeral KeyPair | 每次握手时生成 | 不持久化 | 每次新连接 |
| AES Session Key | HKDF 派生 | 不持久化（内存，断开销毁） | 每次新连接 |

### 密钥泄露恢复
- **Host 私钥泄露**：删除 `.anywhere-host.json` → 重启 → 重新扫码配对。PFS 保证过去会话安全。
- **Client 私钥泄露**：清除 App 数据 → 重新扫码配对。Host 端的旧 clientId 缓存会过期。
- **密钥轮换**：手动重置即可。长期增加 `ANYWHERE_ROTATE_KEYS=1` 开机自轮换。

---

## 实施优先级 — 含退出标准

### 优先期 1 (Phase 2a)：加密握手基础

| 任务 | 退出标准 |
|---|---|
| EncryptedChannel 状态机（含 control/send 分离） | 单元测试：四态转换 + pending queue flush 逻辑通过 |
| Pairing Offer 改为 `#offer=<base64url>` | 服务端 QR 输出含两个公钥字段；手机端扫码解析并暂存 |
| `host-identity.mts` 新增 Ed25519 + schemaVersion | 文件格式升级后旧版本读兼容不报错；新版本写入包含 5 个字段 |
| 手机端 HUKS Ed25519 ClientKeyPair | HUKS 生成、导出公钥、软件降级路径均可用 |
| 加密握手完整实现 | 通过 relay 端到端：Client → E2EEHello → Host → E2EEReady，双方派生出相同 AES key |
| 版本协商降级 | 模拟 C.version < Server.minVersion → 收到 error 响应 |

### 优先期 2 (Phase 2b)：加密通道 + Relay 增强

| 任务 | 退出标准 |
|---|---|
| Re-hello 支持 | 两次相同 key 的 E2EEHello 不重新派生；不同 key 重新派生 |
| relay.py 帧缓冲（max 200） | Host 延迟连接时 Client 消息被缓冲，Host 上线后 flush 到 Host |
| AES-256-GCM 全链路 | Node.js 端加密 → relay 转发 → Node.js 端解密，3 轮随机 payload 测试 |
| relay.py 控制通道心跳 | Bridge 侧 30s 超时检测 → 记录日志并触发重连 |
| 试探连接超时 | 手机扫码后 Host 不可达 → 10s 后提示用户 |

### 优先期 3 (Phase 3a)：断线恢复

| 任务 | 退出标准 |
|---|---|
| wsRef 间接引用 + orphan timeout | WS 断开 → session orphaned；5min 内重连 → 接管；超时 → cleanup |
| Turn 级消息缓冲 | 重连后 cursor sync 完整恢复断线期间的 thinking + tool_calls + text |
| Cursor sync 协议 | 双端 messageId 一致，无重复消息 |

### 优先期 4 (Phase 3b)：UX 完善

| 任务 | 退出标准 |
|---|---|
| 二维码重新显示（stdin / env / WS） | 三种方式均可触发 QR 打印 |
| 手机端重连状态清洗 | 重连后 permission_request 浮层清除；tool_call 卡片同步 |

### 优先期 5 (Phase 4)：权限沙盒

| 任务 | 退出标准 |
|---|---|
| 危险命令拦截 | 正则黑名单命中 → 自动拒绝（不发手机审批） |
| 分级 TTL + 敏感路径 | read_file 超时自动允许；/etc/shadow 读取自动拒绝 |
| 锁屏保活通知 | 手机锁屏后通知栏保持连接提示 |

---

## 环境依赖
- **Bridge Server (Node.js)**：`qrcode-terminal` ✅，Ed25519 密钥生成（Node.js `crypto` 原生支持，无需额外包）。
- **Relay Server**：Python 3.10+ ✅，帧缓冲仅需 `defaultdict(list)`，零新依赖。
- **HarmonyOS 客户端**：`@kit.ScanKit` ✅，`@kit.CryptoArchitectureKit`（已内置）。

---

## 已知限制与未解决问题

| 问题 | 影响 | 缓解 |
|---|---|---|
| 明文缓存在内存中，Bridge 重启后丢失 | Agent 需重建 turn | 标记为已知限制；重启频率远低于断线重连 |
| relay.py 单机 VPS 无自动故障恢复 | VPS 宕机时服务不可用 | 架构层面无解；考虑多区域部署（未来） |
| 无应用层 ACK 协议 | 恶意中继丢包不可检测 | 依赖 TCP 保底；Phase 3 可增加 |
| 锁屏保活机制依赖系统行为 | 某些 HarmonyOS 版本可能杀后台 | 通知栏保活 + 标注此为最佳努力 |
