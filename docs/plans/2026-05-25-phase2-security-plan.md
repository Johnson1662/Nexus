# Anywhere Phase 2: 安全架构与持久化连接实现计划 (基于 Paseo 架构重构版)

## 核心目标
将 Anywhere 从当前的"信任优先/明文中继"模型，平滑升级为**零信任、抗弱网、端到端加密**的稳定生产力工具。借鉴业界最先进的设计，**彻底淘汰 PIN 码和手工确认**，通过带外扫码 (OOB) 实现"一眼配对，绝对安全"。

---

## 架构强制约束 (Architectural Constraints)

在进入各阶段实施前，必须遵守以下核心约束，以防止系统分裂或瘫痪：

### C1. 网络拓扑多路复用
`relay/relay.py`（Python 3 部署版）或 `relay/server.ts`（Bun 参考版）必须支持多 Client 绑定同一 Host，杜绝新连接直接踢掉旧连接。采用 `dict[str, set[WebSocket]]` 的数据结构，让 Host 的响应能够多播给旗下所有关联的 Client。

### C2. 控制平面与数据平面分离
握手和路由协议（如 `type`, `hostId`, `sessionId`）走明文，维持网络基建兼容；但 Payload（代码、思考、终端）必须全程被密文包裹。

### C3. E2EE 边界定义（重要）
**E2EE 的端点是 Phone ↔ Bridge (PC)**，不是 Phone ↔ Agent Process。架构如下：

```
Phone ──AES-GCM──→ Relay ──AES-GCM──→ Bridge (PC) ──plaintext──→ Agent
   ↑                    ↑                    ↑
 加密帧              盲转发              解密 + 明文缓存
```

- Relay 全程接触密文，无法解密。
- Bridge 是 **可信端点**：接收密文 → 解密 → 处理 → 发送给 Agent 子进程。
- Bridge **必须缓存明文** 用于断线恢复。E2EE 不延伸入 Agent 进程内部。
- 这意味着 Bridge 所在的 PC 是信任边界。如果 PC 被攻陷，E2EE 不提供额外保护。

### C4. 带外信任根 (OOB Trust Root)
废除基于网络的短数字 PIN 认证，彻底切断公网中间人 (MITM) 及暴力破解的可能。信任的建立必须依赖物理世界"面对面"的二维码扫描。

**单向信任认清**：OOB 建立的是 **Phone → Host 的单向信任**。手机通过 QR 码获得 Host 的公钥。Host 在第一次握手时获得 Phone 的公钥并缓存，后续连接可利用缓存做双向认证。首次连接 Host 无法验证 Phone 的合法性——这是已知限制，由 DoS 保护机制缓解（见 C9）。

### C5. 前向保密 (Perfect Forward Secrecy, PFS)
即便 Host 的长期私钥在未来某天泄露，也绝不能被用来解密过去的会话数据。每次 WebSocket 连接建立时，双方必须基于长期公钥进行身份认证，但**必须生成并交换临时的 Ephemeral KeyPair** 来派生本次会话的 AES 对称密钥。连接一旦断开，临时密钥即被安全销毁。

### C6. 会话生命周期隔离
WebSocket 断线后不立即 kill 会话。引入 **orphaned 状态** 和存活窗口（默认 5 分钟）。在此期间新连接可凭 `sessionId` 接管旧会话。超时后未重连才真正清理子进程和会话资源。此约束是 Phase 3 的前提，但必须在 Phase 2 落地前完成基础设施改造。

### C7. 协议必须携带版本号
所有握手消息（`E2EEHello`, `E2EEReady`, `SyncRequest` 等）必须包含 `protocolVersion` 字段。版本协商取双方支持的最大公共版本，支持优雅降级。

### C8. 消息传递模型：幂等消费
Relay 和 Bridge 不保证 exactly-once 投递。客户端必须按 `messageId` 去重（幂等消费）。重连恢复时可能收到已处理的消息，客户端必须忽略。

### C9. 恶意中继攻击模型
除窃听外，一个被攻陷的 Relay 可以执行以下攻击。架构必须对每种攻击有缓解措施：

| 攻击 | 效果 | 缓解 |
|---|---|---|
| 静默丢包 | 消息丢失 | 序列号 + 超时检测，客户端发起重传请求 |
| 重排序 | IV 失步，解密失败 | 消息头包含显式序列号，Bridge 按序处理 |
| 重放旧包 | IV 复用，GCM 密钥信息泄露 | 每个消息包含随机 nonce 或单调递增 counter，服务端检测重复 |
| 延迟注入 | 连接超时断开 | 应用层心跳（加密 ping/pong），超时独立于传输层 |

