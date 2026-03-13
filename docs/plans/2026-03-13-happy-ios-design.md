# Happy Coder iOS 客户端设计文档

## 概述

使用 Swift 原生重写 Happy Coder 移动客户端（原版为 React Native/Expo），完全兼容 Happy Server 后端。采用底层优先策略，逐层构建并通过 CI 自动测试验证。

## 决策摘要

- App 名称：Happy Coder
- 目标平台：iOS 18+（CI 兼容）/ macOS 15+
- MVP 目标：扫码登录 + 完整会话交互
- 架构：MVVM
- 实施策略：底层优先（方案 A），CI 自动测试
- Package 依赖：移除模板项目全部 5 个自定义 Package，从干净状态开始
- UI 风格：iOS 26 原生风格，低版本用 @available 条件编译

## 分层架构

```
┌──────────────────────────────────────┐
│            UI 层 (SwiftUI)           │
│  QR扫码 · 会话列表 · 聊天界面 · 设置   │
├──────────────────────────────────────┤
│          ViewModel 层 (MVVM)         │
│  AuthVM · SessionListVM · ChatVM     │
├──────────────────────────────────────┤
│           Sync 层 (同步引擎)          │
│  SyncManager · SessionSync           │
│  MessageSync · MachineSync           │
├──────────────────────────────────────┤
│         Network 层 (通信)             │
│  HappyAPIClient (HTTP REST)          │
│  HappySocketClient (Socket.IO)       │
├──────────────────────────────────────┤
│         Crypto 层 (加密)              │
│  KeyDerivation · SecretBoxCrypto     │
│  AESGCMCrypto · BoxCrypto            │
│  EncryptionManager                   │
├──────────────────────────────────────┤
│         Storage 层 (持久化)           │
│  SwiftData Models · KeychainStore    │
└──────────────────────────────────────┘
```

每层只依赖下层，不跨层调用。

## 模块对照（Happy TS → Swift）

### Phase 1: Crypto 层

对照 `happy-app/sources/encryption/`（~240 行 TS）

| Happy 文件 | Swift 文件 | 功能 |
|-----------|-----------|------|
| deriveKey.ts | Crypto/KeyDerivation.swift | HMAC-SHA512 密钥派生树 |
| hmac_sha512.ts | （合并到 KeyDerivation） | HMAC-SHA512 |
| libsodium.ts | Crypto/SecretBoxCrypto.swift | NaCl SecretBox 加解密 |
| libsodium.ts | Crypto/BoxCrypto.swift | NaCl Box 非对称加解密 |
| aes.ts | Crypto/AESGCMCrypto.swift | AES-256-GCM 加解密 |
| base64.ts | Crypto/Base64Utils.swift | Base64/Base64URL 编解码 |
| hex.ts | Crypto/HexUtils.swift | Hex 编码 |
| text.ts | （Swift 原生 UTF8） | 不需要 |
| sha512.ts | （CryptoKit 原生） | 不需要 |

依赖：swift-sodium（SPM），CryptoKit（系统框架）

测试：每个加密函数的单元测试，使用 Happy 源码中的已知输入输出做交叉验证。

### Phase 2: Auth 层

对照 `happy-app/sources/auth/`（~537 行 TS）

| Happy 文件 | Swift 文件 | 功能 |
|-----------|-----------|------|
| authChallenge.ts | Auth/AuthChallenge.swift | Ed25519 签名 challenge |
| authQRStart.ts | Auth/QRAuthFlow.swift | QR 认证发起 |
| authQRWait.ts | Auth/QRAuthFlow.swift | QR 认证轮询等待 |
| tokenStorage.ts | Auth/CredentialStore.swift | Keychain 凭证存储 |
| secretKeyBackup.ts | Auth/SecretKeyBackup.swift | Base32 备份格式 |
| AuthContext.tsx | （Phase 6 ViewModel） | 后续 UI 阶段 |

测试：challenge 签名验证、Base32 编解码、Keychain 读写。

### Phase 3: Sync 加密层

对照 `happy-app/sources/sync/encryption/`（~621 行 TS）

