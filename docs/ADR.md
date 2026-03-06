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

Talon 需要管理 Eagle 资源库的元数据索引，数据规模从数百到数万条素材记录，需要支持：

- 高效的多维查询（标签、评分、颜色、时间、文件类型等组合筛选）
- 1 万+ 素材的毫秒级搜索响应
- 离线可用（所有元数据本地持久化）
- 增量同步（检测 Eagle 桌面端的文件系统变更）

方案对比：

| 维度 | SwiftData | Core Data | SQLite (GRDB/FMDB) |
|------|-----------|-----------|---------------------|
| SwiftUI 集成 | 原生 @Query、@Model，零胶水代码 | 需要 @FetchRequest + NSManagedObject 包装 | 需手动桥接 ObservableObject |
| 学习成本 | 低，纯 Swift 声明式 | 中，需理解 NSManagedObjectContext 栈 | 中，需写原生 SQL |
| 大数据量性能 | iOS 18+ 底层仍为 SQLite，性能可控 | 成熟，性能已验证 | 最优，完全可控 |
| 复杂查询 | #Predicate 支持组合谓词，iOS 18 改进显著 | NSPredicate + NSCompoundPredicate，灵活但冗长 | 原生 SQL，最灵活 |
| 批量操作 | iOS 18+ `@Query` 支持 `fetchLimit`/`fetchOffset`，批量插入需手动分批 | `NSBatchInsertRequest` 原生批量操作 | 原生 SQL 事务批量 |
| iCloud 同步 | 内建 CloudKit 同步（本项目不需要） | 内建 CloudKit 同步 | 不支持 |
| 迁移 | 轻量迁移自动处理，复杂迁移有限 | 完善的版本化迁移 | 手动 ALTER TABLE |
| 最低版本 | iOS 17+（项目要求 iOS 18+，满足） | iOS 3+ | 无限制 |
| 调试工具 | Xcode Instruments SwiftData template | Core Data Instruments + SQLite 直查 | SQLite 直查 |

### 当前项目选择

SwiftData，理由：

1. 项目最低版本 iOS 18+，SwiftData 在 iOS 18 已修复了 iOS 17 的主要 bug 和性能问题
2. 纯 Swift 声明式 API 与 MVVM + SwiftUI 架构天然匹配，减少样板代码
3. @Query 的自动 UI 刷新避免手动 Combine/通知管道
4. Eagle 资源库是只读解析 → 本地索引的场景，不涉及复杂的多上下文写冲突
5. 性能瓶颈可通过下方「大数据量性能策略」解决，不需要降级到 Core Data

### 实施详情

→ Issue「[ADR] 数据持久化方案」

### 备注

如果未来遇到 SwiftData 无法解决的性能问题（如 10 万+ 素材），可评估引入 GRDB 作为 AI 向量索引的补充存储，SwiftData 仍负责主数据模型。

---

## 大数据量性能策略

### 说明

Eagle 用户资源库规模差异极大：轻度用户数百张，重度用户数万张甚至 10 万+。SwiftData 底层为 SQLite，性能上限取决于索引设计、查询模式和内存管理。需要从架构层面确保在大数据量下保持流畅体验。

核心挑战：

| 场景 | 数据量 | 性能要求 |
|------|--------|---------|
| 首次索引 | 1000-50000 个 metadata.json | < 10s（1000 张）、< 60s（10000 张） |
| 搜索/筛选 | 10000+ 条记录多维查询 | < 500ms |
| 瀑布流滚动 | 10000+ 缩略图 | ≥ 55fps |
| AI 向量搜索 | 10000+ × 512 维 float32 | < 1s |

### 当前项目选择

分五个层面系统解决：

#### 1. SwiftData 模型设计原则

```
核心原则：宽表 + 反范式 + 预计算
```

- 素材主表（Asset）采用宽表设计，将高频查询字段平铺为直接属性，避免关联查询
- 标签采用预序列化字符串存储（`tagsJoined: String`，逗号分隔），搜索时使用 `CONTAINS` 谓词，避免多对多关联表的 JOIN 开销
- 颜色调色板同理，将主色调 HEX 值序列化为字符串字段
- 文件夹归属使用 `folderIDs: String`（逗号分隔 ID），配合 `@Relationship` 的文件夹树形结构

