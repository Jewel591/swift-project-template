# Talon v1.0 开发进度

> 最后更新: 2026-03-07

## 总体状态

- 分支: `claude/fork-talon-project-tZAaq`
- 计划文档: `docs/plans/2026-03-06-talon-v1-implementation.md`
- 设计文档: `docs/plans/2026-03-06-talon-v1-design.md`

---

## 已完成

### Phase 1: Foundation (GRDB Models + Eagle Parser + File Access)

| Task | 文件 | 状态 |
|------|------|------|
| Task 1: Add GRDB Package Dependency | 需在 Xcode 中手动添加 | ⚠️ 需手动操作 |
| Task 2: Asset Record Models | `Talon/Models/Asset.swift`, `AssetTag.swift`, `AssetFolder.swift` | ✅ 完成 |
| Task 3: Folder & Tag Record Models | `Talon/Models/Folder.swift`, `Tag.swift` | ✅ 完成 |
| Task 4: AppDatabase | `Talon/Models/AppDatabase.swift` | ✅ 完成 |
| Task 5: Eagle DTO Models | `Talon/DTOs/AssetDTO.swift`, `TagDTO.swift`, `LibraryDTO.swift` | ✅ 完成 |
| Task 6: EagleLibraryScanner | `Talon/Services/EagleLibraryScanner.swift` | ✅ 完成 |
| Task 7: EagleMetadataParser | `Talon/Services/EagleMetadataParser.swift` | ✅ 完成 |
| Task 8: LibraryIndexer | `Talon/Services/LibraryIndexer.swift` | ✅ 完成 |
| Task 9: ScopedAccessManager | `Talon/Services/ScopedAccessManager.swift` | ✅ 完成 |

### Phase 2: Browse UI (Thumbnail + Grid + Folder Navigation)

| Task | 文件 | 状态 |
|------|------|------|
| Task 10: ThumbnailLoader Actor | `Talon/Services/ThumbnailLoader.swift` | ✅ 完成 |
| Task 11: ThumbnailView Component | `Talon/Components/ThumbnailView.swift` | ✅ 完成 |
| Task 12: AssetGridViewModel | `Talon/Features/AssetGrid/AssetGridViewModel.swift` | ✅ 完成 |
| Task 13: Grid/List Layout Views | `Talon/Features/AssetGrid/AssetGridView.swift` | ✅ 完成 |
| Task 14: Folder Navigation | `Talon/Features/LibraryBrowser/LibraryBrowserViewModel.swift`, `LibraryBrowserView.swift` | ✅ 完成 |

### Phase 3: Search

| Task | 文件 | 状态 |
|------|------|------|
| Task 15: SearchCoordinator | `Talon/Features/Search/SearchCoordinator.swift` | ✅ 完成 |
| Task 16: SearchView & ViewModel | `Talon/Features/Search/SearchViewModel.swift`, `SearchView.swift` | ✅ 完成 |

### Phase 4: Preview + Cache + Settings + Wiring

| Task | 文件 | 状态 |
|------|------|------|
| Task 17: AssetPreviewView | `Talon/Features/Preview/AssetPreviewView.swift`, `AssetDetailSheet.swift` | ✅ 完成 |
| Task 18: DiskCacheManager | `Talon/Services/DiskCacheManager.swift` | ✅ 完成 |
| Task 19: SettingsView | `Talon/Features/Settings/SettingsView.swift` | ✅ 完成 |
| Task 20: Main TabView Wiring | `Talon/ContentView.swift` (改写) | ✅ 完成 |

---

## 未完成 / 后续工作

### 必须完成（项目可运行的前提）

- [ ] **在 Xcode 中添加 GRDB 依赖**: 通过 File → Add Package Dependencies 添加 `GRDB 7.0+` (`https://github.com/groue/GRDB.swift.git`) 和 `GRDBQuery 0.9+` (`https://github.com/groue/GRDBQuery.git`)
- [ ] **编译修复**: 所有代码在 Linux 上编写未经编译验证，预计有类型推断、import 缺失、API 签名等编译错误需逐一修复

### 功能补全

- [x] **App 启动书签恢复**: `ContentView` 启动时自动从 security-scoped bookmark 恢复上次打开的 library，并触发增量索引
- [x] **增量索引**: `LibraryIndexer.incrementalIndex(since:)` 只扫描修改过的 asset 文件夹，增量更新 FTS5
- [x] **AssetPreviewView 缩放手势**: `ZoomableImageView` 支持 MagnifyGesture 缩放（1x-5x）、DragGesture 拖拽、双击切换 3x/1x
- [x] **搜索筛选 UI**: `SearchView` 添加文件类型 FilterChip、评分星级筛选、Clear Filters 按钮，筛选状态驱动搜索
- [x] **DiskCacheManager 与 ThumbnailLoader 集成**: `ThumbnailLoader` 现在三级缓存：memory → disk → source，disk miss 时自动写入
- [x] **分页加载触发**: `AssetGridView` 在倒数第 5 个 item 出现时自动触发 `loadNextPage()`，带 loading indicator
- [x] **GRDBQuery @Query 宏集成**: 新增 `DatabaseContext.swift`，提供 `appDatabase` 环境键 + `AssetListRequest`、`FolderListRequest`、`AssetCountRequest` 三个可复用 Query 类型

### 测试

- [ ] `EagleMetadataParser` 单元测试（mock metadata.json）
- [ ] `SearchCoordinator` 单元测试（内存数据库 + 各种查询组合）
- [ ] `LibraryIndexer` 集成测试
- [ ] `AppDatabase` 迁移测试

### 优化

- [x] FTS5 索引增量更新（`incrementalIndex` 已支持按 asset 粒度增量更新 FTS5）
- [ ] 大库性能测试（10万+ 素材）
- [ ] 内存占用监控和 thumbnail cache 调优
