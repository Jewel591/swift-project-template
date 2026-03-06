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
- 全文搜索（名称、标签、备注、OCR 文本）
- 离线可用（所有元数据本地持久化）
- 批量导入（首次打开资源库需导入数千至数万条记录）
- 增量同步（检测 Eagle 桌面端的文件系统变更）

方案对比：

| 维度 | SwiftData | Core Data | GRDB (SQLite) |
|------|-----------|-----------|---------------|
| 文本搜索 | `CONTAINS` → `LIKE '%x%'` 全表扫描，无 FTS | NSPredicate 同理，无原生 FTS | 原生 SQLite FTS5 全文索引 |
| 查询可控性 | `#Predicate` 生成的 SQL 不透明、不可调优 | `NSPredicate` 略好但同样不透明 | 手写 SQL，EXPLAIN QUERY PLAN 可调优 |
| 批量插入 | 无 `NSBatchInsertRequest`，每条记录实例化 @Model 对象 | `NSBatchInsertRequest` 绕过上下文直接写 SQLite | `INSERT OR REPLACE` 事务批量，零对象开销 |
| 变更通知 | @Query 任何 Model 变更触发全量重查询 | NSFetchedResultsController 精确到行级变更 | `DatabaseRegionObservation` 精确到表/行级变更 |
| 复合索引 | `#Index` 宏有限支持 | 支持但配置繁琐 | `CREATE INDEX` 完全自由组合 |
| 内存开销 | 每条记录创建 @Model 对象 + 变更追踪 | NSManagedObject + 变更追踪 | 纯 Swift 值类型 struct，零额外开销 |
| SwiftUI 集成 | 原生 @Query | @FetchRequest | `@Query` 通过 `GRDBQuery` SPM 包（声明式，类似 SwiftData） |
| 迁移 | 自动轻量迁移 | 版本化迁移 | `DatabaseMigrator` 编程式迁移，完全可控 |

SwiftData `@Query` 的具体性能问题：

```
问题 1: 全量重查询
─────────────────
用户修改了 1 条 Asset 的评分
→ SwiftData 通知 @Query 数据变更
→ @Query 重新执行完整查询（即使查询条件与评分无关）
→ 1 万条记录全量 fetch + 实例化 @Model 对象
→ UI 卡顿

问题 2: 文本搜索无索引
─────────────────────
搜索 "渐变" → #Predicate { $0.tagsJoined.contains("渐变") }
→ 编译为 SQL: WHERE tagsJoined LIKE '%渐变%'
→ 全表扫描 1 万行，逐行字符串匹配
→ 响应时间 > 1 秒

问题 3: 批量导入慢
─────────────────
导入 1 万条 Eagle 元数据
→ 每条记录创建 @Model 实例（内存分配 + 变更追踪注册）
→ 即使分批 save()，对象实例化开销无法避免
→ 导入时间 >> 原生 SQL INSERT

对比 GRDB 的处理方式:
→ FTS5 全文索引: 搜索 "渐变" < 5ms（倒排索引直接定位）
→ DatabaseRegionObservation: 仅在 asset 表相关行变更时通知
→ 批量导入: db.inTransaction { for row in rows { try row.insert(db) } }
  纯 SQL INSERT，零对象开销
```

### 当前项目选择

GRDB（直接操作 SQLite），理由：

1. Talon 的核心工作负载是「大数据量读密集型搜索」，不是典型的 CRUD App。SwiftData 为 CRUD + iCloud 同步优化，而 Talon 需要的是搜索引擎级的查询能力
2. FTS5 全文索引是文本搜索的必需品 — 名称、标签、备注、OCR 文本的模糊搜索在万级数据下，`LIKE '%keyword%'` 不可接受，FTS5 的倒排索引将响应时间从秒级降到毫秒级
3. 批量导入性能 — 首次打开 Eagle 库需导入数千至数万条记录，GRDB 的 SQL 事务批量插入比 SwiftData 逐条实例化 @Model 快一个数量级
4. 查询完全可控 — 可以 `EXPLAIN QUERY PLAN` 确认索引命中，SwiftData 的 `#Predicate` 生成的 SQL 是黑盒
5. 内存效率 — GRDB 的 `Record` 是纯 Swift struct，fetch 后无变更追踪开销；SwiftData 的 @Model 每个实例都注册变更观察
6. 精确变更通知 — `DatabaseRegionObservation` 可以精确到表/列级别触发 UI 刷新，不会像 @Query 那样任何 Model 变更都全量重查询
7. GRDB 提供 `GRDBQuery` SPM 包，在 SwiftUI 中使用 `@Query` 宏实现声明式查询，开发体验接近 SwiftData