```swift
// 模型设计示意
@Model
final class Asset {
    // --- 主键 & 索引 ---
    #Unique<Asset>([\.eagleID])
    #Index<Asset>([\.eagleID], [\.importedAt], [\.rating], [\.fileExtension])

    @Attribute(.unique) var eagleID: String        // Eagle 13位随机ID

    // --- 核心元数据（直接属性，避免关联查询）---
    var name: String
    var fileExtension: String                       // "jpg", "png", "psd"
    var fileSize: Int64                             // 字节
    var width: Int
    var height: Int
    var rating: Int                                 // 0-5 星
    var sourceURL: String?
    var annotation: String?                         // 备注

    // --- 时间戳 ---
    var createdAt: Date
    var modifiedAt: Date
    var importedAt: Date

    // --- 反范式字段（搜索性能优化）---
    var tagsJoined: String                          // "UI,登录页,渐变" 逗号分隔
    var folderIDsJoined: String                     // "FOLDER1,FOLDER2" 逗号分隔
    var primaryColorHex: String?                    // 主色调 HEX，用于颜色筛选
    var palettesJSON: String?                       // 完整调色板 JSON 字符串

    // --- 文件路径（相对于 .library 根目录）---
    var relativePath: String                        // "images/XXXXX.info/image.jpg"
    var thumbnailRelativePath: String               // "images/XXXXX.info/_thumbnail.png"

    // --- AI 相关（P1 阶段填充）---
    var clipVectorData: Data?                       // 512维 float32 向量，序列化为 Data
    var ocrText: String?                            // OCR 识别文本
    var aiTagsJoined: String?                       // AI 生成的标签

    // --- 缓存状态 ---
    var thumbnailCached: Bool = false
    var originalCached: Bool = false
    var lastAccessedAt: Date?

    // --- 关联（仅文件夹树形结构需要）---
    @Relationship var folders: [Folder]
}
```

#### 2. 索引策略

```
核心原则：为每个高频查询路径建立对应索引
```

| 查询场景 | 索引字段 | 说明 |
|----------|---------|------|
| 按时间浏览 | `importedAt` | 默认排序，最新优先 |
| 按评分筛选 | `rating` | 星级过滤 |
| 按文件类型 | `fileExtension` | 类型筛选 |
| 关键字搜索 | `name`, `tagsJoined`, `annotation`, `ocrText` | 文本搜索 |
| 按颜色搜索 | `primaryColorHex` | 颜色筛选前缀匹配 |
| 缓存淘汰 | `lastAccessedAt` | LRU 清理 |

SwiftData 的 `#Index` 宏在 iOS 18+ 可声明复合索引。对于文本搜索，如果 `CONTAINS` 性能不足，可回退到 SQLite FTS5 全文索引（通过 `ModelConfiguration` 的底层 SQLite 连接访问）。

#### 3. 批量导入策略

```
核心原则：分批提交 + 后台上下文 + 进度反馈
```

首次打开 Eagle 资源库时需要解析大量 `metadata.json` 文件。策略：

- 使用独立的后台 `ModelContext`（非 `@MainActor`），避免阻塞 UI
- 分批插入：每 200 条 `insert` 后执行一次 `save()`，平衡内存和 I/O
- 解析和插入流水线：用 `TaskGroup` 并行解析 JSON，串行写入 SwiftData
- 进度回调：通过 `AsyncStream<ImportProgress>` 向 UI 报告进度
- 增量更新：记录上次扫描时间戳，后续只处理 `modifiedAt` 更晚的文件

```
首次导入流程：
┌─────────────┐    ┌──────────────┐    ┌──────────────┐
│ 扫描文件系统  │ →  │ 并行解析 JSON │ →  │ 分批写入       │
│ 收集路径列表  │    │ TaskGroup     │    │ SwiftData     │
│              │    │ (8 并发)      │    │ (200条/批)    │
└─────────────┘    └──────────────┘    └──────────────┘
                                              ↓
                                       ┌──────────────┐
                                       │ 构建搜索索引   │
                                       │ 通知 UI 刷新   │
                                       └──────────────┘
```

#### 4. 查询性能优化

```
核心原则：分页加载 + 预测查询 + 避免全量 fetch
```

- 分页查询：`@Query` 配合 `fetchLimit` + `fetchOffset`，每页加载 50-100 条
- 瀑布流/网格使用 `LazyVGrid` / `LazyVStack`，仅渲染可见区域的 View
- 搜索防抖：输入停顿 300ms 后才触发查询，避免每次击键都查库
- 筛选谓词缓存：多维筛选条件组合为 `#Predicate`，条件未变时复用上次查询结果
- 计数查询：筛选器角标数量使用 `fetchCount` 而非 `fetch + count`，避免实例化对象

#### 5. 内存管理

```
核心原则：控制活跃对象数量，及时释放不可见数据
```

- `ModelContext.autosaveEnabled = false`：手动控制保存时机，避免频繁磁盘 I/O
- 滚动时仅持有当前可见区域 ± 预加载缓冲区的 Asset 对象引用
- 缩略图使用独立的 `NSCache` 内存缓存（非 SwiftData），设置 `countLimit` 和 `totalCostLimit`
- 大文件预览（原图、PDF、视频）使用临时 `ModelContext` 加载，预览关闭后释放
- CLIP 向量数据（`clipVectorData`）标记为惰性加载，仅在 AI 搜索时批量读取

### 实施详情

→ Issue「[ADR] 大数据量性能策略」

### 备注

