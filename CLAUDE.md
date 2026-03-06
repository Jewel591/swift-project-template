<!-- 格式规范：尽可能减少加粗格式，保持文档简洁易读 -->

# Talon

## 基本信息

- 名称：Talon
- 平台：iOS / macOS (SwiftUI)
- 后端：Supabase
- 数据持久化：SwiftData

## 技术栈

- UI 框架：SwiftUI
- 架构：MVVM
- 最低版本：iOS 18+ / macOS 15+
- 第三方依赖：LayoutUIKit、BrandKit、SupabaseKit、RevenueCatKit、PromoKit

## 产品定位

<!-- 在此描述产品定位 -->

## 核心功能

<!-- 在此描述核心功能 -->

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