代价和应对：

| 代价 | 应对 |
|------|------|
| 需要手写 SQL schema | 表结构在项目初期确定后很少变动，一次性成本 |
| 无自动 iCloud 同步 | Talon 不需要 iCloud 数据同步（数据源是 Eagle 文件系统） |
| SwiftUI 集成需要额外包 | `GRDBQuery` 提供 `@Query` 宏，体验接近 SwiftData |
| 需手动处理 schema 迁移 | `DatabaseMigrator` API 简洁可控，比 SwiftData 的自动迁移更可靠 |

### 实施详情

→ Issue「[ADR] 数据持久化方案」

### 备注

GRDB 是 iOS 生态最成熟的 SQLite 封装库，活跃维护超过 10 年，被 Firefox iOS、法国政府 App 等生产环境广泛使用。它不是对 SQLite 的简单封装，而是提供了类型安全的查询构建器、Codable 映射、并发安全的数据库访问、以及 SwiftUI 集成。

---

## 大数据量性能策略

### 说明

Eagle 用户资源库规模差异极大：轻度用户数百张，重度用户数万张甚至 10 万+。需要从数据库 schema 设计、索引策略、批量操作、查询模式、内存管理五个层面系统保证性能。

核心挑战：

| 场景 | 数据量 | 性能要求 |
|------|--------|---------|
| 首次索引 | 1000-50000 个 metadata.json | < 5s（1000 张）、< 30s（10000 张） |
| 关键字搜索 | 10000+ 条记录全文搜索 | < 50ms |
| 多维筛选 | 10000+ 条记录组合查询 | < 100ms |
| 瀑布流滚动 | 10000+ 缩略图 | ≥ 55fps |
| AI 向量搜索 | 10000+ × 512 维 float32 | < 1s |

### 当前项目选择

分五个层面系统解决：

#### 1. Schema 设计

```
核心原则：正规化关系 + FTS5 全文索引 + 预计算辅助列
```

GRDB 直接操作 SQLite，schema 完全可控。与之前 SwiftData 的「反范式 tagsJoined 字符串」方案不同，GRDB 下可以同时拥有正规化关系和高效搜索：

```sql
-- 素材主表
CREATE TABLE asset (
    id              TEXT PRIMARY KEY,   -- Eagle 13位随机ID
    name            TEXT NOT NULL,
    fileExtension   TEXT NOT NULL,
    fileSize        INTEGER NOT NULL,
    width           INTEGER NOT NULL,
    height          INTEGER NOT NULL,
    rating          INTEGER NOT NULL DEFAULT 0,
    sourceURL       TEXT,
    annotation      TEXT,
    createdAt       REAL NOT NULL,      -- Unix timestamp
    modifiedAt      REAL NOT NULL,
    importedAt      REAL NOT NULL,
    relativePath    TEXT NOT NULL,
    thumbnailPath   TEXT NOT NULL,
    primaryColorHex TEXT,
    palettesJSON    TEXT,
    -- AI 相关（P1 阶段填充）
    clipVector      BLOB,               -- 512维 float32 = 2KB
    ocrText         TEXT,
    aiTags          TEXT,
    -- 缓存状态
    thumbnailCached INTEGER NOT NULL DEFAULT 0,
    originalCached  INTEGER NOT NULL DEFAULT 0,
    lastAccessedAt  REAL
);

-- 标签关联表（正规化，支持精确匹配）
CREATE TABLE asset_tag (
    assetID TEXT NOT NULL REFERENCES asset(id) ON DELETE CASCADE,
    tag     TEXT NOT NULL,
    PRIMARY KEY (assetID, tag)
);

-- 文件夹归属（多对多）
CREATE TABLE asset_folder (
    assetID  TEXT NOT NULL REFERENCES asset(id) ON DELETE CASCADE,
    folderID TEXT NOT NULL REFERENCES folder(id) ON DELETE CASCADE,
    PRIMARY KEY (assetID, folderID)
);

-- 文件夹表（自引用树形结构）
CREATE TABLE folder (
    id       TEXT PRIMARY KEY,
    name     TEXT NOT NULL,
    parentID TEXT REFERENCES folder(id) ON DELETE CASCADE
);

-- 全局标签定义
CREATE TABLE tag (
    name  TEXT PRIMARY KEY,
    color TEXT
);

-- 标注（Talon 独有）
CREATE TABLE annotation (
    id        TEXT PRIMARY KEY,
    assetID   TEXT NOT NULL REFERENCES asset(id) ON DELETE CASCADE,
    data      BLOB NOT NULL,            -- 标注绘制数据
    createdAt REAL NOT NULL,
    updatedAt REAL NOT NULL
);

-- FTS5 全文索引（搜索核心）
CREATE VIRTUAL TABLE asset_fts USING fts5(
    name,
    tags,           -- 空格分隔的标签列表
    annotation,
    ocrText,
    content='',     -- 无内容表，手动同步
    contentless_delete=1
);
```

