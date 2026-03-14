<!--
  PRD - 产品需求文档
  记录"做什么"：功能清单、优先级、里程碑
  技术决策请记录在 ADR.md
-->

# PRD

# 产品概述

- 产品：Happy iOS — Claude Code / Codex 原生 iOS 客户端
- 平台：iOS 26+
- 框架：SwiftUI + Swift 6
- 分发：App Store
- 兼容服务端：[Happy Coder](https://github.com/slopus/happy)（`happy-server`）

---

# 已完成

---

# 基础

## P0 — 认证与连接

- [ ] QR 码扫描认证（AVFoundation 相机 → 解析 challenge → Ed25519 签名 → POST /v1/auth）
- [ ] 密钥对生成与安全存储（Keychain，32 字节 master secret）
- [ ] Bearer token 管理（存储、自动附加到请求）
- [ ] 服务端地址配置（默认 + 自定义）

## P0 — 端到端加密

- [ ] NaCl XSalsa20-Poly1305 加解密（Legacy 兼容）
- [ ] AES-256-GCM 加解密（DataKey，推荐方案）
- [ ] DataEncryptionKey 包装/解包装（tweetnacl.box）
- [ ] 会话级、机器级加密 key 管理

## P0 — 会话管理

- [ ] 会话列表（GET /v1/sessions, /v2/sessions）
- [ ] 会话创建/删除
- [ ] 活跃会话标识
- [ ] 会话详情页 — 消息流展示

## P0 — 实时消息同步

- [ ] Socket.IO 连接（/v1/updates，user-scoped）
- [ ] 接收并解密 `new-message` 更新
- [ ] 按 seq 顺序应用 update 事件
- [ ] 消息历史加载（GET /v3/sessions/:id/messages，after_seq 分页）

## P0 — 消息渲染

- [ ] `text` 事件 — Markdown 渲染 + 代码高亮
- [ ] `thinking` 标志 — 思考过程折叠/展开
- [ ] `tool-call-start` / `tool-call-end` — 工具调用卡片（名称、描述、加载状态）
- [ ] `turn-start` / `turn-end` — Agent 处理状态指示
- [ ] `service` 事件 — 系统消息样式

---

# 增强

## P1 — 消息交互

- [ ] 发送用户消息（加密 → Socket.IO `message` 事件）
- [ ] 子 Agent 层级显示（`start` / `stop` 事件，subagent ID 分组）
- [ ] `file` 事件 — 文件附件展示（图片 thumbhash 预览）

## P1 — 机器与守护进程

- [ ] 机器列表（GET /v1/machines）
- [ ] 机器在线/离线状态（`machine-activity` ephemeral 事件）
- [ ] 守护进程状态展示（解密 daemonState）

## P1 — 实时同步增强

- [ ] `update-session` 处理（metadata + agentState 版本化更新）
- [ ] 乐观并发控制（expectedVersion 重试逻辑）
- [ ] 会话心跳（`session-alive`）
- [ ] 断线重连 + 增量同步

## P1 — 推送通知

- [ ] 注册 push token（POST /v1/push/token）
- [ ] 处理远程通知（权限请求、消息提醒）

---

# 扩展

## P2 — Artifact 管理

- [ ] Artifact 列表与详情
- [ ] Artifact 创建/更新/删除（加密 header + body）

## P2 — KV 存储

- [ ] 加密 KV 读写（GET/POST /v1/kv）
- [ ] 批量操作 + 版本校验

## P2 — RPC 转发

- [ ] RPC 调用（Socket.IO `rpc-call`）
- [ ] 权限请求审批 UI

## P2 — 体验优化

- [ ] Widget（活跃会话状态）
- [ ] Live Activity（当前 Agent 运行进度）
- [ ] Shortcuts 集成
- [ ] 语音通信（LiveKit）
- [ ] iPad 适配

---

# Out of Scope

- 服务端开发（使用现有 happy-server）
- CLI 守护进程（使用现有 happy-cli）
- Android / Web 版本
- 自建账户系统（使用 Happy 的公钥认证）