性能基准测试矩阵（需在真机上验证）：

| 素材数量 | 首次索引 | 搜索响应 | 滚动帧率 | 内存峰值 |
|---------|---------|---------|---------|---------|
| 1,000   | < 10s   | < 100ms | 60fps   | < 100MB |
| 5,000   | < 30s   | < 200ms | 60fps   | < 150MB |
| 10,000  | < 60s   | < 500ms | ≥ 55fps | < 200MB |
| 50,000  | < 5min  | < 1s    | ≥ 55fps | < 300MB |

如果 50,000 素材场景下 SwiftData 查询性能不达标，可考虑：
- 对文本搜索引入 SQLite FTS5 全文索引
- 对 CLIP 向量搜索引入独立的 FAISS/USearch 索引文件
- 将 `#Predicate` 替换为原生 `NSPredicate` 获取更底层优化空间

---

## SwiftData 模型层架构

### 说明

定义 SwiftData 模型的组织结构、模型间关系、以及与 Eagle 文件系统数据的映射关系。

核心模型：

```
┌─────────────────────────────────────────────────────┐
│                    SwiftData 模型层                    │
│                                                       │
│  ┌──────────┐     ┌──────────┐     ┌──────────────┐  │
│  │  Library  │ 1:N │  Folder  │ N:M │    Asset     │  │
│  │ (资源库)  │────→│ (文件夹) │←───→│   (素材)     │  │
│  └──────────┘     └──────────┘     └──────────────┘  │
│       │                │ 1:N             │            │
│       │                ↓                 │            │
│       │           ┌──────────┐           │            │
│       │           │  Folder  │           │            │
│       │           │ (子文件夹)│           │            │
│       │           └──────────┘           │            │
│       │                                  │            │
│       │           ┌──────────┐           │            │
│       └──────────→│   Tag    │←──────────┘            │
│             1:N   │  (标签)  │  引用（非关联）         │
│                   └──────────┘                        │
│                                                       │
│                   ┌──────────────┐                    │
│                   │  Annotation  │                    │
│                   │   (标注)     │                    │
│                   └──────────────┘                    │
│                        N:1 ↑                          │
│                        Asset                          │
└─────────────────────────────────────────────────────┘
```

模型说明：

| 模型 | 对应 Eagle 数据 | 关系 | 说明 |
|------|----------------|------|------|
| Library | `.library` 根目录 | 1:N Folder, 1:N Tag | 资源库元信息（名称、路径、最后扫描时间） |
| Folder | 文件夹层级 | 自引用 1:N（父子）、N:M Asset | 支持多层级嵌套 |
| Asset | `images/XXX.info/metadata.json` | N:M Folder、1:N Annotation | 素材核心模型，宽表设计 |
| Tag | `tags.json` 全局标签 | 属于 Library | 全局标签定义（名称、颜色） |
| Annotation | Talon 独有 | N:1 Asset | 标注/批注数据，不写回 Eagle |

关键设计决策：

- Asset 与 Tag 不使用 `@Relationship`：标签通过 `tagsJoined` 字符串存储在 Asset 上，避免多对多关联表的查询开销。Tag 模型独立存在仅用于标签管理 UI（自动补全、标签列表）
- Asset 与 Folder 使用 `@Relationship`：文件夹树形结构需要关联查询（「展开文件夹显示所有素材」），且文件夹数量有限（通常 < 500），关联开销可接受
- Annotation 为 Talon 独有数据，不映射回 Eagle 文件系统

### 当前项目选择

采用上述模型结构。关键点：

1. Asset 宽表设计优先查询性能，接受一定的数据冗余
2. 标签字段反范式化（字符串而非关联表）
3. ModelContainer 配置单一 Store，所有模型共享同一 SQLite 文件
4. 每个 Library 对应独立的 SwiftData Store 文件（多库切换时切换 ModelContainer）

### 实施详情

→ Issue「[ADR] SwiftData 模型层架构」

### 备注

多 Library 隔离方案：每个 Eagle 资源库对应独立的 `.store` 文件，通过 `ModelConfiguration(url:)` 指定路径。切换资源库时销毁旧 `ModelContainer` 并创建新实例。这避免了单库内的 Library ID 过滤开销，也简化了「删除资源库」操作（直接删文件）。

---

## Eagle 资源库解析架构

### 说明

将 Eagle `.library` 文件系统结构转换为 SwiftData 模型的解析流程设计。

需要处理的数据源：

| 文件 | 内容 | 解析频率 |
|------|------|---------|
| `metadata.json`（根目录） | 资源库全局配置 | 仅首次 |
| `tags.json` | 全局标签定义 | 首次 + 变更检测 |
| `images/*/metadata.json` | 每个素材的元数据 | 首次全量 + 增量 |
| `images/*/_thumbnail.png` | Eagle 预生成缩略图 | 按需读取 |

解析流程：

