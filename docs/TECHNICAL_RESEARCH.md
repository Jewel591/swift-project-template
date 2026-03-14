<!--
  技术调研文档
  记录 Happy Coder 服务端协议的完整实现细节
  用于指导 Swift 原生 iOS 客户端的开发
  所有内容基于 https://github.com/slopus/happy 源码分析
-->

# Happy Coder 服务端兼容性技术调研

## 调研结论

技术上完全可行，无阻断点。所有协议和加密算法均可在 iOS/Swift 上实现。

---

# 一、加密系统

Happy 的核心设计原则：端到端加密，服务端完全无法解密用户内容。

## 1.1 密钥层级

```
Master Secret（32 字节，QR 认证时从桌面端获取）
│
├── deriveKey(masterSecret, 'Happy EnCoder', ['content'])
│   → contentDataKey（32 字节）
│   → crypto_box_seed_keypair(contentDataKey)
│     → contentKeyPair { publicKey, privateKey }（用于加解密 DEK）
│
├── deriveKey(masterSecret, 'Happy Coder', ['analytics', 'id'])
│   → anonID（取前 16 字符 hex，用于匿名分析）
│
└── 直接用作 SecretBoxEncryption 的 key（Legacy 加密）
```

## 1.2 密钥派生算法

源码：`happy-app/sources/encryption/deriveKey.ts`

使用 HD wallet 风格的 HMAC-SHA512 树形派生（类似 BIP32 但自定义）：

```
deriveSecretKeyTreeRoot(seed, usage):
  I = HMAC-SHA512(key = UTF8(usage + ' Master Seed'), data = seed)
  key = I[0:32]
  chainCode = I[32:64]
  return { key, chainCode }

deriveSecretKeyTreeChild(chainCode, index):
  data = [0x00 || UTF8(index)]    // 前置一个 0x00 字节作为分隔符
  I = HMAC-SHA512(key = chainCode, data = data)
  key = I[0:32]
  chainCode = I[32:64]
  return { key, chainCode }

deriveKey(master, usage, path[]):
  state = deriveSecretKeyTreeRoot(master, usage)
  for each index in path:
    state = deriveSecretKeyTreeChild(state.chainCode, index)
  return state.key
```

Swift 可行性：CryptoKit 原生支持 HMAC-SHA512，零依赖。

## 1.3 三种加密方案

### 1.3.1 SecretBox 加密（Legacy）

源码：`happy-app/sources/encryption/libsodium.ts` 第 36-57 行

算法：NaCl XSalsa20-Poly1305（tweetnacl.secretbox）

```
加密 encryptSecretBox(data, secret):
  plaintext = UTF8(JSON.stringify(data))
  nonce = randomBytes(24)
  ciphertext = crypto_secretbox_easy(plaintext, nonce, secret)
  return [nonce(24) || ciphertext+authTag]

解密 decryptSecretBox(bundle, secret):
  nonce = bundle[0:24]
  ciphertext = bundle[24:]
  plaintext = crypto_secretbox_open_easy(ciphertext, nonce, secret)
  return JSON.parse(UTF8Decode(plaintext))
```

- Key：32 字节（masterSecret）
- Nonce：24 字节（随机）
- 二进制布局：`[nonce(24) | ciphertext+poly1305_tag]`
- 用途：没有 dataEncryptionKey 的旧会话/机器数据