---

## 阶段一：扫码配对与长效信任链 (OOB QR-Pairing)

**目标**：消除手工输入 PIN 码与键盘敲击 `Y` 的繁琐，实现扫描即连、无感重连。

### 身份与公钥生成
- PC 端 (Bridge Server) 启动时，基于本地存储生成持久化的 `hostId`，同时生成持久化的 ECDH `HostKeyPair`（主私钥落盘 `.anywhere-host.json`）。
- 手机端启动时生成自身的 `clientId` 及长效 `ClientKeyPair`。**优先由 HUKS 硬件级保护**；设备不支持 HUKS 时降级为软件密钥（内存中，`AppStorage` 持久化，标记为 `software-backed`）。

### 首次发现 (Discovery via QR)
- PC 端在终端中打印二维码（利用 `qrcode-terminal` 库），二维码 URL 包含：`relayUrl`、`hostId` 及 `HostPublicKey`。
- 手机端扫码，**天然获取了绝对可信的主机公钥和路由地址**。
- ✅ **已实现**：服务端 `host-identity.mts` 生成密钥，QR 码包含 hostId + publicKeyHex。手机端 `OnboardingView.ets` 解析并注入连接。

### 无感重连与鉴权
- 手机端已存有可信的 `HostPublicKey`，通过 Relay 找到 `targetHostId` 后，直接发起包含自己临时公钥的握手（以长效私钥签名）。

### QR 码重新显示机制
QR 码**不仅在启动时打印一次**。支持以下方式重新获取：
- 服务端监听 `stdin`，收到空行或 `qr` 命令时重新输出 QR 码。
- 增加 `ANYWHERE_SHOW_QR=1` 环境变量，启动时强制重打 QR 码（即使已有存储的身份）。
- 长期：增加 Bridge 端 HTTP endpoint 或 WS 命令，远程触发 QR 显示（受已有认证保护）。

---

## 阶段二：端到端加密 (E2EE) 重建

**目标**：防止公网 Relay Server 窃听代码、终端输出和私人对话。

### 加密握手协议 (Handshake)

**协议版本**：`protocolVersion = 1`

**握手流程**：

```
Client                              Host
  │                                   │
  │──── E2EEHello ──────────────────→│
  │    { protocolVersion: 1,         │
  │      clientId: "uuid",           │
  │      ephemeralPublicKey: <32B>,  │
  │      clientPublicKey: <32B>,     │  ← 长期公钥，首次连接介绍自己
  │      signature: <64B>,           │  ← 用 client 长期私钥签名 ephemeralPublicKey
  │      hostId: "target-host-id" }  │
  │                                   │
  │←─── E2EEReady ──────────────────│
  │    { protocolVersion: 1,         │
  │      ephemeralPublicKey: <32B>,  │
  │      signature: <64B>,           │  ← 用 host 长期私钥签名 ephemeralPublicKey
  │      accepted: true }            │
  │                                   │
  │   ← 双方计算 ECDH 共享密钥 →      │
  │   ← HKDF 派生 AES-256-GCM 密钥 →  │
```

**密钥派生参数**（必须硬编码，跨端统一）：

```
HKDF-Extract(salt = E2EEHello.ephemeralPublicKey[0:16],
             IKM  = ECDH_shared_secret)
             → PRK

HKDF-Expand(PRK,
            info = "anywhere-e2ee-v1",
            L    = 32)
            → AES_Key (256-bit GCM key)
```

**加密消息格式**（加密后的每一个 payload）：

```
[12 bytes IV (random)]
[encrypted payload]
[16 bytes GCM Auth Tag]
```

每个消息使用**随机 IV**（nonce），而非计数器递增 IV。这避免了重连后 IV 失步问题（代价：每条消息多 12 字节开销，对 1KB 以下消息约 1% 开销，可接受）。

消息头中增加 **序列号**（monotonic uint64，以连接生命周期计）用于重排序检测：

```
[8 bytes  sequence number (plaintext)]
[12 bytes IV (random)]
[encrypted payload]
[16 bytes GCM Auth Tag]
```

Bridge 收到后校验序列号是否单调递增。如果序列号 <= 已处理的最大值，判定为重放攻击，断开连接。

### 首次连接的客户端身份问题
Host 在收到 `E2EEHello` 时，`clientId` 和 `clientPublicKey` 可能是首次见到。Host **不拒绝**未知客户端（否则无法完成首次配对），但：
- 记录 `clientId` → `clientPublicKey` 映射到内存缓存。
- 后续同一 `clientId` 的连接必须提供匹配的 `signature`。
- **防 DoS**：同一 `hostId` 每秒最多接受 5 次握手尝试（在 Bridge 侧限流）。