```
Eagle .library 文件系统                    SwiftData
━━━━━━━━━━━━━━━━━━━━━━                    ━━━━━━━━━

  ┌──────────────┐      ┌───────────┐      ┌────────────┐
  │ metadata.json │ ──→  │ LibraryDTO│ ──→  │  Library   │
  │ (根目录)      │      │           │      │  @Model    │
  └──────────────┘      └───────────┘      └────────────┘

  ┌──────────────┐      ┌───────────┐      ┌────────────┐
  │  tags.json   │ ──→  │  TagDTO   │ ──→  │    Tag     │
  └──────────────┘      └───────────┘      │  @Model    │
                                           └────────────┘

  ┌──────────────┐      ┌───────────┐      ┌────────────┐
  │ images/*/    │ ──→  │ AssetDTO  │ ──→  │   Asset    │
  │ metadata.json│      │ (Codable) │      │  @Model    │
  └──────────────┘      └───────────┘      └────────────┘
       ↑
  并行解析 (TaskGroup)                      分批写入 (200条/批)
```

DTO 层的作用：

- `AssetDTO`：纯 `Codable` 结构体，1:1 映射 Eagle 的 metadata.json 字段
- 解析时先反序列化为 DTO，再转换为 SwiftData @Model
- DTO 与 @Model 分离，确保 Eagle 格式变更不影响数据库模型
- DTO 层处理字段类型转换（Eagle 时间戳为 Unix milliseconds → Date）

增量同步策略：

- 记录 `Library.lastScanDate` 为上次全量/增量扫描时间
- 增量扫描时，遍历 `images/` 目录，比较每个 `metadata.json` 的文件系统 `modificationDate` 与 `lastScanDate`
- 仅解析 `modificationDate > lastScanDate` 的文件
- 检测被删除的素材：对比 SwiftData 中的 eagleID 集合与文件系统中实际存在的目录集合

### 当前项目选择

三层架构：FileSystem → DTO → SwiftData Model

- `EagleLibraryScanner`：负责文件系统遍历和变更检测
- `EagleMetadataParser`：负责 JSON 解析为 DTO
- `LibraryIndexer`：负责 DTO 到 SwiftData Model 的转换和批量写入

### 实施详情

→ Issue「[ADR] Eagle 资源库解析架构」

### 备注

Eagle metadata.json 的字段名和类型可能在 Eagle 版本迭代中变化。DTO 层使用 `CodingKeys` + 可选字段处理向前兼容。建议收集 Eagle 3.x / 4.x / 5.x 的 metadata.json 样本进行兼容性测试。

---

## 文件访问与安全沙盒

### 说明

iOS App 运行在沙盒中，访问外部文件（iCloud Drive、SMB）需要通过安全作用域书签（Security-Scoped Bookmarks）获取持久访问权限。

挑战：

| 场景 | 问题 | 解决方案 |
|------|------|---------|
| 首次打开 Eagle 库 | 需要用户授权访问 .library 目录 | UIDocumentPickerViewController |
| App 重启后 | 沙盒权限丢失，无法再次访问 | Security-Scoped Bookmark 持久化 |
| iCloud 文件 | 文件可能未下载到本地 | `startDownloadingUbiquitousItem` |
| SMB 网络共享 | 网络断开时不可访问 | 优雅降级到离线缓存 |
| Share Extension | 独立进程，无法访问主 App 沙盒 | App Group 共享容器 |

### 当前项目选择

```
访问流程：
┌──────────────┐     ┌─────────────────────┐     ┌──────────────┐
│ Document     │ ──→ │ Security-Scoped     │ ──→ │ 存储 Bookmark │
│ Picker       │     │ URL                 │     │ 到 UserDefaults│
│ (用户选择库)  │     │ startAccessingScope │     │ / Keychain    │
└──────────────┘     └─────────────────────┘     └──────────────┘
                                                        │
                      ┌─────────────────────┐           │
                      │ App 重启时            │ ←────────┘
                      │ resolveBookmarkData  │
                      │ startAccessingScope  │
                      └─────────────────────┘
```

关键实现点：

- 使用 `URL.bookmarkData(options: .withSecurityScope)` 创建书签
- 书签数据存储在 UserDefaults（或 Keychain），按资源库路径索引
- 每次访问前调用 `startAccessingSecurityScopedResource()`，用完调用 `stopAccessingSecurityScopedResource()`
- 封装为 `ScopedAccessManager`，提供 `withAccess(to url:) async throws -> T` 便捷方法
- Share Extension 通过 App Group 共享容器读写素材，主 App 启动时同步到 Eagle 库

### 实施详情

→ Issue「[ADR] 文件访问与安全沙盒」

### 备注

Security-Scoped Bookmark 在以下情况会失效：用户移动/重命名了 .library 目录、iCloud Drive 同步冲突。需要处理 `bookmarkDataIsStale` 标记，提示用户重新选择目录。

---

## 本地数据缓存方案

