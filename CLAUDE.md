<!-- 格式规范：尽可能减少加粗格式，保持文档简洁易读 -->

# Talon

## 基本信息

- 名称：Talon
- 平台：iOS（SwiftUI，iOS 26+）
- 架构：MVVM
- 语言：Swift 6

## 产品定位

Talon 是 Claude Code / Codex 的原生 iOS 客户端，完全兼容 [Happy Coder](https://github.com/slopus/happy) 的服务端。

目标：使用 Swift 原生语言 + iOS 26 设计语言，提供比 React Native 实现更原生、更优雅的操作体验。

核心优势：
- 纯 Swift + SwiftUI 原生实现，充分利用 iOS 26 新特性（Liquid Glass 等）
- 与 Happy 服务端完全兼容，共享同一套通信协议和加密方案
- 原生性能和系统集成（通知、Shortcuts、Widget 等）

## 兼容目标：Happy Coder 服务端

### 架构概览

Happy 是一个 TypeScript monorepo，包含 5 个包：
- `happy-server` — Node.js/Fastify 后端（Postgres + Redis + S3）
- `happy-app` — React Native/Expo 移动端 + Web（Talon 要替代的部分）
- `happy-cli` — 本地 CLI 守护进程（包装 Claude/Codex CLI）
- `happy-wire` — 共享协议定义（Zod schema）
- `happy-agent` — 远程会话控制 CLI

### 通信协议

传输层：
- HTTP/REST — 会话创建、Artifact CRUD、KV 存储、账户信息
- WebSocket（Socket.IO）— 实时同步、消息流、RPC
- Socket.IO 路径：`/v1/updates`

连接类型（Socket.IO handshake 中 `clientType`）：
- `user-scoped` — 接收所有账户更新（默认）
- `session-scoped` — 仅接收指定会话更新
- `machine-scoped` — 守护进程连接

### 认证机制

无密码，基于公钥的 challenge-response：
1. 客户端用私钥签名 challenge
2. 服务端用公钥验证签名
3. 返回 Bearer token
4. WebSocket 通过 handshake `auth.token` 传递 token

认证入口：`POST /v1/auth`
移动端通过 QR 码扫描完成认证

### 端到端加密

所有用户内容在客户端加密后传输，服务端完全无法解密。

两种加密方案：
- Legacy（NaCl XSalsa20-Poly1305）— nonce 24 字节 + key 32 字节
- DataKey（AES-256-GCM，推荐）— nonce 12 字节 + authTag 16 字节 + key 32 字节

DataKey 布局：`[version(1) | nonce(12) | ciphertext | authTag(16)]`

加密范围：会话元数据、agent 状态、消息内容、机器信息、Artifact、KV 值

### 会话消息协议（Session Protocol）

消息信封结构：
```json
{
  "id": "cuid2",
  "time": 1739347200000,
  "role": "user | agent",
  "turn": "cuid2?",
  "subagent": "cuid2?",
  "ev": { "t": "event_type", ... }
}
```

9 种事件类型：
- `text` — 文本消息（支持 markdown，可选 `thinking` 标志）
- `service` — Agent 服务消息
- `tool-call-start` — 工具调用开始
- `tool-call-end` — 工具调用结束
- `file` — 文件附件
- `turn-start` — Agent 开始处理
- `turn-end` — Agent 结束（completed/failed/cancelled）
- `start` — 子 Agent 启动
- `stop` — 子 Agent 停止

### Socket.IO 事件

服务端 → 客户端（持久化 `update`）：
- `new-session`, `update-session`, `delete-session`
- `new-message`, `update-account`
- `new-machine`, `update-machine`
- `new-artifact`, `update-artifact`, `delete-artifact`
- `kv-batch-update`

服务端 → 客户端（临时 `ephemeral`）：
- `activity` — 会话活跃状态
- `machine-activity` — 机器在线状态
- `usage` — Token/费用追踪

客户端 → 服务端：
- `message` — 发送加密消息
- `update-metadata` / `update-state` — 更新会话元数据/状态（带乐观并发 `expectedVersion`）
- `session-alive` / `session-end` — 会话心跳
- `artifact-create` / `artifact-update` / `artifact-delete` — Artifact 操作
- `rpc-call` / `rpc-register` — RPC 转发
- `ping` — 连通性检查

### HTTP API 端点

认证：`POST /v1/auth`
会话：`GET/POST /v1/sessions`, `GET /v1/sessions/:id/messages`, `DELETE /v1/sessions/:id`
机器：`POST/GET /v1/machines`
Artifact：`POST /v1/artifacts`, `POST /v1/artifacts/:id`, `DELETE /v1/artifacts/:id`
KV 存储：`POST /v1/kv`, `GET /v1/kv/:key`
推送：`POST /v1/push-tokens`

### 并发控制

- 每用户全局单调递增 `seq`，所有 update 事件按序应用
- 每对象版本号（metadata、agentState、artifact 等）
- 乐观并发：更新时携带 `expectedVersion`，版本不匹配时返回当前值，客户端重试

## 核心功能（待实现）

- QR 码认证（扫描登录）
- 端到端加密（NaCl + AES-256-GCM）
- 会话列表和实时同步
- 会话消息流（9 种事件类型渲染）
- 工具调用可视化
- Markdown 渲染
- Agent 思考过程展示
- 子 Agent 层级显示
- 机器/守护进程状态监控
- Artifact 管理
- 推送通知
- 深色/浅色主题

## 技术栈

- UI 框架：SwiftUI（iOS 26+）
- 架构：MVVM
- 网络：URLSession + Socket.IO Swift 客户端
- 加密：CryptoKit（AES-GCM）+ libsodium/TweetNaCl（XSalsa20-Poly1305）
- 数据持久化：SwiftData
- 第三方依赖：LayoutUIKit、BrandKit、SupabaseKit、RevenueCatKit、PromoKit

## 框架依赖

### Package 依赖

- `LayoutUIKit`: 通用 UI 布局组件库
- `BrandKit`: 品牌设计系统（颜色、字体、图标）
- `SupabaseKit`: Supabase 后端封装
- `RevenueCatKit`: 内购和订阅管理
- `PromoKit`: 推广和营销 UI 组件

### 全局导入

- `TalonApp.swift` 使用 `@_exported import` 全局导出了 `LayoutUIKit` 和 `BrandKit`
- 其他文件无需重复导入这两个模块，直接使用即可

## 参考实现

- 服务端源码：https://github.com/slopus/happy
- 协议定义：`happy-wire/src/messages.ts`, `happy-wire/src/sessionProtocol.ts`
- 加密实现：`happy-cli/src/api/encryption.ts`
- 移动端同步：`happy-app/sources/sync/`
- 服务端 Socket：`happy-server/sources/app/api/socket/`