Swift 可行性：需要 libsodium。CryptoKit 不支持 XSalsa20-Poly1305。使用 [swift-sodium](https://github.com/jedisct1/swift-sodium)。

### 1.3.2 Box 加密（非对称）

源码：`happy-app/sources/encryption/libsodium.ts` 第 8-34 行

算法：X25519 ECDH + XSalsa20-Poly1305（tweetnacl.box）

```
加密 encryptBox(data, recipientPublicKey):
  ephemeralKeyPair = crypto_box_keypair()
  nonce = randomBytes(24)           // crypto_box_NONCEBYTES = 24
  ciphertext = crypto_box_easy(data, nonce, recipientPublicKey, ephemeralKeyPair.privateKey)
  return [ephemeralPublicKey(32) || nonce(24) || ciphertext+authTag]

解密 decryptBox(bundle, recipientSecretKey):
  ephemeralPublicKey = bundle[0:32]   // crypto_box_PUBLICKEYBYTES = 32
  nonce = bundle[32:56]
  ciphertext = bundle[56:]
  plaintext = crypto_box_open_easy(ciphertext, nonce, ephemeralPublicKey, recipientSecretKey)
  return plaintext
```

- 二进制布局：`[ephemeral_pk(32) | nonce(24) | ciphertext+poly1305_tag]`
- 用途：QR 认证时加密 masterSecret、DataEncryptionKey 的包装

Swift 可行性：需要 libsodium（crypto_box 语义与 CryptoKit Curve25519 不完全相同）。

### 1.3.3 AES-256-GCM 加密（推荐方案）

源码：`happy-app/sources/sync/encryption/encryptor.ts` 第 81-126 行

算法：AES-256-GCM（标准 NIST）

```
加密 AES256Encryption.encrypt(data):
  plaintext = JSON.stringify(data)
  encrypted = AES-GCM-Encrypt(plaintext, dataEncryptionKey)
  // encrypted 的内部格式由 rn-encryption 库决定：[nonce(12) | ciphertext | authTag(16)]
  output = [version_byte(1) || encrypted]
  output[0] = 0x00      // 版本号固定为 0
  return output

解密 AES256Encryption.decrypt(bundle):
  if bundle[0] !== 0: return null   // 版本检查
  encrypted = bundle[1:]
  plaintext = AES-GCM-Decrypt(encrypted, dataEncryptionKey)
  return JSON.parse(plaintext)
```

- Key：32 字节（dataEncryptionKey，每个会话/机器独立）
- Nonce：12 字节（随机，GCM 标准）
- Auth Tag：16 字节
- 二进制布局：`[version(1) | nonce(12) | ciphertext | authTag(16)]`
- version 固定为 `0x00`
- 用途：有 dataEncryptionKey 的新会话/机器数据

Swift 可行性：CryptoKit `AES.GCM` 原生支持，零依赖。

### 1.3.4 加密方案选择逻辑

源码：`happy-app/sources/sync/encryption/encryption.ts` 第 51-56 行

```
openEncryption(dataEncryptionKey):
  if dataEncryptionKey === null:
    return SecretBoxEncryption(masterSecret)    // Legacy
  else:
    return AES256Encryption(dataEncryptionKey)  // Modern
```

## 1.4 DataEncryptionKey 的加密包装

源码：`happy-app/sources/sync/encryption/encryption.ts` 第 162-182 行

DEK（每个会话/机器独立的 32 字节 AES key）通过 Box 加密包装后存储在服务端：

```
加密 encryptEncryptionKey(key):
  encrypted = encryptBox(key, contentKeyPair.publicKey)  // 用自己的公钥加密
  return [0x00 || encrypted]                              // 前置版本字节

解密 decryptEncryptionKey(encrypted_base64):
  data = base64Decode(encrypted_base64)
  if data[0] !== 0: return null                            // 版本检查
  return decryptBox(data[1:], contentKeyPair.privateKey)   // 用自己的私钥解密
```

二进制布局：`[version(1) | ephemeral_pk(32) | nonce(24) | ciphertext+tag]`

## 1.5 消息内容的加密传输

源码：`happy-app/sources/sync/encryption/sessionEncryption.ts`

```
服务端存储格式（JSON）:
{
  "t": "encrypted",
  "c": "<base64_encoded_encrypted_bytes>"
}

发送消息:
  1. data = { role: "session", content: { SessionEnvelope }, meta?: {...} }
  2. encrypted_bytes = encryptor.encrypt([data])    // SecretBox 或 AES256
  3. encoded = base64Encode(encrypted_bytes[0])
  4. 发送: { content: { t: "encrypted", c: encoded } }

接收消息:
  1. 从 content.c 取出 base64 字符串
  2. encrypted_bytes = base64Decode(content.c)
  3. data = encryptor.decrypt([encrypted_bytes])
  4. 解析 data 中的 SessionEnvelope
```

## 1.6 Swift 加密方案对照表

| 算法 | Happy 库 | Swift 方案 | 依赖 |
|------|---------|-----------|------|
| HMAC-SHA512 | 自实现 | CryptoKit `HMAC<SHA512>` | 无 |
| XSalsa20-Poly1305 | tweetnacl/libsodium | swift-sodium `SecretBox` | swift-sodium |
| X25519 + XSalsa20 (box) | tweetnacl/libsodium | swift-sodium `Box` | swift-sodium |
| AES-256-GCM | rn-encryption | CryptoKit `AES.GCM` | 无 |
| Ed25519 签名 | tweetnacl/libsodium | swift-sodium `Sign` 或 CryptoKit `Curve25519.Signing` | 可选 |
| crypto_box_seed_keypair | libsodium | swift-sodium `Box.keyPair(seed:)` | swift-sodium |
| crypto_sign_seed_keypair | libsodium | swift-sodium `Sign.keyPair(seed:)` | swift-sodium |
| SHA-512 | 自实现 | CryptoKit `SHA512` | 无 |

关键结论：必须引入 swift-sodium（或直接桥接 libsodium C 库），因为 CryptoKit 不支持 XSalsa20-Poly1305 和 NaCl box 语义。

---

# 二、认证系统

## 2.1 QR 码认证流程（移动端扫码登录）

源码：`happy-app/sources/auth/authQRStart.ts`, `authQRWait.ts`, `authChallenge.ts`

这是移动端 **首次配对** 的流程，用于从桌面端获取 masterSecret：

```
步骤 1: 移动端生成临时密钥对
  secret = randomBytes(32)
  keypair = crypto_box_seed_keypair(secret)   // X25519 密钥对
  → { publicKey(32), secretKey(32) }

步骤 2: 移动端发起认证请求
  POST /v1/auth/account/request
  Body: { publicKey: base64(keypair.publicKey) }
  服务端创建 AccountAuthRequest 记录

步骤 3: 桌面端（CLI）扫描 QR 码
  QR 码内容包含移动端的 publicKey
  桌面端用 encryptBox(masterSecret, mobile_publicKey) 加密 masterSecret
  POST /v1/auth/account/response
  Body: { response: base64(encrypted_master_secret), publicKey: base64(mobile_publicKey) }
  Headers: Authorization: Bearer <desktop_token>

步骤 4: 移动端轮询等待
  每隔 1 秒 POST /v1/auth/account/request（同一个 publicKey）
  当 response.state === 'authorized':
    token = response.data.token
    encrypted_response = base64Decode(response.data.response)
    masterSecret = decryptBox(encrypted_response, keypair.secretKey)
    → 获得 { secret: masterSecret, token: bearer_token }

步骤 5: 存储凭证
  TokenStorage.setCredentials({
    token: bearer_token,
    secret: base64url(masterSecret)
  })
  iOS 端存储在 Keychain（React Native 用 expo-secure-store）
```

## 2.2 Challenge-Response 认证（Token 获取）

源码：`happy-app/sources/auth/authChallenge.ts`

这是 **已有 masterSecret** 时直接获取 token 的流程：

```
authChallenge(secret):
  keypair = crypto_sign_seed_keypair(secret)   // Ed25519 密钥对（注意：不是 box keypair）
  challenge = randomBytes(32)
  signature = crypto_sign_detached(challenge, keypair.privateKey)
  return { challenge, signature, publicKey: keypair.publicKey }

POST /v1/auth
Body: {
  publicKey: base64(publicKey),      // Ed25519 公钥，32 字节
  challenge: base64(challenge),      // 随机 32 字节
  signature: base64(signature)       // Ed25519 签名，64 字节
}
Response: { success: true, token: "bearer_token_string" }
```

服务端验证：`tweetnacl.sign.detached.verify(challenge, signature, publicKey)`

重要区分：
- QR 认证用 `crypto_box_seed_keypair`（X25519）— 用于 ECDH 加密传输 masterSecret
- Token 认证用 `crypto_sign_seed_keypair`（Ed25519）— 用于签名验证身份

## 2.3 Token 存储

源码：`happy-app/sources/auth/tokenStorage.ts`

```
存储结构:
{
  token: string,          // Bearer token
  secret: string          // masterSecret 的 base64url 编码
}

iOS (React Native): expo-secure-store → Keychain
Web: localStorage

Swift 对应方案: Keychain Services (kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
```

## 2.4 密钥备份格式

源码：`happy-app/sources/auth/secretKeyBackup.ts`

masterSecret 可以导出为用户友好格式用于备份：

```
格式: "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XX"
编码: Base32 (RFC 4648: ABCDEFGHIJKLMNOPQRSTUVWXYZ234567)
32 字节 = 256 位 = 52 个 Base32 字符 → 11 组，每组 5 字符，用 - 分隔

恢复时容错映射: 0→O, 1→I, 8→B, 9→G
```

---

# 三、实时通信（Socket.IO）

## 3.1 服务端配置

源码：`happy-server/sources/app/api/socket.ts`

```
Socket.IO 版本: 4.8.1（服务端和客户端）
路径: /v1/updates
传输: websocket + polling（服务端），websocket only（客户端）
命名空间: 默认（无自定义）
数据格式: 纯 JSON（无二进制帧）
pingTimeout: 45000ms
pingInterval: 15000ms
connectTimeout: 20000ms
upgradeTimeout: 10000ms
CORS: origin "*"
```

## 3.2 连接认证

```
Handshake auth 对象:
{
  token: string,                    // Bearer token
  clientType: "user-scoped" | "session-scoped" | "machine-scoped",
  sessionId?: string,               // clientType === "session-scoped" 时必填
  machineId?: string                // clientType === "machine-scoped" 时必填
}

移动端使用 "user-scoped"（接收所有更新）
```

## 3.3 客户端 → 服务端事件

### message — 发送加密消息

```
socket.emit('message', {
  sid: string,                      // Session ID
  message: string,                  // base64 加密后的消息内容
  localId?: string                  // 可选，客户端去重 ID
})
// 无回调
```

### update-metadata — 更新会话元数据

```
socket.emitWithAck('update-metadata', {
  sid: string,
  metadata: string,                 // base64 加密后的元数据
  expectedVersion: number           // 乐观并发版本号
})
→ 回调: {
  result: "success" | "version-mismatch" | "error",
  version?: number,                 // 成功时新版本号
  metadata?: string                 // 冲突时当前值
}
```

### update-state — 更新 Agent 状态

```
socket.emitWithAck('update-state', {
  sid: string,
  agentState: string | null,
  expectedVersion: number
})
→ 回调: 同 update-metadata 格式
```

### session-alive — 会话心跳

```
socket.emit('session-alive', {
  sid: string,
  time: number,                     // 毫秒时间戳
  thinking?: boolean
})
// 无回调
```

### session-end — 结束会话

```
socket.emit('session-end', {
  sid: string,
  time: number
})
```

### machine-alive — 机器心跳

```
socket.emit('machine-alive', {
  machineId: string,
  time: number
})
```

### machine-update-metadata — 更新机器元数据

```
socket.emitWithAck('machine-update-metadata', {
  machineId: string,
  metadata: string,
  expectedVersion: number
})
→ 回调: { result, version?, metadata?, message? }
```

### machine-update-state — 更新守护进程状态

```
socket.emitWithAck('machine-update-state', {
  machineId: string,
  daemonState: string,
  expectedVersion: number
})
→ 回调: { result, version?, daemonState?, message? }
```

### artifact-read — 读取 Artifact

```
socket.emitWithAck('artifact-read', {
  artifactId: string
})
→ 回调: {
  result: "success" | "error",
  artifact?: {
    id, header(base64), headerVersion, body(base64), bodyVersion,
    seq, createdAt(ms), updatedAt(ms)
  },
  message?: string
}
```

### artifact-create — 创建 Artifact

```
socket.emitWithAck('artifact-create', {
  id: string,
  header: string,                   // base64
  body: string,                     // base64
  dataEncryptionKey: string         // base64
})
→ 回调: { result, artifact?, message? }
```

### artifact-update — 更新 Artifact

```
socket.emitWithAck('artifact-update', {
  artifactId: string,
  header?: { data: string, expectedVersion: number },
  body?: { data: string, expectedVersion: number }
})
→ 回调: { result, header?: { version, data }, body?: { version, data }, message? }
```

### artifact-delete — 删除 Artifact

```
socket.emitWithAck('artifact-delete', { artifactId: string })
→ 回调: { result, message? }
```

### rpc-call — RPC 远程调用

```
socket.timeout(30000).emitWithAck('rpc-call', {
  method: string,                   // "sessionId:methodName" 或 "machineId:methodName"
  params: string                    // base64 加密的参数
})
→ 回调: { ok: boolean, result?: any, error?: string }
```

### rpc-register / rpc-unregister — RPC 处理器注册

```
socket.emit('rpc-register', { method: string })
socket.emit('rpc-unregister', { method: string })
```

### usage-report — 用量上报

```
socket.emitWithAck('usage-report', {
  key: string,
  sessionId?: string,
  tokens: { total, input, output, cache_creation, cache_read },
  cost: { total, input, output }
})
→ 回调: { success, reportId?, createdAt?, updatedAt?, error? }
```

### access-key-get — 获取 Access Key

```
socket.emitWithAck('access-key-get', {
  sessionId: string,
  machineId: string
})
→ 回调: {
  ok: boolean,
  accessKey?: { data, dataVersion, createdAt, updatedAt } | null,
  error?: string
}
```

### ping — 连通性检查

```
socket.emit('ping', callback)
→ 回调: {}
```

## 3.4 服务端 → 客户端事件

### update — 持久化更新（带 seq，重连后可追溯）

```
socket.on('update', (payload) => {
  payload: {
    id: string,
    seq: number,                    // 用户级单调递增序列号
    body: UpdateEvent,              // 见下方类型列表
    createdAt: number
  }
})

UpdateEvent 类型（由 body.t 区分）:
- "new-session":    { t, id, seq, tag, metadata, agentState?, dataEncryptionKey?, active, lastActiveAt, createdAt, updatedAt }
- "update-session": { t, id, metadata?: { version, value }, agentState?: { version, value } }
- "delete-session": { t, sid }
- "new-message":    { t, sid, message: { id, seq, content: { t: "encrypted", c: base64 }, localId?, createdAt, updatedAt } }
- "new-machine":    { t, machineId, seq, metadata, metadataVersion, daemonState?, daemonStateVersion, dataEncryptionKey?, active, lastActiveAt, createdAt, updatedAt }
- "update-machine": { t, machineId, metadata?: { version, value }, daemonState?: { version, value }, active?, activeAt? }
- "new-artifact":   { t, artifactId, seq, header, headerVersion, body, bodyVersion, dataEncryptionKey, createdAt, updatedAt }
- "update-artifact":{ t, artifactId, header?: { version, data }, body?: { version, data } }
- "delete-artifact":{ t, artifactId }
- "update-account": { t, id, ... }
- "relationship-updated": { t, uid, status, ... }
- "new-feed-post":  { t, id, body, ... }
- "kv-batch-update":{ t, changes: [{ key, value, version }] }
```

### ephemeral — 临时事件（不持久化，断线后不重放）

```
socket.on('ephemeral', (payload) => {
  payload 类型（由 type 区分）:
  - { type: "activity", id(sessionId), active: boolean, activeAt: number, thinking?: boolean }
  - { type: "machine-activity", id(machineId), active: boolean, activeAt: number }
  - { type: "usage", id, key, tokens: {...}, cost: {...}, timestamp }
  - { type: "machine-status", machineId, online: boolean, timestamp }
})
```

## 3.5 重连机制

```
客户端配置:
  reconnection: true
  reconnectionDelay: 1000ms
  reconnectionDelayMax: 5000ms
  reconnectionAttempts: Infinity

重连后处理:
  客户端触发 onReconnected() 回调
  → 全量重新拉取: sessions, machines, artifacts, friends, feed
  → 通过 HTTP API 获取最新状态，而非依赖 seq 增量追赶
```

## 3.6 Swift Socket.IO 兼容性

[socket.io-client-swift](https://github.com/socketio/socket.io-client-swift) 支持情况：

| 需求 | 支持状态 |
|------|---------|
| Socket.IO v4 协议 | ✅ |
| WebSocket 传输 | ✅ |
| Polling fallback | ✅ |
| JSON 载荷 | ✅ |
| handshake auth 对象 | ✅ |
| emitWithAck 回调 | ✅ |
| .on() 事件监听 | ✅ |
| 自动重连 | ✅ |
| 二进制帧 | 不需要 |
| 自定义命名空间 | 不需要 |

潜在风险：socket.io-client-swift 维护频率较低，需验证与 Socket.IO v4.8 的兼容性。备选方案：使用原生 URLSessionWebSocketTask 自行实现 Engine.IO/Socket.IO 协议。

---

# 四、HTTP REST API

## 4.1 基础信息

```
默认服务端: https://api.cluster-fluster.com
认证方式: Authorization: Bearer <token>（除 /v1/auth 外所有端点）
数据格式: JSON
```

## 4.2 认证端点

```
POST /v1/auth
  Body: { publicKey: base64, challenge: base64, signature: base64 }
  Response: { success: true, token: string }

POST /v1/auth/account/request
  Body: { publicKey: base64 }
  Response: { state: "requested" | "authorized", token?: string, response?: base64 }

GET /v1/auth/request/status
  Query: { publicKey: base64 }
  Response: { status: "not_found" | "pending" | "authorized", supportsV2: boolean }

POST /v1/auth/account/response（需认证）
  Body: { response: base64, publicKey: base64 }
```

## 4.3 会话端点

```
GET /v1/sessions
  Response: { sessions: SessionData[] }  // 最近 150 个

GET /v2/sessions
  Query: { cursor?, limit: 1-200 (default 50), changedSince? }
  Response: 游标分页

GET /v2/sessions/active
  Query: { limit: 1-500 (default 150) }
  Response: 最近 15 分钟活跃的会话

POST /v1/sessions
  Body: { tag: string, metadata: base64, agentState?: base64, dataEncryptionKey?: base64 }
  Response: 创建或按 tag 加载已有会话

POST /v1/sessions/:id/delete
  Response: 标记会话为不活跃
```

## 4.4 消息端点（V3）

```
GET /v3/sessions/:sessionId/messages
  Query: { after_seq: number, limit: 1-500 (default 100) }
  Response: { messages: SessionMessage[], hasMore: boolean }

POST /v3/sessions/:sessionId/messages
  Body: { messages: [{ content: string(base64 encrypted), localId: string }] }
  Response: 创建的消息（带服务端分配的 seq）
```

SessionMessage 结构：
```json
{
  "id": "cuid",
  "seq": 42,
  "localId": "client_generated_id",
  "content": { "t": "encrypted", "c": "<base64>" },
  "createdAt": 1739347200000,
  "updatedAt": 1739347200000
}
```

## 4.5 机器端点

```
POST /v1/machines
  Body: { id: string, metadata: base64, daemonState?: base64, dataEncryptionKey?: base64 }

GET /v1/machines
  Response: 按 lastActiveAt 降序排列

GET /v1/machines/:id
```

## 4.6 Artifact 端点

```
GET /v1/artifacts
  Response: 列表（不含 body）

GET /v1/artifacts/:id
  Response: 完整 artifact（含 body）

POST /v1/artifacts
  Body: { id: UUID, header: base64, body: base64, dataEncryptionKey: base64 }

PATCH /v1/artifacts/:id
  Body: { header?: base64, body?: base64 }

DELETE /v1/artifacts/:id (通过 Socket.IO artifact-delete)
```

## 4.7 KV 存储端点

```
GET /v1/kv/:key
  Response: { key, value: base64, version } | null

GET /v1/kv?prefix=xxx&limit=100
  Response: { items: [{ key, value, version }] }

POST /v1/kv/bulk
  Body: { keys: string[] }
  Response: { values: [{ key, value, version }] }

POST /v1/kv（原子批量写入）
  Body: {
    mutations: [{
      key: string,
      value: base64 | null,     // null 表示删除
      version: number           // -1 表示新建，否则为当前版本号
    }]
  }
  Response: { success: true, results: [...] } | { success: false, errors: [...] }
  版本冲突返回 409
```

## 4.8 其他端点

```
POST /v1/push/token
  Body: { token: string }         // 注册推送 token

POST /v1/voice/sessions/:id/token
  Response: LiveKit token

POST /v1/account                  // 更新账户信息
POST /v1/account/profile          // 获取 profile
POST /v1/account/settings         // 更新设置
GET /v1/users/:userId/profile     // 获取其他用户 profile

POST /v1/friends/add
POST /v1/friends/remove
GET /v1/friends
GET /v1/relationships

GET /v1/feed
  Query: { before?, after?, limit: 1-200 (default 50) }

POST /v1/connect/:service/register  // 注册第三方服务 token
DELETE /v1/connect/:service
```

---

# 五、消息协议（Session Protocol）

## 5.1 消息信封（SessionEnvelope）

源码：`happy-wire/src/sessionProtocol.ts`

```json
{
  "id": "cuid2_string",
  "time": 1739347200000,
  "role": "user" | "agent",
  "turn": "cuid2_string",         // 可选，agent 消息必填
  "subagent": "cuid2_string",     // 可选，子 agent 标识
  "ev": { "t": "event_type", ... }
}
```

## 5.2 九种事件类型

### text — 文本消息
```json
{ "t": "text", "text": "markdown content", "thinking": true }
```
- `thinking` 可选，true 表示 Agent 思考过程

### service — 服务消息（仅 agent）
```json
{ "t": "service", "text": "service message" }
```

### tool-call-start — 工具调用开始
```json
{
  "t": "tool-call-start",
  "call": "unique_call_id",
  "name": "tool_name",
  "title": "Human Readable Title",
  "description": "What this tool does",
  "args": { "key": "value" }
}
```

### tool-call-end — 工具调用结束
```json
{ "t": "tool-call-end", "call": "unique_call_id" }
```
- `call` 与 `tool-call-start` 的 `call` 匹配

### file — 文件附件
```json
{
  "t": "file",
  "ref": "file_reference",
  "name": "filename.png",
  "size": 12345,
  "image": { "width": 800, "height": 600, "thumbhash": "base64_thumbhash" }
}
```
- `image` 可选，仅图片文件

### turn-start — Agent 开始处理
```json
{ "t": "turn-start" }
```

### turn-end — Agent 结束处理
```json
{ "t": "turn-end", "status": "completed" | "failed" | "cancelled" }
```

### start — 子 Agent 启动（仅 agent）
```json
{ "t": "start", "title": "Sub-agent task description" }
```

### stop — 子 Agent 停止（仅 agent）
```json
{ "t": "stop" }
```

## 5.3 Legacy 消息格式

源码：`happy-wire/src/legacyProtocol.ts`

旧版消息格式仍需支持解析：

```json
// 用户消息
{
  "role": "user",
  "content": { "type": "text", "text": "user input" },
  "localKey": "optional_key",
  "meta": { ... }
}

// Agent 消息
{
  "role": "agent",
  "content": { "type": "...", ... },
  "meta": { ... }
}
```

## 5.4 消息元数据（MessageMeta）

源码：`happy-wire/src/messageMeta.ts`

```json
{
  "sentFrom": "device_identifier",
  "permissionMode": "default" | "acceptEdits" | "bypassPermissions" | "plan" | "read-only" | "safe-yolo" | "yolo",
  "model": "claude-sonnet-4-20250514",
  "fallbackModel": null,
  "customSystemPrompt": null,
  "appendSystemPrompt": null,
  "allowedTools": ["tool1", "tool2"],
  "disallowedTools": null,
  "displayText": "显示文本"
}
```

## 5.5 消息内容判断逻辑

解密后的消息内容是 `MessageContent` 联合类型，由 `role` 字段区分：

```
if role === "session":   → SessionProtocolMessage（现代格式，含 SessionEnvelope）
if role === "user":      → UserMessage（Legacy 格式）
if role === "agent":     → AgentMessage（Legacy 格式）
```

---

# 六、数据模型（服务端 Prisma Schema）

源码：`happy-server/prisma/schema.prisma`

## 6.1 Account（用户）

```
id: string (CUID)
publicKey: string (唯一，hex 编码)
seq: number (全局单调递增序列号)
feedSeq: BigInt
settings: string? (加密，版本化)
settingsVersion: number
githubUserId: string? (关联 GitHub)
firstName, lastName, username: string?
avatar: JSON? (ImageRef)
```

## 6.2 Session（会话）

```
id: string (CUID)
tag: string (会话标识，同一用户唯一)
accountId: string
metadata: string (加密的会话元数据)
metadataVersion: number
agentState: string? (加密的 agent 状态)
agentStateVersion: number
dataEncryptionKey: bytes? (会话专属加密密钥，加密存储)
seq: number (会话级序列号)
active: boolean
lastActiveAt: DateTime
@@unique([accountId, tag])
```

## 6.3 SessionMessage（消息）

```
id: string (CUID)
sessionId: string
localId: string? (客户端去重 ID)
seq: number (会话内消息序号)
content: JSON → { t: "encrypted", c: "<base64>" }
@@unique([sessionId, localId])
@@index([sessionId, seq])
```

## 6.4 Machine（机器）

```
id: string (机器 UUID，客户端生成)
accountId: string
metadata: string (加密的机器静态信息)
metadataVersion: number
daemonState: string? (加密的守护进程运行状态)
daemonStateVersion: number
dataEncryptionKey: bytes?
seq: number
active: boolean
lastActiveAt: DateTime
@@unique([accountId, id])
```

## 6.5 Artifact

```
id: string (UUID，客户端生成)
accountId: string
header: bytes (加密)
headerVersion: number
body: bytes (加密)
bodyVersion: number
dataEncryptionKey: bytes (加密密钥)
seq: number
```

## 6.6 UserKVStore

```
accountId: string
key: string (明文，用于索引)
value: bytes? (加密，null 表示已删除)
version: number
@@unique([accountId, key])
```

## 6.7 AccessKey

```
accountId, machineId, sessionId: 三者联合唯一
data: string (加密)
dataVersion: number
```

## 6.8 UserRelationship（社交关系）

```
fromUserId, toUserId: 联合主键
status: none | requested | pending | friend | rejected
```

## 6.9 UserFeedItem（动态）

```
userId: string
counter: BigInt (排序用)
repeatKey: string? (去重用)
body: JSON (FeedBody)
```

---

# 七、并发控制

## 7.1 用户级全局序列号

- `Account.seq` 是全局单调递增计数器
- 每个 `update` 事件携带 `seq` 值
- 客户端按 `seq` 顺序应用更新，保证一致性

## 7.2 对象级版本号

每个可变字段都有独立版本号：
- Session: `metadataVersion`, `agentStateVersion`
- Machine: `metadataVersion`, `daemonStateVersion`
- Artifact: `headerVersion`, `bodyVersion`
- KV: `version`

## 7.3 乐观并发更新

```
客户端发送更新时携带 expectedVersion:
  socket.emitWithAck('update-metadata', {
    sid, metadata, expectedVersion: 3
  })

服务端检查:
  if 当前版本 !== expectedVersion:
    return { result: "version-mismatch", version: 当前版本, metadata: 当前值 }
  else:
    更新成功，版本号 +1
    return { result: "success", version: 4 }

客户端处理冲突:
  读取返回的当前值 → 合并 → 用新的 expectedVersion 重试
```

---

# 八、Base64 编码

源码：`happy-app/sources/encryption/base64.ts`

Happy 使用两种 Base64 变体：

```
标准 Base64 (variant = 'base64'):
  标准字符集 A-Z a-z 0-9 + /，= 填充

Base64URL (variant = 'base64url'):
  URL 安全字符集 A-Z a-z 0-9 - _，无填充

互转:
  base64url → base64: 替换 - → +, _ → /，补齐 = 填充
  base64 → base64url: 替换 + → -, / → _，去除 = 填充
```

masterSecret 存储使用 base64url。加密内容传输使用标准 base64。

---

# 九、Swift 技术方案总结

## 9.1 必要的第三方依赖

| 库 | 用途 | 替代方案 |
|---|------|---------|
| [swift-sodium](https://github.com/jedisct1/swift-sodium) | XSalsa20-Poly1305, NaCl Box, Ed25519 seed keypair | 直接桥接 libsodium C 库 |
| [socket.io-client-swift](https://github.com/socketio/socket.io-client-swift) | Socket.IO v4 实时通信 | 自实现 Engine.IO/Socket.IO 协议（成本高） |

## 9.2 Apple 原生框架覆盖

| 需求 | Apple 框架 |
|------|-----------|
| AES-256-GCM | CryptoKit `AES.GCM` |
| HMAC-SHA512 | CryptoKit `HMAC<SHA512>` |
| SHA-512 | CryptoKit `SHA512` |
| HTTP REST | URLSession |
| QR 码扫描 | AVFoundation `AVCaptureMetadataOutput` |
| 密钥存储 | Keychain Services |
| 数据持久化 | SwiftData |
| 推送通知 | UserNotifications + APNs |
| Markdown 渲染 | AttributedString 或第三方库 |

## 9.3 风险评估

| 风险 | 级别 | 缓解措施 |
|------|------|---------|
| socket.io-client-swift 维护状态 | 中 | 验证 v4.8 兼容性；备选自实现 |
| swift-sodium 编译复杂度 | 低 | SPM 支持良好，CI 可通过 |
| 流式 Markdown 渲染性能 | 低 | 增量渲染 + 缓存 |
| Base64 编解码一致性 | 低 | 单元测试覆盖边界情况 |
| Legacy 消息格式兼容 | 低 | 解析时判断 role 字段路由 |

## 9.4 结论

所有 Happy Coder 服务端功能均可在 Swift/iOS 上实现：
- 加密：CryptoKit + swift-sodium 覆盖全部算法
- 通信：socket.io-client-swift 支持全部 Socket.IO v4 功能
- 认证：AVFoundation QR + libsodium Ed25519/X25519
- 数据：SwiftData 可映射全部服务端模型
- 无技术阻断点

---

# 参考文件索引

| 文件 | 用途 |
|------|------|
| `happy-wire/src/sessionProtocol.ts` | 消息信封和 9 种事件类型定义 |
| `happy-wire/src/messages.ts` | API 消息类型、更新事件类型 |
| `happy-wire/src/legacyProtocol.ts` | Legacy 消息格式 |
| `happy-wire/src/messageMeta.ts` | 消息元数据字段 |
| `happy-app/sources/encryption/libsodium.ts` | NaCl 加解密实现（SecretBox, Box） |
| `happy-app/sources/encryption/deriveKey.ts` | 密钥派生树（HMAC-SHA512） |
| `happy-app/sources/encryption/aes.ts` | AES-256-GCM 加解密 |
| `happy-app/sources/encryption/base64.ts` | Base64/Base64URL 编解码 |
| `happy-app/sources/sync/encryption/encryptor.ts` | 三种 Encryptor 实现 |
| `happy-app/sources/sync/encryption/encryption.ts` | 加密管理器（密钥层级、DEK 包装） |
| `happy-app/sources/auth/authQRStart.ts` | QR 认证发起 |
| `happy-app/sources/auth/authQRWait.ts` | QR 认证轮询等待 |
| `happy-app/sources/auth/authChallenge.ts` | Ed25519 challenge-response |
| `happy-app/sources/auth/tokenStorage.ts` | 凭证存储 |
| `happy-app/sources/auth/secretKeyBackup.ts` | 密钥备份格式 |
| `happy-server/prisma/schema.prisma` | 数据库 Schema |
| `happy-server/sources/app/api/socket.ts` | Socket.IO 服务端配置 |
| `happy-server/sources/app/api/routes/authRoutes.ts` | 认证路由 |
| `happy-server/sources/app/api/routes/sessionRoutes.ts` | 会话路由 |
| `happy-server/sources/app/api/routes/v3SessionRoutes.ts` | V3 消息路由 |
| `happy-server/sources/app/api/routes/machinesRoutes.ts` | 机器路由 |
| `happy-server/sources/app/api/routes/artifactsRoutes.ts` | Artifact 路由 |
| `happy-server/sources/app/api/routes/kvRoutes.ts` | KV 存储路由 |