### 说明

Talon 的数据源是 Eagle 文件系统（非远端服务），因此缓存策略与常规 SaaS App 不同：

| 数据类型 | 来源 | 缓存方案 | 说明 |
|---------|------|---------|------|
| 素材元数据 | Eagle metadata.json → SwiftData | SwiftData 即缓存 | 解析后即持久化，SwiftData 本身就是离线缓存 |
| 缩略图 | Eagle `_thumbnail.png` | 磁盘缓存（Application Support） | 复制到 App 沙盒，避免反复访问安全作用域 |
| 原始文件 | Eagle 原始素材文件 | 按需磁盘缓存 + LRU 淘汰 | 用户查看过的原图缓存到本地 |
| CLIP 向量 | 本地 Core ML 计算 | SwiftData `clipVectorData` 字段 | 计算一次，永久存储 |
| OCR 文本 | 本地 Vision 计算 | SwiftData `ocrText` 字段 | 计算一次，永久存储 |
| 搜索历史 | 用户输入 | UserDefaults | 轻量键值存储 |

### 当前项目选择

分层缓存策略：

```
┌─────────────────────────────────────────────────┐
│ 内存层 (NSCache)                                 │
│ - 缩略图 UIImage：countLimit = 500               │
│ - 解码后的原图：countLimit = 10                   │
│ - 搜索结果缓存：基于查询谓词哈希                    │
│ 特点：自动内存管理，App 进后台自动释放               │
├─────────────────────────────────────────────────┤
│ 磁盘层 (Application Support)                     │
│ - 缩略图文件：首次打开库时全量复制，增量更新          │
│ - 原始文件缓存：按需下载，LRU 淘汰                  │
│ - 最大空间：用户可配（默认 2GB）                    │
│ - 排除 iCloud 备份：isExcludedFromBackup = true   │
├─────────────────────────────────────────────────┤
│ 数据库层 (SwiftData / SQLite)                    │
│ - 所有素材元数据（始终离线可用）                     │
│ - CLIP 向量、OCR 文本（计算结果持久化）              │
│ - 标注数据（Talon 独有数据）                       │
│ 特点：App 删除才会丢失                             │
└─────────────────────────────────────────────────┘
```

缩略图缓存策略：

- 首次打开资源库时，将所有 `_thumbnail.png` 复制到 `Application Support/Talon/Thumbnails/{eagleID}.png`
- 后续直接从 App 沙盒读取，不再访问安全作用域（性能更好）
- 增量更新：新增素材时复制新缩略图，删除素材时清理对应缓存

原始文件缓存策略：

- 用户点击查看原图时，将原始文件复制到 `Application Support/Talon/Originals/{eagleID}.{ext}`
- LRU 淘汰：使用 `lastAccessedAt` 字段跟踪访问时间，空间不足时清理最久未访问的文件
- 收藏素材（用户标记）的原始文件不参与 LRU 淘汰

### 实施详情

→ Issue「[ADR] 本地数据缓存方案」

### 备注

现有的 `CacheManager.swift`（JSON 文件缓存）适用于 Supabase 远端数据缓存场景。Talon 的主要数据源是本地文件系统，SwiftData 本身承担了缓存角色，因此 `CacheManager` 在当前架构中仅用于缓存 Supabase 的用户账户信息、订阅状态等少量远端数据。

---

## AI/ML 本地推理架构

### 说明

Talon 的 AI 功能全部在设备端运行，涉及多个 ML 模型和框架的协调：

| 功能 | 框架/模型 | 输入 | 输出 | 存储 |
|------|----------|------|------|------|
| 语义搜索 | MobileCLIP-S0 (Core ML) | 图片 / 文本 | 512 维向量 | SwiftData `clipVectorData` |
| 自动标签 | VNClassifyImageRequest | 图片 | 分类标签 + 置信度 | SwiftData `aiTagsJoined` |
| OCR | VNRecognizeTextRequest | 图片 | 识别文本 | SwiftData `ocrText` |
| 图片特征指纹 | VNGenerateImageFeaturePrintRequest | 图片 | 特征指纹 | SwiftData 独立字段 |
| 风格识别 (P3) | Create ML 自定义模型 | 图片 | 风格分类 | SwiftData 标签 |

### 当前项目选择

统一的 AI 处理管道：

```
┌────────────────────────────────────────────────────────┐
│                  AIProcessingPipeline                   │
│                                                         │
│  输入：[Asset]（待处理素材列表）                            │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │  CLIP    │  │  Vision  │  │   OCR    │  │ 风格   │ │
│  │ Encoder  │  │ Classify │  │  Engine  │  │ 分类器 │ │
│  │ (P1)     │  │ (P1)     │  │ (P1)     │  │ (P3)   │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └───┬────┘ │
│       ↓              ↓              ↓             ↓      │
│  clipVectorData  aiTagsJoined    ocrText     styleTags  │
│                                                         │
│  处理策略：                                               │
│  - 后台队列（QoS: .utility）                              │
│  - 并发度：max(2, ProcessInfo.activeProcessorCount - 2)  │
│  - 分批处理：每批 50 张                                    │
│  - 进度报告：AsyncStream<ProcessingProgress>              │
│  - 可中断：Task cancellation 支持                         │
│  - 电量感知：低电量模式暂停处理                              │
└────────────────────────────────────────────────────────┘
```

