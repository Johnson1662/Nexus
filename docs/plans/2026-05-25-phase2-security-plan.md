# Anywhere Phase 2: 安全架构与持久化连接实现计划

## 核心目标
将 Anywhere 从当前的“信任优先/明文中继”模型，平滑升级为**零信任、抗弱网、端到端加密**的稳定生产力工具。彻底告别反复输入 PIN 码，并保证代码隐私在 Relay 节点绝对安全。

---

## 架构强制约束 (Architectural Constraints)
在进入各阶段实施前，必须遵守以下核心约束，以防止系统分裂或瘫痪：
1. **网络拓扑必须支持多路复用**：`relay/server.ts` 必须支持多 Client 绑定同一 Host，杜绝新连接直接踢掉旧连接的现状。
2. **控制平面与数据平面分离**：路由信息（如 `hostId`、`sessionId`、协议指令）必须明文或仅受传输层保护；但 Agent 吐出的内容必须被 E2EE 保护。
3. **能力协商 (Capability Negotiation)**：握手时必须交换 `features` 数组，新旧版本必须能优雅降级回明文模式。
4. **中继状态强感知**：Relay 必须具备主机在线状态的订阅/广播能力；若 Host 掉线，Relay 必须显式通知所有关联 Client。
5. **防重放与加密状态同步 (Crypto State Sync)**：断网重连不仅会丢失消息，还会导致 AES-GCM 的 IV (初始化向量) 计数器两端失步。重传机制必须明确包含加密状态的对齐，或采用基于 `messageId` 的确定性 IV。
6. **防中间人攻击 (MITM) 与 PAKE**：ECDH 密钥交换若无身份认证极易被 Relay 节点劫持（替换公钥）。必须利用 8 位 PIN 码作为预共享密钥 (PSK) 派生 KEK，对初始 ECDH 交换进行签名，或采用 SPAKE2 协议，确保密钥交换无法被篡改。

---

## 阶段一：持久化授权模型 (Auth Token 机制)
**目标**：消除频繁的 PIN 码确认，实现一次配对，永久无感直连。

- **重构身份体系**：
  - 客户端生成全局唯一的 `clientId`。
  - 维持服务端刚引入的持久化 `hostId`。
  - **Relay 路由拓扑升级**：Relay Server 从依赖临时 PIN 码升级为按 `targetHostId` 路由分发流量。
- **首次发现 (Discovery)**：
  - 用户在手机端输入 PC 生成的 8 位随机 `relayPin`。
  - **物理授权确认**：杜绝暴力破解，必须在 PC 控制台敲击 `Y` 确认后，才将该 `clientId` 纳入白名单并下发 `authToken`，同时完成经 PIN 码认证的 ECDH 交换。
- **无感重连 (Reconnection)**：
  - 手机端利用 **HarmonyOS HUKS (通用密钥库系统)** 安全存储 `{ hostId, clientId, authToken, 私钥 }`，而非明文写在 Preferences 中。
  - 下次连接直接通过 Relay 向 `targetHostId` 发起基于 Challenge-Response 的鉴权握手，避免 Token 在链路上被直接抓取。
- **抗 DDOS 与防爆破**：
  - 由于 Relay 只做盲路由，Host 面临被恶意 Client 疯狂尝试连接的风险。Host 必须实现连接速率限制 (Rate Limiting)，并在连续 N 次鉴权失败后，通过 Relay 封禁特定来源。

---

## 阶段二：端到端加密 (E2EE) 重建
**目标**：防止公网 Relay Server 窃听代码、终端输出和私人对话。

- **加密方案选择**：
  - 采用 **ECDH** 进行密钥交换（由 PIN 码担保防 MITM）。
  - 采用 **AES-256-GCM** 进行对称加密通信。
- **规避前期踩过的坑**：
  - 严格约束握手时的公钥格式（Raw/SPKI），统一 IV 长度为 12 Bytes，统一将 GCM 的 16 Bytes Auth Tag 追加在密文末尾。
- **中继盲发 (Blind Relay)**：
  - Relay Server 只负责根据目标 `hostId` 路由 WebSocket 二进制帧。
- **加密颗粒度控制**：
  - AES 应用于逻辑体（Payload Content），而保留 WebSocket 外壳（明文 Type）以维持协议栈兼容和重传。

---

## 阶段三：断线无缝接管 (Seamless Session Recovery)
**目标**：在移动网络与 Wi-Fi 切换、锁屏杀后台等场景下，保护 Agent 的流式输出不丢失。

- **消息重传缓冲 (Message Buffer)**：
  - 服务端为每个激活的 Session 维护最近 50 条消息及流式 Chunk 的缓存。
- **游标同步 (Cursor Sync)**：
  - 客户端在重连握手时，携带本地接收到的 `lastMessageId`。
- **断点续传与通道重定向 (Re-piping)**：
  - 服务端对比游标，将断线期间错过的状态更新重新推给客户端。
  - 服务器必须维护 `sessionId` 与当前激活的 WebSocket 连接的绑定，断线重连时必须将旧 Session 的输出重定向至新连接。

---

## 阶段四：权限抢占与高危沙盒 (Permissions Sandbox)
**目标**：建立 PC 端的防御纵深，避免 Agent 失控。

- **拦截策略配置**：
  - 在 Bridge Server 层配置危险命令正则。
- **移动端审批与死锁解除 (Deadlock Prevention)**：
  - 当 Agent 尝试调用高危指令时，发给手机审批卡片。
  - **防死锁机制**：审批请求必须带有 TTL（如 5 分钟超时）。若手机断网或用户未响应，服务端自动拒绝该权限，防止 Agent 进程永久挂起耗尽 PC 资源。

---

## 实施路径建议
**阶段一 (Auth Token + Relay拓扑升级) -> 阶段三 (断线接管) -> 阶段二 (E2EE)**。
优先解决**连接体验**和**弱网容错**，最后再补齐**防窃听加密**。