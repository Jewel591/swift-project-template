# Brand 模块规范

## 颜色规范

- **唯一颜色来源**：`Brand/Color+Brand.swift`
- **除了白名单外，任何颜色写法都视为违规**

### 白名单（允许使用）

| 用途 | 允许用法 |
|------|----------|
| 品牌主色 | `Color.brand` |
| 品牌浅色 | `Color.brandLight` |
| 品牌语义色 | `Color.brandRed / brandOrange / brandYellow / brandGreen / brandTeal / brandBlue / brandIndigo / brandPurple / brandPink` |
| 品牌渐变 | `Color.brandGradient` |
| 背景色 | `Color.Background.app` / `Color.Background.card` |
| 文字色 | `Color.Text.primary` / `Color.Text.secondary` / `Color.Text.tertiary` / `Color.Text.quaternary` / `Color.Text.inverse` |
| 状态色 | `Color.Status.success` / `Color.Status.warning` / `Color.Status.error` / `Color.Status.info` |
| 叠加层 | `Color.Overlay.scrim` |
| 运行时十六进制（数据恢复） | `Color.dynamicHex(_:)` |
| 透明色（例外） | `Color.clear` |

### 违规写法（全部禁止）

- 显式系统色：`Color.red`、`Color.secondary`、`Color.primary`、`Color.gray`、`Color.accentColor` 等
- `Color(...)` 构造系统色：`Color(uiColor:)`、`Color(nsColor:)`、`Color(.systemBackground)` 等
- 隐式简写系统色：
  - `.foregroundStyle(.secondary)`
  - `.fill(.green)`
  - `.background(.blue)`
  - `.tint(.orange)`
  - `.stroke(.quaternary)`
  - `.strokeBorder(.secondary)`

### 备注

- `Material`（如 `.ultraThinMaterial`）不属于 `Color`，可按组件语义使用
- 需要新颜色时，先在 `Color+Brand.swift` 增加，再在业务代码引用

## 间距规范

使用 `Brand/Spacing+Brand.swift` 中定义的间距常量：

| 用途 | 常量 | 值 |
|------|------|----|
| 卡片内边距 | `BrandSpacing.cardPadding` | 22pt |
| 卡片内部元素间距 | `BrandSpacing.cardContent` | 16pt |
| Section 间距 | `BrandSpacing.section` | 16pt |
| 根页面水平内边距 | `BrandSpacing.pageHorizontal` | 20pt |
| 紧凑间距 | `BrandSpacing.compact` | 8pt |

## 字体规范

使用 `Brand/Font+Brand.swift` 中定义的自定义字体：

| 字体 | 用法 | 适用场景 |
|------|------|----------|
| 字魂大黑 | `.font(.zhdh(size: 24))` | 标题、强调文字 |
| 演示白菜体 | `.font(.slidefontBC(size: 20))` | 手写风格 |
| 思源柔黑 Bold | `.font(.genJyuuGothic(size: 18))` | 圆润标题 |
