# Swift Project Template

Swift 项目模板仓库。通过 GitHub Issue Forms 记录产品与技术决策，每个 Issue 对应一个独立的决策领域，Issue 的 open/closed 状态即开发进度。

## 使用方式

1. 点击 **Use this template** 创建新仓库
2. 在新仓库中进入 **Actions → 初始化 PRD Issues → Run workflow**，一键创建全部 PRD Issue
3. 打开各个 Issue，编辑填写决策选项和实施清单
4. 功能开发完成后关闭对应 Issue

> 也可以手动通过 Issues → New Issue 从模板逐个创建。

## Issue 模板列表

| 模板 | 分类 | 说明 |
|------|------|------|
| 产品概述 | PRD | 项目名称、描述、平台、版本、分发方式 |
| 数据持久化方案 | 基础 | SwiftData + iCloud / Supabase / Core Data |
| 多语言支持 | 扩展 | 语言选择与 String Catalogs 实施 |
| 内购 | 增强 | RevenueCat 内购方案与价格设置 |
| 版本更新提示 | 增强 | App Store / Sparkle / GitHub Release |
| 反馈渠道 | 增强 | GitHub Issues / 应用内表单 / 邮件 |
| Onboarding 引导流程 | 增强 | TipKit / 全屏引导页 |
| 推送通知 | 增强 | 本地通知 / 远程推送 |

## 每个 Issue 的标准结构

- **说明** — 该领域的背景介绍和可选方案
- **当前项目选择** — 下拉选择具体方案
- **实施清单** — 勾选式 TODO，跟踪开发进度
- **备注** — 补充说明

## 法律文档

| 文档 | 链接 |
|------|------|
| 用户协议（EULA） | [Apple Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) |
| 隐私政策 | [隐私政策](https://cats-lead-ll1.craft.me/fcFpKKe0ciczOi) |

> 需在 App 内（如登录等页面）及 App Store Connect「描述」底部添加以上链接 —— 中国区审核强制要求。