### 中继盲发 (Blind Relay)
Relay Server 只负责查看包头的 `targetHostId`，并将后续的二进制帧无脑桥接给对应的 PC 节点，完全不知晓内部业务。✅ 已实现。

### 跨端避坑策略 (Crypto Compatibility)
- 公钥格式：统一使用 Raw 32 字节（X25519），导出方式已在 `host-identity.mts` 中通过 JWK 的 `x`/`d` 字段验证。
- IV：固定 12 字节，每个消息随机生成。
- Auth Tag：固定 16 字节，追加在密文末尾。
- 密钥派生：HKDF-SHA256，salt 和 info 如上定义，确保 Node.js `crypto` 与 HarmonyOS `@kit.CryptoArchitectureKit` 互通。

---

## 阶段三：断线无缝接管 (Seamless Session Recovery)

**目标**：在移动网络与 Wi-Fi 切换、锁屏杀后台等场景下，保护 Agent 的流式输出不丢失。

### 前置基础设施改造

必须在 Phase 2 结束后、Phase 3 开始前，完成以下架构改造：

#### 3.1 间接 WebSocket 引用
当前 `SessionState` 和所有 ACP 回调直接持有 `ws` 闭包引用，无法替换。改为间接寻址：

```typescript
// 改造前
interface SessionState {
  ws: WebSocket;           // 常量引用，无法替换
}

// 改造后
interface SessionState {
  wsRef: { current: WebSocket | null };  // 间接引用，可以替换
}
```

所有 `onSessionUpdate`、`onPermissionRequest` 等回调改为通过 `session.wsRef.current` 发送。断线重连时，只需将新 `ws` 赋值给 `wsRef.current`，所有回调自动指向新连接。

#### 3.2 cleanupWsSessions 改为 Orphan Timeout

```typescript
// 改造后
export function onWsDisconnected(ws: WebSocket): void {
  const sessions = findSessionsForWs(ws);
  for (const sess of sessions) {
    sess.wsRef.current = null;        // 清空引用
    sess.orphanedAt = Date.now();     // 记入孤儿时间
    scheduleCleanup(sess.sessionId, 300_000); // 5分钟后清理
  }
}

export function onWsReconnected(ws: WebSocket, sessionId: string): void {
  const sess = sessions.get(sessionId);
  if (sess && sess.wsRef.current === null) {
    sess.wsRef.current = ws;          // 接管旧会话
    cancelCleanup(sessionId);
    replayBuffer(sess, ws);           // 重放缓冲
  }
}
```

### 消息重传缓冲 (Message Buffer)

**按 turn 粒度缓存**，保持引用完整性：

```typescript
interface SessionBuffer {
  turns: TurnBuffer[];        // 滑动窗口，最多 10 个 turn
}

interface TurnBuffer {
  turnId: string;
  messageId: string;          // 客户端侧的游标
  entries: BufferEntry[];     // 一个 turn 包含的所有帧
  closed: boolean;            // turn 结束后不可再添加
}

interface BufferEntry {
  messageId: string;          // 全局唯一，幂等去重用
  type: string;               // "thinking" | "tool_call" | "tool_call_update" | "text_chunk" | "plan" | "turn_ended"
  data: object;               // 完整的帧数据（密文的明文副本）
  timestamp: number;
}
```

- 每个 `turn` 包含一个 `tool_call` 及其后续的所有 `tool_call_update`。客户端重连时服务器按 `turn` 整体下发，避免 `tool_call_update` 引用不存在的 `tool_call`。
- `messageId` 用于客户端去重：客户端维护 `lastProcessedMessageId`，服务器回放时跳过 ≤ 该 ID 的条目。

### 游标同步 (Cursor Sync)

```
Client                                Bridge
  │                                     │
  │──── SyncRequest ──────────────────→│
  │    { protocolVersion: 1,           │
  │      sessionId: "acp-12345",       │
  │      lastMessageId: "msg_50" }     │
  │                                     │
  │←─── SyncResponse ─────────────────│
  │    { entries: [entry_51 .. entry_N] }  ← 加密传输
```

客户端收到后：
1. 遍历 `entries`，跳过 `messageId ≤ lastMessageId` 的条目。
2. 按顺序重放每个条目（如同正常 `agent_event` 处理路径）。
3. 更新 `lastMessageId`。
4. 与 Bridge 当前活跃的流式状态同步（如正在输出的 terminal、正在 thinking 的文本）。

