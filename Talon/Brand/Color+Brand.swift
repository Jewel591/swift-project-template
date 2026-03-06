//
//  Color+Brand.swift
//  HeyCoffee
//
//  品牌色定义
//
//  ## 组件说明
//  将 ColorPalette 中定义的颜色映射到 Color 扩展，
//  提供统一的颜色访问接口。
//
//  ## 使用方式
//  ```swift
//  Text("Hello").foregroundStyle(Color.brand)
//  Circle().fill(Color.brandOrange)
//  ```
//
//  ## 切换颜色集
//  修改 CurrentPalette 类型别名即可切换整个 App 的颜色集：
//  ```swift
//  private typealias CurrentPalette = HeyCoffeePalette
//  // private typealias CurrentPalette = StressWatchPalette
//  ```
//
//  ## 变更日志
//  - 2026-02-03: 重构为基于 ColorPalette 协议的颜色系统
//  - 2026-02-03: 添加 brandRed/Orange/Yellow/Green/Teal/Blue/Indigo/Purple/Pink 常用颜色
//  - 2026-02-06: Background 改为从 CurrentBackgroundPalette 读取，支持独立于主色切换背景色
//  - 2026-03-03: 使用 #if canImport 条件编译替换 UIColor，支持 macOS 跨平台
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 颜色集配置（修改这里切换颜色集）

// private typealias CurrentPalette = HeyCoffeePalette
//private typealias CurrentPalette = StressWatchPalette
// private typealias CurrentPalette = GrowPalPalette
private typealias CurrentPalette = WaterTrackerPalette
// private typealias CurrentPalette = iOSSystemPalette // 颜色很深，观感不太好！

// MARK: - 背景色配置（可独立于 CurrentPalette 单独切换）

// private typealias CurrentBackgroundPalette = HeyCoffeePalette
// private typealias CurrentBackgroundPalette = StressWatchPalette
private typealias CurrentBackgroundPalette = GrowPalPalette
//private typealias CurrentBackgroundPalette = WaterTrackerPalette
// private typealias CurrentBackgroundPalette = iOSSystemPalette

// MARK: - 品牌色映射

extension Color {
    /// 品牌主色（OffScreen 应用的主题和标签颜色）
    // static let brand = Color(hex: "5E8FDC") // GrowPal 蓝色
    //     static let brand = Color(hex: "E37C47") // Gentler Streak
    // static let brand = Color(hex: "#5DC092")  // StressWatch
     static let brand = Color(hex: "#6C6FFA")  // 

    /// 品牌色浅色变体（次要按钮背景）
    static let brandLight = brand.opacity(0.15)

    // MARK: - 常用颜色

    /// 品牌红色
    static let brandRed = CurrentPalette.red
    /// 品牌橙色
    static let brandOrange = CurrentPalette.orange
    /// 品牌黄色
    static let brandYellow = CurrentPalette.yellow
    /// 品牌绿色
    static let brandGreen = CurrentPalette.green
    /// 品牌青色
    static let brandTeal = CurrentPalette.teal
    /// 品牌蓝色
    static let brandBlue = CurrentPalette.blue
    /// 品牌靛蓝色
    static let brandIndigo = CurrentPalette.indigo
    /// 品牌紫色
    static let brandPurple = CurrentPalette.purple
    /// 品牌粉色
    static let brandPink = CurrentPalette.pink

    // MARK: - 渐变色

    /// 品牌渐变色（左上角到右下角）
    static let brandGradient = LinearGradient(
        colors: [
            Color(hex: "483633"),
            Color(hex: "2C221E"),
            Color(hex: "0C0B0B"),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 引导/教程场景色
    static let guide = brandOrange

    /// 从十六进制数值创建颜色（供运行时解析存储值使用）
    static func dynamicHex(_ hexValue: UInt) -> Color {
        Color(hex: hexValue)
    }

    // MARK: - 背景色

    enum Background {
        /// App 主背景色
        #if canImport(UIKit)
        static let app = Color(
            uiColor: UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(CurrentBackgroundPalette.appBackgroundDark)
                    : UIColor(CurrentBackgroundPalette.appBackgroundLight)
            }
        )
        #elseif canImport(AppKit)
        static let app = Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(CurrentBackgroundPalette.appBackgroundDark)
                    : NSColor(CurrentBackgroundPalette.appBackgroundLight)
            }
        )
        #endif

        /// 卡片背景色
        #if canImport(UIKit)
        static let card = Color(
            uiColor: UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(CurrentBackgroundPalette.cardBackgroundDark)
                    : UIColor(CurrentBackgroundPalette.cardBackgroundLight)
            }
        )
        #elseif canImport(AppKit)
        static let card = Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(CurrentBackgroundPalette.cardBackgroundDark)
                    : NSColor(CurrentBackgroundPalette.cardBackgroundLight)
            }
        )
        #endif
    }

    // MARK: - 文字颜色

    enum Text {
        /// 主要文字
        static let primary = Color.primary
        /// 次要文字
        static let secondary = Color.secondary
        /// 第三级文字
        #if canImport(UIKit)
        static let tertiary = Color(uiColor: .tertiaryLabel)
        /// 第四级文字/分割线弱强调
        static let quaternary = Color(uiColor: .quaternaryLabel)
        #elseif canImport(AppKit)
        static let tertiary = Color(nsColor: .tertiaryLabelColor)
        /// 第四级文字/分割线弱强调
        static let quaternary = Color(nsColor: .quaternaryLabelColor)
        #endif

        /// 反色文字（用于深色胶囊或实色底按钮）
        static let inverse = Color(hex: "#FFFFFF")
    }

    // MARK: - 状态色

    enum Status {
        static let success = Color.brandGreen
        static let warning = Color.brandOrange
        static let error = Color.brandRed
        static let info = Color.brandBlue
    }

    // MARK: - 叠加层

    enum Overlay {
        static let scrim = Color(hex: "#000000")
    }

}