为什么标签使用关联表而非逗号分隔字符串：

| 操作 | 逗号字符串 `LIKE '%UI%'` | 关联表 `JOIN asset_tag` | FTS5 `MATCH 'UI'` |
|------|------------------------|------------------------|-------------------|
| 精确匹配标签 "UI" | 会误匹配 "UI设计"、"GUI" | 精确匹配 | 精确匹配（tokenize） |
| 标签组合 AND | 多个 LIKE 全表扫描 | JOIN + 索引 | `MATCH 'UI AND 登录'` |
| 查询速度（万级） | > 500ms | < 50ms（索引） | < 5ms（倒排索引） |

两者配合：关联表用于精确标签筛选和标签管理，FTS5 用于模糊关键字搜索。

#### 2. 索引策略

```
核心原则：每个查询路径都有对应索引，用 EXPLAIN QUERY PLAN 验证
```

```sql
-- 时间排序（默认浏览）
CREATE INDEX idx_asset_importedAt ON asset(importedAt DESC);

-- 评分筛选
CREATE INDEX idx_asset_rating ON asset(rating) WHERE rating > 0;

-- 文件类型筛选
CREATE INDEX idx_asset_ext ON asset(fileExtension);

-- 颜色筛选（前缀匹配）
CREATE INDEX idx_asset_color ON asset(primaryColorHex);

-- 缓存淘汰（LRU）
CREATE INDEX idx_asset_lastAccess ON asset(lastAccessedAt) WHERE originalCached = 1;

-- 标签精确筛选（覆盖索引，无需回表）
CREATE INDEX idx_asset_tag_tag ON asset_tag(tag, assetID);

-- 文件夹浏览
CREATE INDEX idx_asset_folder ON asset_folder(folderID, assetID);

-- 复合索引：文件类型 + 时间（常见组合筛选）
CREATE INDEX idx_asset_ext_time ON asset(fileExtension, importedAt DESC);

-- 复合索引：评分 + 时间
CREATE INDEX idx_asset_rating_time ON asset(rating, importedAt DESC) WHERE rating > 0;
```

索引验证流程：每个查询在开发阶段必须通过 `EXPLAIN QUERY PLAN` 确认走索引而非全表扫描。GRDB 提供 `db.execute(sql: "EXPLAIN QUERY PLAN ...")` 便于自动化测试。

#### 3. 批量导入策略

```
核心原则：单事务批量 INSERT + 延迟建索引 + 流水线并行
```

```
首次导入流程：
┌─────────────┐    ┌──────────────┐    ┌───────────────┐
│ 扫描文件系统  │ →  │ 并行解析 JSON │ →  │ SQL 批量写入    │
│ 收集路径列表  │    │ TaskGroup     │    │ db.inTransaction│
│              │    │ (8 并发)      │    │ (1000条/事务)  │
└─────────────┘    └──────────────┘    └───────────────┘
                                              ↓
                                       ┌───────────────┐
                                       │ 重建 FTS5 索引  │
                                       │ 通知 UI 刷新    │
                                       └───────────────┘
```

GRDB 批量导入 vs SwiftData 批量导入：

```swift
// GRDB: 单事务批量插入，零对象追踪开销
try dbWriter.write { db in
    // 导入期间临时禁用索引（提速 3-5x）
    try db.execute(sql: "PRAGMA synchronous = NORMAL")

    for batch in dtos.chunked(into: 1000) {
        for dto in batch {
            try Asset(dto: dto).insert(db)
        }
    }

    // 批量填充 FTS5
    try db.execute(sql: """
        INSERT INTO asset_fts(rowid, name, tags, annotation, ocrText)
        SELECT rowid, name,
               (SELECT GROUP_CONCAT(tag, ' ') FROM asset_tag WHERE assetID = asset.id),
               annotation, ocrText
        FROM asset
    """)
}
// 1 万条: ~3-5 秒（iPhone 12+）

// SwiftData 等效操作:
// let context = ModelContext(container)
// for dto in dtos {
//     let asset = AssetModel(dto: dto)  // 实例化 @Model（内存分配 + 变更追踪注册）
//     context.insert(asset)             // 注册到上下文
// }
// try context.save()                    // 序列化 + 写 SQLite
// 1 万条: ~15-30 秒（@Model 实例化开销）
```