### 重连恢复后的状态清洗
客户端重连并完成 cursor sync 后，必须：
- 清理所有残留 `permission_request` 浮层。
- 清理所有 stale `tool_call` 卡片（不在重放数据中的）。
- 如果当前有 turn 活跃，恢复 `turnActive = true` 和流式状态。

---

## 阶段四：权限抢占与高危沙盒 (Permissions Sandbox)

**目标**：建立 PC 端的防御纵深，避免 Agent 越权操作。

### 拦截策略配置
在 Bridge Server 层配置危险命令正则拦截（如全局系统修改、敏感目录操作）。

### 移动端审批与防死锁 (Deadlock Prevention)
- 当 Agent 尝试调用高危指令时，发给手机审批卡片（卡片内容同受 E2EE 保护）。
- **分级 TTL 策略**：
  - `read_file` → TTL = 10 秒。超时自动允许（读文件不破坏系统）。
  - `write_file` → TTL = 30 秒。超时自动拒绝。
  - `execute_command` → TTL = 60 秒。超时自动拒绝。
  - `global_modification` → TTL = 120 秒。超时自动拒绝。
- TTL 过期后 `permission_response` 返回 `outcome: "timeout"`，Agent 应捕获错误并选择合适的回退路径（而非重试）。
- **锁屏保活**：手机端在 `aboutToDisappear`（应用退后台）时弹起通知栏提醒，保持后台任务窗口以延续 WebSocket 连接。如果手机断网导致超时，Agent 获得 `"timeout"` 后可主动提示用户检查手机连接。

### UI 幽灵状态清理
断网会导致客户端残留未响应的 `permission_request` 悬浮卡片。当发生重连时，客户端必须依据服务端的真实会话状态强制清洗 UI 栈，防止产生无法消除的"幽灵弹窗"。✅ 依赖路径与 Phase 3 cursor sync 耦合，cursor sync 完成后统一清理。

---

## 密钥管理与安全运维

### 密钥生命周期

| 密钥 | 生成方式 | 持久化 | 更换时机 |
|---|---|---|---|
| Host 长期 KeyPair | `host-identity.mts` Node.js x25519 | `.anywhere-host.json` | 手动删除文件后重启 |
| Client 长期 KeyPair | HUKS（优先）/ 软件（降级） | HUKS 硬件 / AppStorage | 清除 App 数据或手动重置 |
| Ephemeral KeyPair | 每次握手时生成 | 不持久化（内存中，握手后销毁） | 每次新连接 |
| AES Session Key | HKDF 派生 | 不持久化（内存中，连接断开销毁） | 每次新连接 |

### 密钥泄露恢复
- **Host 私钥泄露**：删除 `.anywhere-host.json`，重启生成新的 hostId 和密钥。所有已配对手机需重新扫码。旧加密的会话数据不可恢复（符合 PFS 承诺）。
- **Client 私钥泄露**：清除 App 数据，重新生成 clientId 和密钥。Host 端的旧缓存条目会过期。
- **密钥轮换**：当前无自动轮换机制，手动重置即可。长期可增加 `ANYWHERE_ROTATE_KEYS=1` 环境变量实现开机自轮换。

---

## 实施优先级

当前阶段一（扫码配对基础设施）已全部落地：
- ✅ PC 端 QR 码生成（`qrcode-terminal`）
- ✅ 手机端扫码解析（`@kit.ScanKit`）
- ✅ Relay 多路复用（`relay/relay.py`）
- ✅ `relay_client_connected` 通知
- ✅ Host 身份持久化（`host-identity.mts`）
- ⏳ 手机端 ClientKeyPair 尚未实现（标记 `TODO(phase2)`）
- ⏳ QR 码重新显示机制尚未实现

接下来的实施顺序：

1. **Phase 2a**：ClientKeyPair 生成（手机端 HUKS/软件降级）+ 加密握手协议实现
2. **Phase 2b**：消息加密/解密通道（Phone ↔ Bridge AES-GCM）+ QR 重新显示
3. **Phase 3a**：间接 WebSocket 引用 + cleanupWsSessions → orphan timeout 改造
4. **Phase 3b**：Turn 级消息缓冲 + cursor sync 协议
5. **Phase 4**：权限沙盒 + 分级 TTL + UI 状态清洗

### 环境依赖
- **Bridge Server (Node.js)**：已在 `package.json` 中引入 `qrcode-terminal`。
- **Relay Server**：需要 **Python 3.10+**（默认满足）。
- **HarmonyOS 客户端**：已在 `module.json5` 中申请 `ohos.permission.CAMERA` 并集成 `@kit.ScanKit`。