CLIP 向量搜索方案：

- 向量存储：512 维 × float32 = 2KB/张，1 万张 = 20MB，可全量加载到内存
- 搜索算法：暴力余弦相似度（1 万张级别，暴力搜索足够快，< 100ms）
- 如果规模达到 10 万+，引入 vDSP/Accelerate 框架的 SIMD 加速，或 USearch 近似最近邻索引
- 向量数据存储在 SwiftData 的 `clipVectorData: Data?` 字段，搜索时批量读取到内存中的 `[String: [Float]]` 字典

### 实施详情

→ Issue「[ADR] AI/ML 本地推理架构」

### 备注

MobileCLIP-S0 模型约 150MB，建议首次使用 AI 搜索时按需下载（而非内置在 App Bundle 中），避免增大安装包体积。可使用 Background Assets Framework 或手动从 App 的 CDN 下载。

---

## 缩略图渲染与滚动性能

### 说明

瀑布流/网格浏览是 Talon 最高频的交互场景。10000+ 缩略图的流畅滚动是用户体验的基础。

性能瓶颈分析：

| 瓶颈 | 原因 | 解决方案 |
|------|------|---------|
| 图片解码 | PNG/JPEG 解码在主线程阻塞 UI | 后台预解码 + 缓存解码后的 CGImage |
| 内存占用 | 大量 UIImage 同时驻留内存 | NSCache 限制 + 只缓存可见区域 |
| 视图创建 | SwiftUI View 频繁创建销毁 | LazyVGrid + 稳定 ID |
| 文件 I/O | 从磁盘读取缩略图阻塞 | 异步加载 + 占位图 |

### 当前项目选择

```
缩略图加载流水线：

  ┌───────────┐     ┌───────────┐     ┌───────────┐     ┌───────────┐
  │ SwiftUI   │ ──→ │ NSCache   │ ──→ │ 磁盘缓存   │ ──→ │ Eagle 源   │
  │ View 请求  │     │ 内存命中?  │     │ 文件命中?  │     │ 文件读取   │
  │ 缩略图     │     │  ↓ 是      │     │  ↓ 是      │     │ + 复制     │
  └───────────┘     │ 直接返回   │     │ 后台解码   │     │ + 后台解码 │
                    └───────────┘     │ 返回 + 缓存 │     │ 返回 + 缓存│
                                      └───────────┘     └───────────┘
```

具体策略：

1. ThumbnailLoader（Actor 隔离）
   - `actor ThumbnailLoader` 管理所有缩略图加载请求
   - 请求合并：同一 eagleID 的并发请求只执行一次 I/O
   - 优先级调度：可见区域的请求优先于预加载请求
   - 取消机制：View 离开可见区域时取消对应加载任务

2. 图片解码优化
   - 使用 `ImageIO` 的 `CGImageSourceCreateThumbnailAtIndex` 直接生成目标尺寸缩略图
   - 设置 `kCGImageSourceShouldCacheImmediately: true` 强制立即解码
   - 避免 UIImage 的惰性解码在主线程触发

3. SwiftUI 视图优化
   - `LazyVGrid` / `LazyVStack` 仅创建可见 View
   - 每个缩略图 View 使用 `.id(asset.eagleID)` 保持稳定标识
   - 避免在滚动路径上使用 `@Query`，改用 ViewModel 提供已 fetch 的数据

### 实施详情

→ Issue「[ADR] 缩略图渲染与滚动性能」

### 备注

SwiftUI 的 `AsyncImage` 不适合本场景（不支持自定义缓存策略、无法取消）。建议实现自定义的 `ThumbnailView`，内部使用 `.task` + `ThumbnailLoader` actor。

---

## 搜索架构

### 说明

Talon 的搜索体系分为三层，从基础到智能逐步构建：

| 层级 | 功能 | 技术方案 | 阶段 |
|------|------|---------|------|
| L1 关键字搜索 | 名称、标签、备注模糊匹配 | SwiftData `#Predicate` + `CONTAINS` | P0 |
| L2 多维筛选 | 文件类型、评分、颜色、时间、尺寸组合 | SwiftData 组合 `#Predicate` | P0 |
| L3 AI 语义搜索 | 自然语言描述搜图 | MobileCLIP 向量相似度 | P1 |
| L4 OCR 搜索 | 图片中的文字内容搜索 | Vision OCR → SwiftData 全文 | P1 |
| L5 颜色搜索 | 按颜色查找素材 | DeltaE 颜色差异算法 | P1 |

