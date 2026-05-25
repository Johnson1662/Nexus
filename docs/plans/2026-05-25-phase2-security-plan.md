# Anywhere Phase 2: 安全架构与持久化连接实现计划

## 核心目标
将 Anywhere 从当前的“信任优先/明文中继”模型，平滑升级为**零信任、抗弱网、端到端加密**的稳定生产力工具。彻底告别反复输入 PIN 码，并保证代码隐私在 Relay 节点绝对安全。

---

## 架构强制约束 (Architectural Constraints)
在进入各阶段实施前，必须遵守以下核心约束，以防止系统分裂或瘫痪：
1. **网络拓扑必须支持多路复用**：`relay/server.ts` 必须支持多 Client 绑定同一 Host，杜绝新连接直接踢掉旧连接的现状。
2. **控制平面与数据平面分离**：路由信息（如 `hostId`、`sessionId`、协议指令）必须明文或仅受传输层保护；但 Agent 吐出的内容（代码、思考、工具详情）必须被 E2EE 保护，以优化高频 Chunk 加密开销。
3. **能力协商 (Capability Negotiation)**：握手时必须交换 `features` 数组，新旧版本必须能优雅降级回明文模式，避免因底层 Crypto 库差异导致无法回滚。
4. **中继状态强感知**：Relay 必须具备主机在线状态的订阅/广播能力；若 Host 掉线，Relay 必须显式通知所有关联 Client，防止 UI 进入黑洞。

---

## 阶段一：持久化授权模型 (Auth Token 机制)
**目标**：消除频繁的 PIN 码确认，实现一次配对，永久无感直连。

- **重构身份体系**：
  - 客户端生成全局唯一的 `clientId`。
  - 维持服务端刚引入的持久化 `hostId`。
  - **Relay 路由拓扑升级**：Relay Server 必须从依赖临时 PIN 码 1 对 1 绑定，升级为按 `targetHostId` 路由分发流量。
- **首次发现 (Discovery)**：
  - 用户在手机端输入 PC 生成的 8 位随机 `relayPin`。
  - **物理授权确认**：杜绝暴力破解，必须在 PC 控制台敲击 `Y` 确认后，才将该 `clientId` 纳入白名单并下发 `authToken`，同时协商 ECDH 初始密钥。
- **无感重连 (Reconnection)**：
  - 手机端 `StorageService` 持久化保存 `{ hostId, clientId, authToken }`。
  - 下次连接时，跳过 PIN 流程，直接通过 Relay 向 `targetHostId` 发起鉴权握手。
- **设备管理**：PC 端提供基础的命令或界面来主动吊销特定的 `clientId`。

---

## 阶段二：端到端加密 (E2EE) 重建
**目标**：防止公网 Relay Server 窃听代码、终端输出和私人对话。

- **加密方案选择**：
  - 采用 **ECDH (Elliptic Curve Diffie-Hellman)** 进行密钥交换。
  - 采用 **AES-256-GCM** 进行对称加密通信。
- **规避前期踩过的坑**：
  - 之前导致链路中断的原因在于 ArkTS `@kit.CryptoArchitectureKit` 与 Node.js `crypto` 的底层对齐问题。
  - **修复策略**：严格约束握手时的公钥格式（Raw/SPKI），统一 IV (Initialization Vector) 长度为 12 Bytes，统一将 GCM 的 16 Bytes Auth Tag 追加在密文末尾，并在两侧严格按此切分。
- **中继盲发 (Blind Relay)**：
  - Relay Server 只负责根据目标 `hostId` 路由 WebSocket 二进制帧，对 Payload 完全无法解密。
- **加密颗粒度控制**：
  - 高频细小的 Stream Chunk 严禁逐帧附带巨大 GCM Tag，建议将 AES 应用于逻辑体（Payload Content），而保留 WebSocket 外壳（明文 Type）以维持协议栈兼容和重传。

---

## 阶段三：断线无缝接管 (Seamless Session Recovery)
**目标**：在移动网络与 Wi-Fi 切换、锁屏杀后台等场景下，保护 Agent 的流式输出不丢失。

- **消息重传缓冲 (Message Buffer)**：
  - 服务端为每个激活的 Session 维护最近 50 条消息及流式 Chunk 的缓存。
- **游标同步 (Cursor Sync)**：
  - 客户端在重连握手时，携带本地接收到的 `lastMessageId`。
- **断点续传与通道重定向 (Re-piping)**：
  - 服务端对比游标，将断线期间错过的 Agent 思考过程 (Thinking)、工具调用状态更新 (tool_call_update) 重新推给客户端。
  - 服务器必须维护 `sessionId` 与当前激活的 WebSocket 连接的绑定，断线重连时必须将旧 Session 的事件输出重定向至新连接的 Socket，避免 UI 状态僵死。

---

## 阶段四：权限抢占与高危沙盒 (Permissions Sandbox)
**目标**：利用已经打通的 `permission_request` 通道，建立 PC 端的防御纵深。

- **拦截策略配置**：
  - 在 Bridge Server 层配置危险命令正则（如 `rm -rf`，全局文件覆写）。
- **移动端审批**：
  - 当 Agent 尝试调用高危指令时，拦截调用并通过 WebSocket 将 `permission_request` 发给手机。
  - 手机弹出审批卡片（允许/拒绝/修改参数），审批结果 (`permission_response`) 返回后继续执行。

---

## 实施路径建议
我们当前处于刚刚稳定 UI 渲染和历史数据恢复的节点。接下来的实施优先级必须是：
**阶段一 (Auth Token + Relay拓扑升级) -> 阶段三 (断线接管) -> 阶段二 (E2EE)**。
优先解决**连接体验**和**弱网容错**，最后再补齐**防窃听加密**，防止加密引入的不稳定影响正常开发流程。