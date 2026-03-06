//
//  Font+Brand.swift
//  HeyCoffee
//
//  自定义字体便捷方法
//
//  ## 使用方式
//  ```swift
//  Text("BodyWatch")
//      .font(.zhdh(size: 24))
//  ```
//
//  ## 变更日志
//  - 2026-02-03: 创建文件，添加 zhdh 和 slidefontBC 字体便捷方法
//  - 2026-02-06: 添加 genJyuuGothic（思源柔黑 Bold）字体便捷方法
//

import SwiftUI

extension Font {
    /// 字魂大黑 - 适合标题、强调文字
    static func zhdh(size: CGFloat) -> Font {
        .custom("ZHDH-Heavy", size: size)
    }

    /// 演示白菜体 - 手写风格
    static func slidefontBC(size: CGFloat) -> Font {
        .custom("SlidefontBC", size: size)
    }

    /// 思源柔黑 Bold - 圆润标题字体
    static func genJyuuGothic(size: CGFloat) -> Font {
        .custom("GenJyuuGothic-Bold", size: size)
    }
}