### 当前项目选择

统一搜索入口 + 可组合的搜索引擎：

```
┌──────────────────────────────────────────────────┐
│                  SearchCoordinator                │
│                                                    │
│  输入：SearchQuery                                  │
│  ┌────────────────────────────────────────────┐   │
│  │ keyword: String?         // 关键字          │   │
│  │ tags: [String]?          // 标签筛选        │   │
│  │ fileTypes: [String]?     // 文件类型         │   │
│  │ ratingRange: ClosedRange<Int>?              │   │
│  │ dateRange: ClosedRange<Date>?               │   │
│  │ colorHex: String?        // 颜色搜索        │   │
│  │ semanticQuery: String?   // AI 语义搜索      │   │
│  │ sortBy: SortField                           │   │
│  │ sortOrder: SortOrder                        │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐           │
│  │ SwiftData│  │  CLIP   │  │  Color  │           │
│  │ Predicate│  │ Vector  │  │ DeltaE  │           │
│  │ Engine   │  │ Engine  │  │ Engine  │           │
│  └────┬─────┘  └────┬────┘  └────┬────┘           │
│       ↓              ↓            ↓                 │
│  ┌─────────────────────────────────────────────┐   │
│  │        结果合并 & 排序 & 分页                  │   │
│  └─────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

SwiftData 查询优化：

- 将多维筛选条件编译为单个 `#Predicate`，一次查询完成
- 避免链式过滤（fetch 全量再内存过滤）
- 搜索关键字的 `CONTAINS` 查询走 SwiftData 索引
- 如果关键字搜索在 1 万+ 素材上性能不达标（> 500ms），回退方案：为 `name`、`tagsJoined`、`ocrText` 建立 SQLite FTS5 全文索引

颜色搜索：

- 从 Eagle palette 数据提取主色调 HEX
- 用户选择目标颜色后，计算 CIEDE2000 DeltaE 值
- 预计算所有素材主色调的 Lab 色彩空间坐标存入 SwiftData
- 搜索时加载全量 Lab 值（1 万条 × 3 个 Float = 120KB）做内存内比较

### 实施详情

→ Issue「[ADR] 搜索架构」

### 备注

搜索性能 SLA：

| 搜索类型 | 1000 张 | 5000 张 | 10000 张 |
|---------|---------|---------|----------|
| 关键字搜索 | < 50ms  | < 150ms | < 500ms  |
| 多维筛选   | < 50ms  | < 100ms | < 300ms  |
| AI 语义搜索 | < 200ms | < 500ms | < 1s     |
| 颜色搜索   | < 100ms | < 200ms | < 500ms  |

---

## 写回 Eagle 格式兼容

### 说明

Talon 不仅读取 Eagle 资源库，还需要写入（添加素材、编辑元数据），且写入的数据必须被 Eagle 桌面端正确识别。

写入场景：

| 操作 | 写入内容 | 文件影响 |
|------|---------|---------|
| 添加素材 | 新建 `images/XXX.info/` 目录 + metadata.json + 原始文件 + _thumbnail.png | 新增文件 |
| 编辑标签/评分/备注 | 更新对应 metadata.json 字段 | 修改文件 |
| 移动到文件夹 | 更新 metadata.json 的 folders 字段 | 修改文件 |
| 创建文件夹 | 更新根目录 metadata.json 的文件夹结构 | 修改文件 |
| 删除素材 | 删除整个 `images/XXX.info/` 目录 | 删除文件 |

### 当前项目选择

- 写入时完全遵循 Eagle 的 metadata.json 字段格式和命名规范
- 新建素材 ID 使用与 Eagle 相同的 13 位随机 ID 生成算法
- 缩略图生成使用与 Eagle 相同的规格（最大 512px 短边）
- 写入操作通过 `EagleLibraryWriter` 统一管理，确保原子性：先写临时文件，再 rename
- 写入完成后同步更新 SwiftData 索引
- 写入操作记录到本地操作日志（Write-Ahead Log），断电/崩溃后可恢复

### 实施详情

→ Issue「[ADR] 写回 Eagle 格式兼容」

### 备注

Eagle metadata.json 的完整字段规范需要通过逆向工程确认。建议创建一个 Eagle 测试资源库，通过桌面端执行各种操作后对比 metadata.json 的变化来确定字段格式。

---

## App 架构与模块划分

### 说明

定义 Talon App 的整体模块结构、依赖关系和代码组织方式。

### 当前项目选择

MVVM + 功能模块化：