增量更新策略：

- 记录 `lastScanTimestamp`，增量扫描只处理 `modificationDate > lastScanTimestamp` 的文件
- 使用 `INSERT OR REPLACE` 语义，存在则更新、不存在则插入
- FTS5 索引增量更新：`INSERT OR REPLACE INTO asset_fts(...) VALUES(...)`
- 检测删除：`DELETE FROM asset WHERE id NOT IN (?,?,?...)`

#### 4. 查询性能优化

```
核心原则：FTS5 处理文本搜索 + SQL 索引处理结构化筛选 + 分页加载
```

查询分层：

```
用户输入 "渐变"
     │
     ▼
┌─────────────────────────────────────────┐
│  SearchCoordinator 判断查询类型          │
│                                          │
│  有关键字？→ FTS5: MATCH '渐变*'          │
│  有标签筛选？→ JOIN asset_tag             │
│  有评分筛选？→ WHERE rating >= ?          │
│  有文件类型？→ WHERE fileExtension IN (?) │
│  有时间范围？→ WHERE importedAt BETWEEN   │
│  有颜色搜索？→ 内存中 DeltaE 计算         │
│  有语义搜索？→ 内存中 CLIP 余弦相似度     │
│                                          │
│  组合为单条 SQL，一次查询完成              │
└─────────────────────────────────────────┘
```

FTS5 搜索细节：

```sql
-- 关键字搜索（支持前缀匹配）
SELECT asset.* FROM asset
JOIN asset_fts ON asset.rowid = asset_fts.rowid
WHERE asset_fts MATCH '渐变*'
ORDER BY rank
LIMIT 50 OFFSET 0;
-- 1 万条: < 5ms

-- 关键字 + 标签筛选组合
SELECT asset.* FROM asset
JOIN asset_fts ON asset.rowid = asset_fts.rowid
JOIN asset_tag ON asset_tag.assetID = asset.id
WHERE asset_fts MATCH '设计*'
  AND asset_tag.tag = 'UI'
  AND asset.rating >= 3
ORDER BY asset.importedAt DESC
LIMIT 50;
-- 1 万条: < 20ms
```

分页加载：

- 使用 `LIMIT/OFFSET` 分页，每页 50-100 条
- 瀑布流/网格使用 GRDB 的 `ValueObservation` 绑定分页结果到 SwiftUI
- 滚动到底部时加载下一页，无需全量 fetch
- 搜索防抖：输入停顿 300ms 后才触发查询

#### 5. 内存管理

```
核心原则：值类型零开销 + 按需加载大字段 + NSCache 管缩略图
```

- GRDB 的 Record 是纯 Swift struct，fetch 后无变更追踪开销，ARC 自动释放
- 大字段分离查询：默认查询排除 `clipVector`（BLOB 2KB/条）和 `palettesJSON`，仅在需要时单独 fetch
- 缩略图使用独立的 `NSCache` 内存缓存，设置 `countLimit = 500` 和 `totalCostLimit`
- CLIP 向量数据：AI 搜索时批量 `SELECT id, clipVector FROM asset WHERE clipVector IS NOT NULL`，加载到 `[String: [Float]]` 内存字典，搜索完毕释放
- 分页查询保证任何时刻内存中只有当前页 + 前后缓冲页的 struct 实例

### 实施详情

→ Issue「[ADR] 大数据量性能策略」

### 备注

性能基准测试矩阵（需在真机上验证）：

| 素材数量 | 首次索引 | FTS5 搜索 | 多维筛选 | 滚动帧率 | 内存峰值 |
|---------|---------|----------|---------|---------|---------|
| 1,000   | < 3s    | < 5ms   | < 20ms  | 60fps   | < 80MB  |
| 5,000   | < 10s   | < 5ms   | < 30ms  | 60fps   | < 100MB |
| 10,000  | < 25s   | < 10ms  | < 50ms  | ≥ 55fps | < 150MB |
| 50,000  | < 2min  | < 20ms  | < 100ms | ≥ 55fps | < 200MB |

FTS5 的倒排索引结构使文本搜索性能与数据量近似对数关系增长（而非线性），所以 1 万和 5 万的搜索时间差距很小。

如果 10 万+ 素材场景下 CLIP 向量暴力搜索（全量余弦相似度计算）性能不足，可引入 USearch 近似最近邻索引或 Accelerate/vDSP 的 SIMD 向量运算加速。

