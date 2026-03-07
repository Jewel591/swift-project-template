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

- [ ] **App 启动书签恢复**: `ContentView` 启动时检查已保存的 security-scoped bookmark，自动恢复上次打开的 library，避免每次手动选择
- [ ] **增量索引**: 当前 `LibraryIndexer` 只支持全量导入，需要利用 `EagleLibraryScanner.scanModifiedAssetFolders(since:)` 实现增量更新
- [ ] **AssetPreviewView 缩放手势**: `ZoomableImageView` 目前只是简单显示图片，需要添加 MagnifyGesture + DragGesture 实现双指缩放和拖拽
- [ ] **搜索筛选 UI**: `SearchViewModel` 已有 `selectedTags`、`selectedFileTypes`、`minRating` 等筛选状态，但 `SearchView` 尚未提供筛选面板 UI
- [ ] **DiskCacheManager 与 ThumbnailLoader 集成**: 当前 `ThumbnailLoader` 只使用内存缓存，需要在 cache miss 时先查磁盘缓存
- [ ] **分页加载触发**: `AssetGridView` 需要在滚动到底部时触发 `viewModel.loadNextPage()`
- [ ] **GRDBQuery @Query 宏集成**: 考虑用 GRDBQuery 的 `@Query` property wrapper 替换手动 `ValueObservation` 代码

### 测试

- [ ] `EagleMetadataParser` 单元测试（mock metadata.json）
- [ ] `SearchCoordinator` 单元测试（内存数据库 + 各种查询组合）
- [ ] `LibraryIndexer` 集成测试
- [ ] `AppDatabase` 迁移测试

### 优化

- [ ] FTS5 索引增量更新（当前全量重建）
- [ ] 大库性能测试（10万+ 素材）
- [ ] 内存占用监控和 thumbnail cache 调优
