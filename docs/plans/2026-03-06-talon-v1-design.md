# Talon v1.0 设计文档

## 产品定位

Eagle 素材库的 iPhone 只读伴侣应用。完全免费，专注浏览和搜索体验，先积累用户和口碑，等后续 AI 功能上线后再引入付费。

## 目标用户

Eagle 桌面端用户（400K+ 用户群），需要在移动端随时浏览和检索设计素材。

## 平台策略

- iPhone 优先
- iPad 自适应（不深度优化）
- macOS 暂不做

## 功能边界

### v1.0 包含

| 编号 | 功能 | 说明 |
|------|------|------|
| F-001 | Eagle .library 解析与索引 | 遍历目录结构，解析 metadata.json，批量写入 GRDB |
| F-002 | iCloud Drive + SMB 网络访问 | 两种方式访问 Eagle 库 |
| F-003 | 瀑布流 / 网格 / 列表三种布局 | iPhone 优先，iPad 自适应 |
| F-004 | 标签搜索 + 多维度筛选 | FTS5 关键词搜索 + 类型/标签/文件夹/日期/评分筛选 |
| F-005 | 多格式文件预览 | JPG/PNG/GIF/WebP 原生，SVG (WebView)，PDF (PDFKit) |
| F-006 | 离线缓存 | 缩略图缓存 + 原始文件 LRU 缓存 |

### v1.0 不包含

- AI 语义搜索 / OCR / 颜色搜索（P1）
- 素材导入 / 编辑 / 写回 Eagle 格式（P1）
- 标注功能（P1）
- 付费 / 订阅体系（P1+）
- PSD 原始文件预览（仅显示缩略图）
- macOS 专属优化
- 多窗口 / Stage Manager / Apple Pencil

## 架构设计

### 整体架构（MVVM）

```
┌─────────────────────────────────────┐
│            SwiftUI Views            │
│  (Browse / Search / Preview / Settings) │
├─────────────────────────────────────┤
│           ViewModels (MVVM)         │
├──────────┬──────────┬───────────────┤
│ Eagle    │ Search   │ Thumbnail     │
│ Parser   │ Service  │ Loader        │
│ Service  │ (FTS5)   │ (Actor)       │
├──────────┴──────────┴───────────────┤
│         GRDB (SQLite + FTS5)        │
├─────────────────────────────────────┤
│   File Access Layer                 │
│   (Security Bookmarks + SMB)        │
└─────────────────────────────────────┘
```

依赖方向：View → ViewModel → Service → Record/DTO

### 核心模块（6 个）

#### 1. File Access — 文件访问层

- `ScopedAccessManager`：安全书签管理，持久化用户授权的目录访问权限
- iCloud Drive：通过 `UIDocumentPickerViewController` 选择 .library 目录
- SMB：通过系统原生 SMB 挂载（Files app 已连接的网络位置），无需自实现 SMB 协议
- 职责边界：只负责"拿到目录访问权"，不关心内容解析

#### 2. Eagle Parser — 库解析引擎

- `EagleLibraryScanner`：遍历 .library 目录结构，发现所有素材文件夹
- `EagleMetadataParser`：解析每个素材的 `metadata.json`（DTO 层）
- `LibraryIndexer`：批量写入 GRDB，事务制（1000 条/事务），支持增量扫描（基于 `lastScanDate`）
- 解析流程：FileSystem → DTO → GRDB Record
- 三层架构确保关注点分离

#### 3. Data Layer — 数据持久化

- GRDB + FTS5，每个库独立 `.sqlite` 文件
- 核心表：
  - `asset`：素材主表（名称、格式、尺寸、评分、创建/修改日期等）
  - `folder`：文件夹（支持嵌套）
  - `tag`：标签
  - `asset_tag`：素材-标签关联
  - `asset_folder`：素材-文件夹关联
  - `asset_fts`：FTS5 全文索引（名称、标签、备注）
- 9 个索引覆盖所有查询路径
- `DatabaseMigrator` 管理 schema 版本迁移
- `ValueObservation` 驱动 UI 响应式更新

#### 4. Browse — 浏览模块

- 三种布局：
  - 瀑布流（`WaterfallLayout` 自定义布局）
  - 网格（`LazyVGrid`）
  - 列表（`List`）
- 文件夹导航：树形结构 + 面包屑
- 排序：名称 / 日期 / 大小 / 类型
- 分页加载：50-100 条/页，LIMIT/OFFSET
- 滚动性能：stable ID + 缩略图预加载

#### 5. Search — 搜索模块

- FTS5 关键词搜索（素材名称、标签匹配）
- 多维度筛选：
  - 文件类型（图片/矢量/PDF 等）
  - 标签（多选）
  - 文件夹
  - 日期范围
  - 评分
- `SearchCoordinator` 统一调度查询
- 搜索历史 + 热门标签推荐

#### 6. Preview — 预览模块

- 图片（JPG/PNG/WebP）：原生 `Image`，支持双指缩放 + 双击缩放
- GIF：`UIImage` 动图播放
- SVG：`WKWebView` 渲染
- PDF：`PDFKit` 原生多页预览
- 不支持的格式（PSD 等）：展示 Eagle 生成的缩略图 + 格式标识
- 素材详情页：元数据展示（标签、尺寸、格式、创建日期、文件大小等）

## 缓存策略

| 层级 | 技术 | 策略 |
|------|------|------|
| 内存-缩略图 | NSCache | countLimit = 500 |
| 内存-解码图 | NSCache | countLimit = 10 |
| 磁盘-缩略图 | Application Support | 优先使用 Eagle 生成的 _thumbnail.png |
| 磁盘-原始文件 | Application Support | LRU 淘汰，可配置上限 |
| 数据库 | GRDB | 元数据持久化，每库独立文件 |

- 离线时展示缓存版本
- 原始文件按需下载

## 性能目标

| 指标 | 目标值 |
|------|--------|
| 首次索引 1,000 素材 | < 10s |
| FTS5 关键词搜索（万级） | < 50ms |
| 多维筛选（万级） | < 100ms |
| 滚动帧率（万级素材） | ≥ 55fps |
| 布局模式切换 | < 300ms |
| 内存占用（万级素材） | < 150MB |

## 开发阶段

```
Phase 1: 地基      → GRDB 模型 + Eagle 解析器 + 文件访问
Phase 2: 能看      → 浏览界面 + 三种布局 + 缩略图加载
Phase 3: 能搜      → FTS5 搜索 + 多维筛选 + 搜索 UI
Phase 4: 能看细节  → 预览模块 + 多格式支持 + 素材详情
Phase 5: 能用      → 离线缓存 + SMB 支持 + 设置页
Phase 6: 能上架    → 性能优化 + UI 打磨 + TestFlight + App Store 提审
```

## 商业策略

- v1.0 完全免费，无内购
- 目标：快速积累用户基础和 App Store 评分
- 后续 P1 版本引入 AI 功能时启用 RevenueCat 订阅体系

## 未来扩展（不在 v1.0 范围内）

- P1：AI 语义搜索、自动标签、OCR、颜色搜索、素材写入
- P2：重复检测、智能文件夹、批量操作、iPad 多窗口
- P3：设计风格识别、Mood Board、团队协作