---

## GRDB 模型层架构

### 说明

定义 GRDB Record 模型的组织结构、表间关系、FTS5 索引同步机制、以及与 Eagle 文件系统数据的映射关系。

核心模型关系：

```
┌───────────────────────────────────────────────────────────┐
│                     GRDB 模型层                             │
│                                                            │
│  ┌──────────┐  1:N  ┌──────────┐  N:M  ┌──────────────┐  │
│  │  folder   │ ←──── │asset_folder│ ────→│    asset      │  │
│  │ (文件夹)  │       │ (关联表)  │       │   (素材)      │  │
│  └──────────┘       └──────────┘       └──────────────┘  │
│       │ parentID                             │ 1:N        │
│       ↓ (自引用)                              ↓            │
│  ┌──────────┐                          ┌──────────────┐  │
│  │  folder   │                          │  asset_tag    │  │
│  │ (子文件夹) │                          │ (标签关联)    │  │
│  └──────────┘                          └──────────────┘  │
│                                              │ N:1        │
│                    ┌──────────┐              ↓            │
│                    │   tag     │ ←───────────┘            │
│                    │ (全局标签) │                           │
│                    └──────────┘                           │
│                                                            │
│                    ┌──────────────┐                        │
│                    │  annotation   │                        │
│                    │   (标注)      │ N:1 → asset            │
│                    └──────────────┘                        │
│                                                            │
│                    ┌──────────────┐                        │
│                    │  asset_fts    │ FTS5 虚拟表            │
│                    │ (全文索引)    │ 同步自 asset + asset_tag│
│                    └──────────────┘                        │
└───────────────────────────────────────────────────────────┘
```

| 表 | 对应 Eagle 数据 | 类型 | 说明 |
|------|----------------|------|------|
| asset | `images/XXX.info/metadata.json` | 主表 | 素材核心数据，宽表设计 |
| folder | 文件夹层级 | 主表 | 自引用树形结构（parentID） |
| tag | `tags.json` | 主表 | 全局标签定义（名称、颜色） |
| asset_tag | 素材 ↔ 标签 | 关联表 | 多对多，支持精确匹配和组合筛选 |
| asset_folder | 素材 ↔ 文件夹 | 关联表 | 多对多（Eagle 支持素材归属多个文件夹） |
| annotation | Talon 独有 | 主表 | 标注/批注数据，不写回 Eagle |
| asset_fts | 合成自多表 | FTS5 虚拟表 | 全文搜索索引，内容来自 asset + asset_tag |

### 当前项目选择

GRDB Record 为纯 Swift struct，符合 `Codable`、`FetchableRecord`、`PersistableRecord` 协议：

```swift
// Asset Record
struct Asset: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String              // Eagle 13位随机ID
    var name: String
    var fileExtension: String
    var fileSize: Int64
    var width: Int
    var height: Int
    var rating: Int
    var sourceURL: String?
    var annotation: String?
    var createdAt: Date
    var modifiedAt: Date
    var importedAt: Date
    var relativePath: String
    var thumbnailPath: String
    var primaryColorHex: String?
    var palettesJSON: String?
    var clipVector: Data?
    var ocrText: String?
    var aiTags: String?
    var thumbnailCached: Bool
    var originalCached: Bool
    var lastAccessedAt: Date?

    // GRDB 关联定义
    static let tags = hasMany(AssetTag.self)
    static let folders = hasMany(Folder.self, through: hasMany(AssetFolder.self), using: AssetFolder.folder)
    static let annotations = hasMany(Annotation.self)
}

// 标签关联 Record
struct AssetTag: Codable, FetchableRecord, PersistableRecord {
    var assetID: String
    var tag: String
}
```

SwiftUI 集成方式（通过 `GRDBQuery` SPM 包）：

```swift
// ViewModel 中使用 ValueObservation 观察查询结果
@Observable
final class AssetGridViewModel {
    private(set) var assets: [Asset] = []
    private var observation: AnyDatabaseCancellable?

    func observe(in dbQueue: DatabaseQueue, filter: AssetFilter) {
        observation = ValueObservation
            .tracking { db in
                try Asset
                    .filter(/* SQL 条件 */)
                    .order(Column("importedAt").desc)
                    .limit(100)
                    .fetchAll(db)
            }
            .start(in: dbQueue, onError: { _ in }, onChange: { [weak self] assets in
                self?.assets = assets
            })
    }
}
```

关键设计决策：