| Happy 文件 | Swift 文件 | 功能 |
|-----------|-----------|------|
| encryptor.ts | SyncEncryption/Encryptor.swift | 3 种加密器（SecretBox/Box/AES256） |
| encryption.ts | SyncEncryption/EncryptionManager.swift | 密钥层级管理、DEK 包装 |
| encryptionCache.ts | SyncEncryption/EncryptionCache.swift | 解密结果缓存 |
| sessionEncryption.ts | SyncEncryption/SessionEncryption.swift | 会话级加解密 |
| machineEncryption.ts | SyncEncryption/MachineEncryption.swift | 机器级加解密 |
| artifactEncryption.ts | SyncEncryption/ArtifactEncryption.swift | Artifact 加解密 |

测试：EncryptionManager 完整密钥派生链、加密→解密往返验证。

### Phase 4: Network 层

对照 `happy-app/sources/sync/apiSocket.ts` + `apiTypes.ts`（~447 行 TS）

| Happy 文件 | Swift 文件 | 功能 |
|-----------|-----------|------|
| apiTypes.ts | Network/APITypes.swift | 所有请求/响应 Codable 类型 |
| apiSocket.ts | Network/HappySocketClient.swift | Socket.IO 客户端封装 |
| serverConfig.ts | Network/ServerConfig.swift | 服务端地址配置 |
| （HTTP 调用散布在 sync.ts） | Network/HappyAPIClient.swift | HTTP REST 客户端 |

依赖：socket.io-client-swift（SPM）

类型定义对照 `happy-wire/src/`：
- messages.ts → APITypes.swift（SessionMessage, UpdateEvent 等）
- sessionProtocol.ts → APITypes.swift（SessionEnvelope, 9 种事件类型）
- legacyProtocol.ts → APITypes.swift（Legacy 消息格式）
- messageMeta.ts → APITypes.swift（MessageMeta）

### Phase 5: Sync 引擎

对照 `happy-app/sources/sync/sync.ts` + `storage.ts` + `reducer/`（~4696 行 TS）

| Happy 文件 | Swift 文件 | 功能 |
|-----------|-----------|------|
| sync.ts | Sync/SyncManager.swift | 主同步协调器 |
| storage.ts | Sync/SyncStorage.swift | 本地状态管理 |
| reducer/state.ts | Sync/SyncState.swift | 同步状态定义 |
| reducer/ops.ts | Sync/SyncReducer.swift | 状态变更操作 |
| reducer/types.ts | Sync/SyncActions.swift | Action 类型 |
| invalidateSync.ts | Sync/InvalidateSync.swift | 防抖同步触发 |

SwiftData 模型（对照 Prisma schema）：
- Models/Session.swift（对应 Session 表）
- Models/SessionMessage.swift（对应 SessionMessage 表）
- Models/Machine.swift（对应 Machine 表）
- Models/Artifact.swift（对应 Artifact 表）

### Phase 6: UI 层

对照 `happy-app/sources/app/` + `components/` + `modules/`（~7300 行 TS）

核心页面：

| Happy 屏幕 | Swift View | 功能 |
|-----------|-----------|------|
| app/auth/qr.tsx | Views/Auth/QRScannerView.swift | QR 码扫描 |
| app/auth/manual.tsx | Views/Auth/ManualKeyView.swift | 手动输入密钥 |
| app/(app)/index.tsx | Views/Sessions/SessionListView.swift | 会话列表 |
| app/(app)/session/[id].tsx | Views/Chat/ChatView.swift | 聊天界面 |
| app/(app)/machines.tsx | Views/Machines/MachineListView.swift | 机器列表 |
| app/(app)/settings.tsx | Views/Settings/SettingsView.swift | 设置 |
| app/create-session.tsx | Views/Sessions/CreateSessionView.swift | 创建会话 |
| modal/compose.tsx | Views/Chat/ComposeView.swift | 消息编辑 |

核心组件：

