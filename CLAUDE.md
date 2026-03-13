<!-- 格式规范：尽可能减少加粗格式，保持文档简洁易读 -->

# Happy iOS

## 基本信息

- 名称：Happy（原生 iOS 客户端）
- 平台：iOS（SwiftUI，iOS 26+）
- 语言：Swift 6
- 架构：MVVM

## 产品定位

Happy iOS 是 [Happy Coder](https://github.com/slopus/happy) 的原生 iOS 客户端，完全兼容其服务端。

Happy Coder 是 Claude Code / Codex 的移动端客户端，支持端到端加密。原版使用 React Native/Expo 实现，本项目使用 Swift + iOS 26 原生重写，提供更原生、更优雅的操作体验。

核心优势：
- 纯 Swift + SwiftUI，充分利用 iOS 26 新特性（Liquid Glass 等）
- 原生性能和系统集成（推送通知、Shortcuts、Widget、Live Activity）
- 与 Happy 服务端完全兼容，共享同一套通信协议和加密方案

## 核心功能

- QR 码扫描认证（无密码，公钥 challenge-response）
- 端到端加密（NaCl XSalsa20-Poly1305 + AES-256-GCM）
- 会话列表与实时同步（Socket.IO）
- Claude Code 消息流渲染（9 种事件类型）
- 工具调用可视化（tool-call-start / tool-call-end）
- Agent 思考过程展示（thinking 标志）
- 子 Agent 层级显示
- Markdown 渲染 + 代码高亮
- 机器/守护进程状态监控
- Artifact 管理
- 推送通知
- RPC 远程调用转发

## 兼容目标：Happy Coder 服务端

### 服务端架构

Happy 是 TypeScript monorepo，包含 5 个包：
- `happy-server` — Node.js/Fastify 后端（Postgres + Redis + S3），端口 3005
- `happy-app` — React Native/Expo 移动端（本项目要替代的部分）
- `happy-cli` — 本地 CLI 守护进程（包装 Claude/Codex CLI）
- `happy-wire` — 共享协议定义（Zod schema）
- `happy-agent` — 远程会话控制 CLI

默认服务端地址：`https://api.cluster-fluster.com`

### 认证机制

无密码，基于公钥 challenge-response：
1. 客户端生成 32 字节 master secret，派生 Ed25519 密钥对
2. 通过 QR 码扫描获取 challenge
3. 用私钥签名 challenge（`crypto_sign_detached`）
4. `POST /v1/auth` 提交 publicKey + challenge + signature
5. 服务端验证后返回 Bearer token
6. WebSocket 通过 handshake `auth.token` 传递 token

### 端到端加密

所有用户内容在客户端加密后传输，服务端完全无法解密。

两种加密方案：
- Legacy（NaCl XSalsa20-Poly1305）— 布局：`[nonce(24) | ciphertext+auth]`，key 32 字节
- DataKey（AES-256-GCM，推荐）— 布局：`[version(1) | nonce(12) | ciphertext | authTag(16)]`，key 32 字节

DataKey 的 DEK 通过 `tweetnacl.box` 加密包装：`[ephPublicKey(32) | nonce(24) | ciphertext]`

加密范围：会话元数据、agent 状态、消息内容、机器信息、Artifact、KV 值

### 消息协议（Session Protocol）

信封结构：
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
- `text` — 文本消息（markdown，可选 `thinking` 标志）
- `service` — Agent 服务消息
- `tool-call-start` — 工具调用开始（name, title, description, args）
- `tool-call-end` — 工具调用结束（匹配 call ID）
- `file` — 文件附件（ref, name, size, 可选 image thumbhash）
- `turn-start` — Agent 开始处理
- `turn-end` — Agent 结束（completed / failed / cancelled）
- `start` — 子 Agent 启动
- `stop` — 子 Agent 停止

消息加密传输格式：
```json
{ "t": "encrypted", "c": "<base64_encrypted_content>" }
```

### 实时通信（Socket.IO）

连接路径：`/v1/updates`
连接类型（handshake `clientType`）：
- `user-scoped` — 接收所有账户更新（默认）
- `session-scoped` — 仅接收指定会话更新
- `machine-scoped` — 守护进程连接

服务端 → 客户端（持久化 `update`，带单调递增 `seq`）：
- `new-session`, `update-session`, `delete-session`
- `new-message`
- `update-account`
- `new-machine`, `update-machine`
- `new-artifact`, `update-artifact`, `delete-artifact`
- `kv-batch-update`

服务端 → 客户端（临时 `ephemeral`，不持久化）：
- `activity` — 会话活跃状态
- `machine-activity` — 机器在线状态
- `usage` — Token/费用追踪
- `machine-status` — 机器状态

客户端 → 服务端：
- `message` — 发送加密消息（sid + base64 encrypted content）
- `update-metadata` / `update-state` — 更新元数据/状态（带 `expectedVersion`）
- `session-alive` / `session-end` — 会话心跳
- `artifact-create` / `artifact-update` / `artifact-read` / `artifact-delete`
- `rpc-call` / `rpc-register` / `rpc-unregister` — RPC 转发
- `ping` — 连通性检查
- `access-key-get` — 获取 access key

### HTTP API 端点

认证：
- `POST /v1/auth` — challenge-response 认证
- `POST /v1/auth/request` — 终端 QR 认证请求
- `GET /v1/auth/request/status` — 查询认证状态
- `POST /v1/auth/response` — 批准认证请求

会话：
- `GET /v1/sessions` — 列表（最近 150 个）
- `GET /v2/sessions` — 游标分页（limit 1-200）
- `GET /v2/sessions/active` — 活跃会话
- `POST /v1/sessions` — 创建/按 tag 加载
- `GET /v3/sessions/:id/messages` — 消息历史（after_seq 分页）
- `POST /v3/sessions/:id/messages` — 批量发送消息
- `POST /v1/sessions/:id/delete` — 删除会话

机器：
- `POST /v1/machines` — 注册机器
- `GET /v1/machines` — 列表
- `GET /v1/machines/:id` — 详情

Artifact：
- `POST /v1/artifacts` — 创建
- `PATCH /v1/artifacts/:id` — 更新
- `GET /v1/artifacts` / `GET /v1/artifacts/:id` — 列表/详情
- `DELETE /v1/artifacts/:id` — 删除

KV 存储：
- `GET /v1/kv/:key` — 读取
- `GET /v1/kv?prefix=` — 前缀查询
- `POST /v1/kv/bulk` — 批量读取
- `POST /v1/kv` — 原子批量写入（乐观并发，version 校验）

推送：`POST /v1/push/token`
语音：`POST /v1/voice/sessions/:id/token`（LiveKit）

### 并发控制

- 每用户全局单调递增 `seq`，所有 update 事件按序应用
- 每对象版本号（metadata、agentState、artifact header/body、KV）
- 乐观并发：更新时携带 `expectedVersion`，版本不匹配返回当前值，客户端重试

## 技术栈

- UI 框架：SwiftUI（iOS 26+）
- 架构：MVVM
- 网络：URLSession + SocketIO Swift 客户端
- 加密：CryptoKit（AES-GCM）+ libsodium/Swift（NaCl XSalsa20-Poly1305, Ed25519 签名）
- 数据持久化：SwiftData
- QR 码：AVFoundation 相机扫描
- Markdown：AttributedString 或 cmark

## 框架依赖

### Package 依赖

- `LayoutUIKit`: 通用 UI 布局组件库
- `BrandKit`: 品牌设计系统（颜色、字体、图标）
- `SupabaseKit`: Supabase 后端封装（本项目可能不需要）
- `RevenueCatKit`: 内购和订阅管理
- `PromoKit`: 推广和营销 UI 组件

### 全局导入

- `TalonApp.swift` 使用 `@_exported import` 全局导出了 `LayoutUIKit` 和 `BrandKit`
- 其他文件无需重复导入这两个模块，直接使用即可

## 参考实现

- 源码：https://github.com/slopus/happy
- 协议定义：`happy-wire/src/messages.ts`, `happy-wire/src/sessionProtocol.ts`
- 加密实现：`happy-cli/src/api/encryption.ts`
- 移动端同步：`happy-app/sources/sync/`
- 移动端认证：`happy-app/sources/auth/`
- 服务端 Socket：`happy-server/sources/app/api/socket/`
- 服务端路由：`happy-server/sources/app/api/routes/`
- 数据库 Schema：`happy-server/prisma/schema.prisma`