- 标签使用 `asset_tag` 关联表而非逗号字符串 — 精确匹配、组合筛选走索引，FTS5 负责模糊搜索
- FTS5 contentless 模式 — `content=''` 意味着 FTS5 不存储原始文本的副本，只存倒排索引，节省空间。需要手动维护 FTS5 与主表的同步（插入/更新/删除时同步 FTS5）
- 每个 Library 对应独立的 `.sqlite` 文件 — 切换资源库时切换 `DatabaseQueue` 实例，避免单库内的 Library ID 过滤开销
- CLIP 向量存储为 BLOB — 512 × float32 = 2KB/条，不单独建表。AI 搜索时一次性 `SELECT id, clipVector` 加载到内存

FTS5 同步触发器（自动维护索引一致性）：

```sql
-- 插入 asset 时同步 FTS5
CREATE TRIGGER asset_fts_insert AFTER INSERT ON asset BEGIN
    INSERT INTO asset_fts(rowid, name, tags, annotation, ocrText)
    VALUES (
        NEW.rowid,
        NEW.name,
        (SELECT GROUP_CONCAT(tag, ' ') FROM asset_tag WHERE assetID = NEW.id),
        NEW.annotation,
        NEW.ocrText
    );
END;

-- 更新 asset 时同步 FTS5
CREATE TRIGGER asset_fts_update AFTER UPDATE ON asset BEGIN
    DELETE FROM asset_fts WHERE rowid = OLD.rowid;
    INSERT INTO asset_fts(rowid, name, tags, annotation, ocrText)
    VALUES (
        NEW.rowid,
        NEW.name,
        (SELECT GROUP_CONCAT(tag, ' ') FROM asset_tag WHERE assetID = NEW.id),
        NEW.annotation,
        NEW.ocrText
    );
END;

-- 删除 asset 时同步 FTS5
CREATE TRIGGER asset_fts_delete AFTER DELETE ON asset BEGIN
    DELETE FROM asset_fts WHERE rowid = OLD.rowid;
END;

-- 标签变更时更新对应 asset 的 FTS5 记录
CREATE TRIGGER asset_tag_change AFTER INSERT ON asset_tag BEGIN
    DELETE FROM asset_fts WHERE rowid = (SELECT rowid FROM asset WHERE id = NEW.assetID);
    INSERT INTO asset_fts(rowid, name, tags, annotation, ocrText)
    SELECT rowid, name,
           (SELECT GROUP_CONCAT(tag, ' ') FROM asset_tag WHERE assetID = asset.id),
           annotation, ocrText
    FROM asset WHERE id = NEW.assetID;
END;
```

### 实施详情

→ Issue「[ADR] GRDB 模型层架构」

### 备注

多 Library 隔离方案：每个 Eagle 资源库对应独立的 `{libraryID}.sqlite` 文件，存放在 `Application Support/Talon/Databases/` 目录。切换资源库时关闭旧 `DatabaseQueue` 并打开新实例。删除资源库直接删文件。

GRDB 的 `DatabaseMigrator` 管理 schema 版本迁移：

```swift
var migrator = DatabaseMigrator()
migrator.registerMigration("v1") { db in
    try db.create(table: "asset") { t in /* ... */ }
    try db.create(table: "folder") { t in /* ... */ }
    // ...
}
migrator.registerMigration("v2-fts5") { db in
    try db.create(virtualTable: "asset_fts", using: FTS5()) { t in /* ... */ }
}
try migrator.migrate(dbQueue)
```

---

## Eagle 资源库解析架构

### 说明

将 Eagle `.library` 文件系统结构转换为 GRDB Record 的解析流程设计。

需要处理的数据源：

| 文件 | 内容 | 解析频率 |
|------|------|---------|
| `metadata.json`（根目录） | 资源库全局配置 | 仅首次 |
| `tags.json` | 全局标签定义 | 首次 + 变更检测 |
| `images/*/metadata.json` | 每个素材的元数据 | 首次全量 + 增量 |
| `images/*/_thumbnail.png` | Eagle 预生成缩略图 | 按需读取 |

解析流程：