```
Talon/
├── App/
│   ├── TalonApp.swift              # @main 入口
│   └── AppState.swift              # 全局状态（当前资源库、用户设置）
│
├── Models/                          # SwiftData @Model
│   ├── Asset.swift
│   ├── Folder.swift
│   ├── Tag.swift
│   ├── Library.swift
│   └── Annotation.swift
│
├── DTOs/                            # Eagle JSON 映射
│   ├── AssetDTO.swift
│   ├── TagDTO.swift
│   └── LibraryDTO.swift
│
├── Features/                        # 功能模块（每个模块独立 View + ViewModel）
│   ├── LibraryBrowser/              # F-001 资源库浏览
│   │   ├── LibraryBrowserView.swift
│   │   ├── LibraryBrowserViewModel.swift
│   │   └── Components/
│   ├── AssetGrid/                   # F-003 瀑布流/网格
│   │   ├── AssetGridView.swift
│   │   ├── WaterfallLayout.swift
│   │   └── ThumbnailView.swift
│   ├── Search/                      # F-004 搜索筛选
│   │   ├── SearchView.swift
│   │   ├── SearchViewModel.swift
│   │   ├── SearchCoordinator.swift
│   │   └── FilterSheet.swift
│   ├── Preview/                     # F-005 文件预览
│   │   ├── AssetPreviewView.swift
│   │   └── PreviewControllers/
│   ├── Annotation/                  # F-007 标注
│   │   ├── AnnotationView.swift
│   │   └── AnnotationToolbar.swift
│   ├── AI/                          # F-101~104 AI 功能
│   │   ├── AIProcessingPipeline.swift
│   │   ├── CLIPSearchEngine.swift
│   │   ├── AutoTagger.swift
│   │   └── OCREngine.swift
│   ├── Import/                      # F-105 素材添加
│   │   ├── ImportView.swift
│   │   └── ImportViewModel.swift
│   ├── DataCache/                   # 数据缓存
│   │   └── CacheManager.swift
│   └── Settings/                    # 设置
│       └── SettingsView.swift
│
├── Services/                        # 基础服务层
│   ├── EagleLibraryScanner.swift    # 文件系统扫描
│   ├── EagleMetadataParser.swift    # metadata.json 解析
│   ├── EagleLibraryWriter.swift     # 写回 Eagle 格式
│   ├── LibraryIndexer.swift         # SwiftData 索引构建
│   ├── ThumbnailLoader.swift        # 缩略图加载 Actor
│   ├── ScopedAccessManager.swift    # 安全作用域书签
│   └── SubscriptionManager.swift    # RevenueCat 订阅管理
│
├── Brand/                           # BrandKit 定制
│   ├── Color+Brand.swift
│   ├── Font+Brand.swift
│   └── Spacing+Brand.swift
│
└── Extensions/                      # 通用扩展
    ├── Date+Eagle.swift             # Eagle 时间戳转换
    ├── Color+DeltaE.swift           # 颜色差异计算
    └── Data+CLIP.swift              # 向量序列化
```

依赖方向（单向依赖，禁止循环）：

```
View → ViewModel → Service → Model/DTO
                      ↓
                  SwiftData / FileSystem
```

- View 只依赖 ViewModel，不直接访问 Service 或 Model
- ViewModel 通过 Service 层操作数据
- Service 层负责所有 I/O（文件系统、SwiftData、Core ML）
- Model 层纯数据定义，无业务逻辑

### 实施详情

→ Issue「[ADR] App 架构与模块划分」

### 备注

第三方 Package 依赖已在 `TalonApp.swift` 中全局导出：LayoutUIKit、BrandKit、SupabaseKit、RevenueCatKit、PromoKit。Feature 模块无需重复 import。

---

## 并发模型

### 说明

Talon 涉及大量异步操作：文件系统扫描、JSON 解析、图片解码、AI 推理、SwiftData 读写。需要明确的并发策略避免数据竞争和主线程阻塞。

### 当前项目选择

Swift Concurrency（async/await + Actor）为主：

| 组件 | 隔离策略 | 说明 |
|------|---------|------|
| View | @MainActor | SwiftUI 要求 |
| ViewModel | @MainActor | 驱动 UI 更新 |
| ThumbnailLoader | actor | 请求合并、缓存管理 |
| LibraryIndexer | 非隔离，后台 Task | 分批写入，不阻塞 UI |
| AIProcessingPipeline | 非隔离，TaskGroup | 并发 ML 推理 |
| EagleLibraryScanner | 非隔离，async | 文件系统遍历 |
| SwiftData ModelContext | 每线程独立 | 主 Context (@MainActor) + 后台 Context |

SwiftData 并发规则：

- 主线程使用 `modelContainer.mainContext` 用于 UI 绑定的查询
- 后台操作使用 `ModelContext(modelContainer)` 创建独立上下文
- 后台上下文写入后，主上下文通过 SwiftData 的自动合并机制同步
- 禁止跨线程传递 `@Model` 对象，使用 `PersistentIdentifier` 传递后重新 fetch

### 实施详情

→ Issue「[ADR] 并发模型」

### 备注

Swift 6 严格并发检查（`SWIFT_STRICT_CONCURRENCY=complete`）建议从项目初始就启用，避免后期迁移成本。
