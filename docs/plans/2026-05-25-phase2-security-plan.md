# Anywhere Phase 2: 安全架构与持久化连接实现计划 (基于 Paseo 架构重构版)

## 核心目标
将 Anywhere 从当前的“信任优先/明文中继”模型，平滑升级为**零信任、抗弱网、端到端加密**的稳定生产力工具。借鉴业界最先进的设计，**彻底淘汰 PIN 码和手工确认**，通过带外扫码 (OOB) 实现“一眼配对，绝对安全”。

---

## 架构强制约束 (Architectural Constraints)
在进入各阶段实施前，必须遵守以下核心约束，以防止系统分裂或瘫痪：
1. **网络拓扑必须支持多路复用**：`relay/server.ts` 必须支持多 Client 绑定同一 Host，杜绝新连接直接踢掉旧连接。采用 `Map<string, Set<WebSocket>>` 的数据结构，让 Host 的响应能够多播给旗下所有关联的 Client。
2. **控制平面与数据平面分离**：握手和路由协议（如 `type`, `hostId`, `sessionId`）走明文，维持网络基建兼容；但 Payload（代码、思考、终端）必须全程被 AES-GCM 密文包裹。
3. **防重放与加密状态同步 (Crypto State Sync)**：断网重连不仅会丢失消息，还会导致 AES-GCM 的 IV (初始化向量) 计数器失步。协议中必须让每一个 Chunk 带上其生成用的随机 IV（或显式同步计数器），确保断点续传时密文能被无缝解开。
4. **带外信任根 (OOB Trust Root)**：废除基于网络的短数字 PIN 认证，彻底切断公网中间人 (MITM) 及暴力破解的可能。信任的建立必须依赖物理世界“面对面”的二维码扫描。
5. **前向保密 (Perfect Forward Secrecy, PFS)**：即便 Host 的长期私钥在未来某天泄露，也绝不能被用来解密过去的会话数据。每次 WebSocket 连接建立时，双方必须基于长期公钥进行身份认证，但**必须生成并交换临时的 Ephemeral KeyPair** 来派生本次会话的 AES 对称密钥。连接一旦断开，临时密钥即被安全销毁。

---

## 阶段一：扫码配对与长效信任链 (OOB QR-Pairing)
**目标**：消除手工输入 PIN 码与键盘敲击 `Y` 的繁琐，实现扫描即连、无感重连。

- **身份与公钥生成**：
  - PC 端 (Bridge Server) 启动时，基于本地存储生成持久化的 `hostId`，同时生成持久化的 ECDH `HostKeyPair`（主私钥落盘）。
  - 手机端启动时生成自身的 `clientId` 及长效 `ClientKeyPair`（由 HUKS 硬件级保护）。
- **首次发现 (Discovery via QR)**：
  - PC 端在终端中打印二维码（利用 `qrcode-terminal` 库），二维码 URL 包含：`relayUrl`、`hostId` 及 `HostPublicKey`。
  - 手机端扫码，**天然获取了绝对可信的主机公钥和路由地址**。
- **无感重连与鉴权 (Reconnection)**：
  - 因为手机端已经存有可信的 `HostPublicKey`，手机通过 Relay 找到 `targetHostId` 后，直接发起包含自己临时公钥的握手（以长效私钥签名）。由于中间人无法篡改二维码里的公钥，这种鉴权是数学意义上绝对安全的。

---

## 阶段二：端到端加密 (E2EE) 重建
**目标**：防止公网 Relay Server 窃听代码、终端输出和私人对话。

- **加密握手协议 (Handshake)**：
  - 客户端发起 `E2EEHello` 包，附带自己生成的临时 `EphemeralClientPublicKey`。
  - 主机收到后，生成临时 `EphemeralHostPublicKey`，结合算出共享密钥，回复 `E2EEReady`。
  - 双方使用 **HKDF** 派生出本次连接的 AES-256-GCM 密钥。
- **中继盲发 (Blind Relay)**：
  - Relay Server 只负责查看包头的 `targetHostId`，并将后续的二进制帧无脑桥接给对应的 PC 节点，完全不知晓内部业务。
- **避坑策略 (Crypto Compatibility)**：
  - Node.js `crypto` 与 HarmonyOS `@kit.CryptoArchitectureKit` 的互通必须严格统一格式：统一采用 Raw 格式导出公钥；统一 IV 长度为 12 Bytes；GCM 的 16 Bytes Auth Tag 统一追加在密文末尾，跨端解密时按字节切割。

---

## 阶段三：断线无缝接管 (Seamless Session Recovery)
**目标**：在移动网络与 Wi-Fi 切换、锁屏杀后台等场景下，保护 Agent 的流式输出不丢失。

- **消息重传缓冲 (Message Buffer)**：
  - 服务端为每个激活的 Session 维护最近 50 条消息及流式 Chunk 的缓存。
- **游标同步 (Cursor Sync)**：
  - 客户端在重连且 E2EE 握手成功后，携带本地接收到的 `lastMessageId` 发起同步。
- **断点续传与通道重定向 (Re-piping)**：
  - 服务端对比游标，将断线期间错过的状态更新重新推给客户端。
  - 服务器必须维护 `sessionId` 与当前激活的 WebSocket 连接的绑定，断线重连时将旧 Session 的子进程输出管道 (stdout) 重定向至新连接。

---

## 阶段四：权限抢占与高危沙盒 (Permissions Sandbox)
**目标**：建立 PC 端的防御纵深，避免 Agent 越权操作。

- **拦截策略配置**：
  - 在 Bridge Server 层配置危险命令正则拦截（如全局系统修改、敏感目录操作）。
- **移动端审批与防死锁 (Deadlock Prevention)**：
  - 当 Agent 尝试调用高危指令时，发给手机审批卡片（卡片内容同受 E2EE 保护）。
  - **防死锁机制**：审批请求必须带有 TTL（如 5 分钟超时）。若手机断网或用户未响应，服务端自动拒绝该权限，防止 Agent 进程永久挂起导致 PC 资源耗尽。
- **UI 幽灵状态清理**：
  - 断网会导致客户端残留未响应的 `permission_request` 悬浮卡片。当发生重连时，客户端必须依据服务端的真实会话状态强制清洗 UI 栈，防止产生无法消除的“幽灵弹窗”。

---

## 实施路径建议
我们当前处于刚刚稳定 UI 渲染和历史数据恢复的节点。接下来的实施优先级必须是：
**阶段一 (扫码生成/识别 + Relay多路复用拓扑) -> 阶段二 (打通 ECDH + AES 通道) -> 阶段三 (断线接管)**。
扫码和加密（阶段一与阶段二）在这一架构下是不可分割的，必须同时上线，一举淘汰明文与弱网验证机制。

### 前置依赖准备工作
在开始实施扫码配对前，必须完成以下环境的配置补齐：
1. **Bridge Server (Node.js)**：需要在 `package.json` 中引入 `qrcode-terminal` 以在终端中输出 ASCII 二维码。
2. **HarmonyOS 客户端**：需要在 `module.json5` 中申请摄像头权限 `ohos.permission.CAMERA`，并集成 `@kit.ScanKit` 实现原生的扫码解析能力。