```
Eagle .library 文件系统                    GRDB (SQLite)
━━━━━━━━━━━━━━━━━━━━━━                    ━━━━━━━━━━━━━

  ┌──────────────┐      ┌───────────┐      ┌────────────┐
  │ metadata.json │ ──→  │ LibraryDTO│ ──→  │  metadata  │
  │ (根目录)      │      │           │      │  (配置表)   │
  └──────────────┘      └───────────┘      └────────────┘

  ┌──────────────┐      ┌───────────┐      ┌────────────┐
  │  tags.json   │ ──→  │  TagDTO   │ ──→  │  tag 表     │
  └──────────────┘      └───────────┘      └────────────┘

  ┌──────────────┐      ┌───────────┐      ┌────────────┐
  │ images/*/    │ ──→  │ AssetDTO  │ ──→  │ asset 表    │
  │ metadata.json│      │ (Codable) │      │ + asset_tag │
  └──────────────┘      └───────────┘      │ + asset_fts │
       ↑                                    └────────────┘
  并行解析 (TaskGroup)               SQL 事务批量写入 (1000条/事务)
```

DTO 层的作用：

- `AssetDTO`：纯 `Codable` 结构体，1:1 映射 Eagle 的 metadata.json 字段
- 解析时先反序列化为 DTO，再转换为 GRDB Record
- DTO 与 Record 分离，确保 Eagle 格式变更不影响数据库 schema
- DTO 层处理字段类型转换（Eagle 时间戳为 Unix milliseconds → Date）

增量同步策略：

- 记录 `Library.lastScanDate` 为上次全量/增量扫描时间
- 增量扫描时，遍历 `images/` 目录，比较每个 `metadata.json` 的文件系统 `modificationDate` 与 `lastScanDate`
- 仅解析 `modificationDate > lastScanDate` 的文件
- 检测被删除的素材：对比数据库中的 asset.id 集合与文件系统中实际存在的目录集合

### 当前项目选择

三层架构：FileSystem → DTO → GRDB Record

- `EagleLibraryScanner`：负责文件系统遍历和变更检测
- `EagleMetadataParser`：负责 JSON 解析为 DTO
- `LibraryIndexer`：负责 DTO 到 GRDB Record 的转换和 SQL 事务批量写入

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
| 素材元数据 | Eagle metadata.json → GRDB | GRDB/SQLite 即缓存 | 解析后即持久化，本地数据库本身就是离线缓存 |
| 缩略图 | Eagle `_thumbnail.png` | 磁盘缓存（Application Support） | 复制到 App 沙盒，避免反复访问安全作用域 |
| 原始文件 | Eagle 原始素材文件 | 按需磁盘缓存 + LRU 淘汰 | 用户查看过的原图缓存到本地 |
| CLIP 向量 | 本地 Core ML 计算 | GRDB `asset.clipVector` 字段 | 计算一次，永久存储 |
| OCR 文本 | 本地 Vision 计算 | GRDB `asset.ocrText` 字段 | 计算一次，永久存储 |
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
│ 数据库层 (GRDB / SQLite)                         │
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

现有的 `CacheManager.swift`（JSON 文件缓存）适用于 Supabase 远端数据缓存场景。Talon 的主要数据源是本地文件系统，GRDB/SQLite 本身承担了缓存角色，因此 `CacheManager` 在当前架构中仅用于缓存 Supabase 的用户账户信息、订阅状态等少量远端数据。

---

## AI/ML 本地推理架构

### 说明

Talon 的 AI 功能全部在设备端运行，涉及多个 ML 模型和框架的协调：

| 功能 | 框架/模型 | 输入 | 输出 | 存储 |
|------|----------|------|------|------|
| 语义搜索 | MobileCLIP-S0 (Core ML) | 图片 / 文本 | 512 维向量 | GRDB `asset.clipVector` |
| 自动标签 | VNClassifyImageRequest | 图片 | 分类标签 + 置信度 | GRDB `asset.aiTags` + `asset_tag` |
| OCR | VNRecognizeTextRequest | 图片 | 识别文本 | GRDB `asset.ocrText` + FTS5 |
| 图片特征指纹 | VNGenerateImageFeaturePrintRequest | 图片 | 特征指纹 | GRDB 独立字段 |
| 风格识别 (P3) | Create ML 自定义模型 | 图片 | 风格分类 | GRDB `asset_tag` |

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
- 向量数据存储在 GRDB 的 `asset.clipVector` BLOB 字段，搜索时 `SELECT id, clipVector` 批量加载到内存中的 `[String: [Float]]` 字典

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
   - ViewModel 通过 GRDB `ValueObservation` 提供分页数据，滚动路径上无数据库查询

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
| L1 关键字搜索 | 名称、标签、备注模糊匹配 | SQLite FTS5 全文索引 `MATCH` | P0 |
| L2 多维筛选 | 文件类型、评分、颜色、时间、尺寸组合 | GRDB 组合 SQL 查询 + 索引 | P0 |
| L3 AI 语义搜索 | 自然语言描述搜图 | MobileCLIP 向量相似度 | P1 |
| L4 OCR 搜索 | 图片中的文字内容搜索 | Vision OCR → FTS5 索引 | P1 |
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
│  │ GRDB SQL│  │  CLIP   │  │  Color  │           │
│  │ + FTS5  │  │ Vector  │  │ DeltaE  │           │
│  │ Engine  │  │ Engine  │  │ Engine  │           │
│  └────┬─────┘  └────┬────┘  └────┬────┘           │
│       ↓              ↓            ↓                 │
│  ┌─────────────────────────────────────────────┐   │
│  │        结果合并 & 排序 & 分页                  │   │
│  └─────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