| Happy 组件 | Swift 组件 | 功能 |
|-----------|-----------|------|
| ConversationView.tsx | Components/ConversationView.swift | 消息列表 |
| MessageRenderer.tsx | Components/MessageRenderer.swift | 单条消息渲染 |
| AgentInput.tsx | Components/AgentInput.swift | 消息输入框 |
| ToolCallView.tsx | Components/ToolCallView.swift | 工具调用卡片 |
| ThinkingAnimation.tsx | Components/ThinkingAnimation.swift | 思考动画 |
| SessionItem.tsx | Components/SessionItem.swift | 会话行 |
| QRScanner.tsx | Components/QRScanner.swift | 相机扫码 |
| StatusBanner.tsx | Components/StatusBanner.swift | 连接状态横幅 |
| content/TextContent.tsx | Components/Content/TextContent.swift | 文本+Markdown |
| content/FileContent.tsx | Components/Content/FileContent.swift | 文件附件 |
| content/ThinkingContent.tsx | Components/Content/ThinkingContent.swift | 思考内容 |
| markdown/MarkdownView.tsx | Components/Markdown/MarkdownView.swift | Markdown 渲染 |
| markdown/CodeBlock.tsx | Components/Markdown/CodeBlock.swift | 代码块高亮 |

## 项目目录结构（Swift）

```
HappyCoder/
├── App/
│   └── HappyCoderApp.swift
├── Crypto/
│   ├── KeyDerivation.swift
│   ├── SecretBoxCrypto.swift
│   ├── BoxCrypto.swift
│   ├── AESGCMCrypto.swift
│   ├── Base64Utils.swift
│   └── HexUtils.swift
├── Auth/
│   ├── AuthChallenge.swift
│   ├── QRAuthFlow.swift
│   ├── CredentialStore.swift
│   └── SecretKeyBackup.swift
├── SyncEncryption/
│   ├── Encryptor.swift
│   ├── EncryptionManager.swift
│   ├── EncryptionCache.swift
│   ├── SessionEncryption.swift
│   ├── MachineEncryption.swift
│   └── ArtifactEncryption.swift
├── Network/
│   ├── APITypes.swift
│   ├── HappyAPIClient.swift
│   ├── HappySocketClient.swift
│   └── ServerConfig.swift
├── Sync/
│   ├── SyncManager.swift
│   ├── SyncStorage.swift
│   ├── SyncState.swift
│   ├── SyncReducer.swift
│   └── InvalidateSync.swift
├── Models/
│   ├── Session.swift
│   ├── SessionMessage.swift
│   ├── Machine.swift
│   └── Artifact.swift
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── SessionListViewModel.swift
│   └── ChatViewModel.swift
├── Views/
│   ├── Auth/
│   ├── Sessions/
│   ├── Chat/
│   ├── Machines/
│   └── Settings/
├── Components/
│   ├── ConversationView.swift
│   ├── MessageRenderer.swift
│   ├── AgentInput.swift
│   ├── ToolCallView.swift
│   ├── ThinkingAnimation.swift
│   ├── SessionItem.swift
│   ├── QRScanner.swift
│   ├── StatusBanner.swift
│   ├── Content/
│   └── Markdown/
└── Resources/
    └── Assets.xcassets
```

## 第三方依赖（SPM）

| 库 | 用途 | 替代 Happy 中的 |
|---|------|----------------|
| [swift-sodium](https://github.com/jedisct1/swift-sodium) | NaCl 加密（XSalsa20, Box, Sign） | @more-tech/react-native-libsodium |
| [socket.io-client-swift](https://github.com/socketio/socket.io-client-swift) | Socket.IO v4 实时通信 | socket.io-client |

Apple 原生框架：
- CryptoKit — AES-256-GCM, HMAC-SHA512
- AVFoundation — QR 码扫描
- Security — Keychain 存储
- SwiftData — 数据持久化

## 不在 MVP 范围

- LiveKit 语音通信（对照 realtime/）
- i18n 多语言（对照 text/）
- PostHog 分析（对照 track/）
- 好友系统（对照 modules/friends/）
- RevenueCat 订阅
- Artifact 管理
- KV 存储操作
- iPad 适配
