<!--
  ADR - 架构决策记录
  记录"为什么这样做"：技术选型、方案对比、决策理由
  每个决策包含：说明 → 当前项目选择 → 实施详情 → 备注
  实施细节通过 GitHub Issue 跟踪，ADR 仅记录决策
-->

# ADR

# 文档规范

- 每个二级标题（`##`）下必须包含固定的三级标题结构：`### 说明`、`### 当前项目选择`、`### 实施详情`、`### 备注`。
- 实施细节通过 GitHub Issue 跟踪，ADR 仅记录决策本身。
- 实施详情格式：`→ Issue「Issue 名称」`

---

## 数据持久化方案

### 说明

选择项目的数据持久化方案。Happy 服务端为数据源，本地需要缓存以实现离线可用和快速启动。

### 当前项目选择

SwiftData 本地缓存 + Happy 服务端远程同步。

理由：
- 会话和消息数据量大，需要支持查询和排序
- SwiftUI @Query 原生集成，UI 响应自动
- 服务端通过 Socket.IO 推送增量更新，本地 SwiftData 作为 cache layer
- 加密数据解密后存入本地，避免重复解密开销

### 实施详情

→ Issue「[ADR] 数据持久化方案」

### 备注

加密内容在首次接收时解密并存入 SwiftData。本地缓存为明文（设备级安全由 iOS Data Protection 保障）。

---

## 网络通信方案

### 说明

与 Happy 服务端的通信需要同时支持 HTTP REST 和 WebSocket（Socket.IO）。

可选方案：

| 方案 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| URLSession + Socket.IO Swift | REST + 实时 | 原生 HTTP，Socket.IO 生态兼容 | 依赖第三方 Socket.IO 库 |
| URLSession + 原生 WebSocket | REST + 实时 | 零第三方依赖 | 需自行实现 Socket.IO 协议（Engine.IO 层、命名空间、ACK） |
| Starscream + 自定义封装 | WebSocket | 成熟 WebSocket 库 | 仍需自行实现 Socket.IO 协议层 |

### 当前项目选择

URLSession（HTTP REST）+ Socket.IO Swift 客户端库（实时通信）。

理由：
- 服务端使用 Socket.IO，自行实现协议成本过高（Engine.IO 握手、心跳、命名空间、ACK 回调）
- [socket.io-client-swift](https://github.com/socketio/socket.io-client-swift) 是官方维护的 Swift 客户端
- HTTP REST 用 URLSession 即可，无需额外依赖

### 实施详情

→ Issue「[ADR] 网络通信方案」

### 备注

---

## 加密方案

### 说明

Happy 使用端到端加密，服务端完全无法读取用户内容。需要在 iOS 端实现兼容的加密/解密。

两种加密方案需同时支持：
- Legacy：NaCl XSalsa20-Poly1305（SecretBox）
- Modern：AES-256-GCM（DataKey 方案）

可选加密库：

| 方案 | 覆盖范围 | 优点 | 缺点 |
|------|---------|------|------|
| CryptoKit + libsodium-swift | AES-GCM（原生）+ NaCl（第三方） | AES-GCM 零依赖，NaCl 完整兼容 | 需两个库 |
| 纯 libsodium-swift | NaCl + AEAD | 单一依赖，覆盖全部 | AES-GCM 非 libsodium 原生 |
| 纯 CryptoKit | AES-GCM + Curve25519 | 零依赖 | 不支持 XSalsa20-Poly1305，无法兼容 Legacy |

### 当前项目选择

CryptoKit（AES-256-GCM）+ Swift libsodium 绑定（XSalsa20-Poly1305, Ed25519, X25519）。

理由：
- AES-256-GCM 使用 Apple CryptoKit，性能最优且零依赖
- XSalsa20-Poly1305 和 Ed25519 签名需要 libsodium，CryptoKit 不支持
- Happy 服务端同时使用两种方案，必须全部兼容

### 实施详情

→ Issue「[ADR] 加密方案」

### 备注

Ed25519 用于认证签名（challenge-response）。X25519 用于 DataEncryptionKey 的 box 加密。

---

## 认证方案

### 说明

Happy 使用无密码的公钥认证机制，通过 QR 码扫描完成设备配对。

流程：CLI 生成 QR 码 → 移动端扫描 → 提取 challenge → 签名 → 提交服务端 → 获得 Bearer token。

### 当前项目选择

AVFoundation 相机扫描 QR 码 + Ed25519 签名认证。

理由：
- AVFoundation 是 iOS 原生相机框架，无需第三方依赖
- 密钥对存储在 Keychain（kSecAttrAccessibleWhenUnlockedThisDeviceOnly）
- Bearer token 存储在 Keychain

### 实施详情

→ Issue「[ADR] 认证方案」

### 备注

master secret（32 字节）→ 派生 Ed25519 密钥对（libsodium `crypto_sign_seed_keypair`）→ 签名 challenge → 获取 token。

---

## Markdown 渲染方案

### 说明

Claude Code 的输出大量包含 Markdown，需要在消息流中实时渲染。

可选方案：

| 方案 | 优点 | 缺点 |
|------|------|------|
| AttributedString (iOS 15+) | 原生，零依赖 | 功能有限，不支持代码高亮 |
| cmark + 自定义渲染 | 高性能，完整 CommonMark | 需自行处理代码高亮 |
| swift-markdown + SwiftUI | Apple 官方库 | 需自行构建 SwiftUI 渲染层 |
| MarkdownUI（第三方） | 功能完整，支持代码高亮 | 第三方依赖 |

### 当前项目选择

待定。需要在 P0 消息渲染阶段评估后决策。

### 实施详情

→ Issue「[ADR] Markdown 渲染方案」

### 备注

需支持：标题、列表、代码块（带语法高亮）、行内代码、链接、粗体/斜体。流式渲染场景下性能很重要。