GRDB + FTS5 查询策略：

- 文本搜索直接走 FTS5 `MATCH` 查询，毫秒级返回
- 结构化筛选（评分、类型、时间）组合为单条 SQL `WHERE` 子句，所有条件都有对应索引
- 文本搜索 + 结构化筛选可以在一条 SQL 中组合（`JOIN asset_fts ... WHERE ... AND asset_fts MATCH ...`）
- 查询结果通过 `LIMIT/OFFSET` 分页，ViewModel 仅持有当前页数据
- `ValueObservation` 精确监听相关表变更，不会因为无关修改触发重查询

颜色搜索：

- 从 Eagle palette 数据提取主色调 HEX
- 用户选择目标颜色后，计算 CIEDE2000 DeltaE 值
- 预计算所有素材主色调的 Lab 色彩空间坐标，存入 GRDB 辅助列
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
- 写入完成后同步更新 GRDB 索引（asset 表 + asset_tag + FTS5）
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
├── Models/                          # GRDB Record (struct)
│   ├── Asset.swift
│   ├── Folder.swift
│   ├── Tag.swift
│   ├── AssetTag.swift
│   ├── AssetFolder.swift
│   ├── Annotation.swift
│   └── AppDatabase.swift           # DatabaseQueue 配置 + Migration
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
│   ├── LibraryIndexer.swift         # GRDB 批量写入 + FTS5 索引构建
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
View → ViewModel → Service → Record/DTO
                      ↓
                  GRDB (SQLite) / FileSystem
```

- View 只依赖 ViewModel，不直接访问 Service 或 Record
- ViewModel 通过 Service 层操作数据，使用 `ValueObservation` 监听变更驱动 UI 刷新
- Service 层负责所有 I/O（文件系统、GRDB、Core ML）
- Record 层纯数据定义（struct），无业务逻辑

### 实施详情

→ Issue「[ADR] App 架构与模块划分」

### 备注

第三方 Package 依赖已在 `TalonApp.swift` 中全局导出：LayoutUIKit、BrandKit、SupabaseKit、RevenueCatKit、PromoKit。Feature 模块无需重复 import。

---

## 并发模型

### 说明

Talon 涉及大量异步操作：文件系统扫描、JSON 解析、图片解码、AI 推理、数据库读写。需要明确的并发策略避免数据竞争和主线程阻塞。

### 当前项目选择

Swift Concurrency（async/await + Actor）为主：

| 组件 | 隔离策略 | 说明 |
|------|---------|------|
| View | @MainActor | SwiftUI 要求 |
| ViewModel | @MainActor | 驱动 UI 更新，持有 ValueObservation |
| ThumbnailLoader | actor | 请求合并、缓存管理 |
| LibraryIndexer | 非隔离，后台 Task | SQL 事务批量写入，不阻塞 UI |
| AIProcessingPipeline | 非隔离，TaskGroup | 并发 ML 推理 |
| EagleLibraryScanner | 非隔离，async | 文件系统遍历 |
| GRDB DatabaseQueue | 内建并发安全 | WAL 模式，读写互不阻塞 |

GRDB 并发模型：

- `DatabaseQueue` / `DatabasePool` 内建并发安全，无需手动管理上下文
- 读操作：`dbQueue.read { db in ... }` — 可从任意线程调用，自动串行化
- 写操作：`dbQueue.write { db in ... }` — 串行写入，保证事务完整性
- WAL 模式（Write-Ahead Logging）：读写并发不阻塞，写入不影响正在进行的读取
- `ValueObservation`：在后台线程观察数据库变更，自动在主线程回调 UI 更新
- Record 是值类型 struct，可安全跨线程传递（无引用语义问题）

### 实施详情

→ Issue「[ADR] 并发模型」

### 备注

Swift 6 严格并发检查（`SWIFT_STRICT_CONCURRENCY=complete`）建议从项目初始就启用，避免后期迁移成本。
