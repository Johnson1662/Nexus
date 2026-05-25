# Anywhere Phase 2: 安全架构与持久化连接实现计划

## 核心目标
将 Anywhere 从当前的“信任优先/明文中继”模型，平滑升级为**零信任、抗弱网、端到端加密**的稳定生产力工具。彻底告别反复输入 PIN 码，并保证代码隐私在 Relay 节点绝对安全。

---

## 阶段一：持久化授权模型 (Auth Token 机制)
**目标**：消除频繁的 PIN 码确认，实现一次配对，永久无感直连。

- **重构身份体系**：
  - 客户端生成全局唯一的 `clientId`。
  - 维持服务端刚引入的持久化 `hostId`。
- **首次发现 (Discovery)**：
  - 用户在手机端输入 PC 生成的 8 位随机 `relayPin`。
  - 服务端验证通过后，将此 `clientId` 注册为受信设备，并签发高熵 `authToken` 下发给手机。
- **无感重连 (Reconnection)**：
  - 手机端 `StorageService` 持久化保存 `{ hostId, clientId, authToken }`。
  - 下次连接时，跳过 PIN 流程，直接通过 Relay 携带这三元组进行握手。
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

---

## 阶段三：断线无缝接管 (Seamless Session Recovery)
**目标**：在移动网络与 Wi-Fi 切换、锁屏杀后台等场景下，保护 Agent 的流式输出不丢失。

- **消息重传缓冲 (Message Buffer)**：
  - 服务端为每个激活的 Session 维护最近 50 条消息及流式 Chunk 的缓存。
- **游标同步 (Cursor Sync)**：
  - 客户端在重连握手时，携带本地接收到的 `lastMessageId`。
- **断点续传**：
  - 服务端对比游标，将断线期间错过的 Agent 思考过程 (Thinking)、工具调用状态更新 (tool_call_update) 重新推给客户端，避免 UI 状态僵死。

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
**阶段一 (Auth Token) -> 阶段三 (断线接管) -> 阶段二 (E2EE)**。
优先解决**连接体验**和**弱网容错**，最后再补齐**防窃听加密**，防止加密引入的不稳定影响正常开发流程。