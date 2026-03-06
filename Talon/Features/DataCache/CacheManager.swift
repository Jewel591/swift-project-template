// MARK: - 变更日志
// [2026-03-05] 新建 CacheManager 模板，JSON 文件缓存工具，支持 per-user 隔离、原子写入、stale-while-revalidate
//
// 适用场景：使用 Supabase 作为后端服务时的本地数据缓存，提供 cache-then-network 体验。
// 不适用于 SwiftData 项目 —— SwiftData 自带本地持久化和 iCloud 同步，无需额外缓存层。

import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.app",
    category: "CacheManager"
)

// MARK: - Cache Envelope

/// 通用缓存信封，包装任意 Codable 数据
struct CacheEnvelope<T: Codable>: Codable {
    let schemaVersion: Int
    let fetchedAt: Date
    let data: T
}

// MARK: - Cache Key & TTL

/// 缓存键定义（按需添加）
enum CacheKey {
    // static let myData = "my-data"
    // static func perItemData(itemID: String) -> String { "item-\(itemID)" }
}

/// 缓存 TTL 定义（按需添加）
enum CacheTTL {
    // static let myData: TimeInterval = 60 * 60           // 1h
    // static let perItemData: TimeInterval = 10 * 60      // 10min
}

// MARK: - Cache Result

/// stale-while-revalidate 语义：返回缓存数据 + 是否过期标记
struct CacheResult<T> {
    let data: T
    let isStale: Bool
}

// MARK: - CacheManager

/// JSON 文件缓存管理器
///
/// 设计原则：
/// - per-user 隔离：缓存目录按 userId 分隔
/// - 原子写入：使用 `.atomic` 选项，内部 tmp + rename，并发安全
/// - stale-while-revalidate：返回缓存数据 + isStale 标记，调用方决定是否后台刷新
/// - fire-and-forget 写入：写缓存在后台线程异步执行，不阻塞主线程
/// - 同步读取：缓存文件通常很小，主线程同步读取可接受
///
/// 使用示例：
/// ```swift
/// // 写入缓存
/// CacheManager.write(myData, key: CacheKey.myData, userId: userId)
///
/// // 读取缓存（stale-while-revalidate）
/// if let cached = CacheManager.read(MyData.self, key: CacheKey.myData, userId: userId, ttl: CacheTTL.myData) {
///     data = cached.data          // 立即使用缓存数据
///     if !cached.isStale { return } // 未过期则跳过网络请求
///     // 已过期则继续后台刷新
/// }
/// ```
enum CacheManager {

    private static let schemaVersion = 1
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Directory

    /// 返回当前用户的缓存目录 URL（不创建目录）
    private static func cacheDirectoryURL(for userId: String) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Talon/Cache", isDirectory: true)
            .appendingPathComponent(userId.lowercased(), isDirectory: true)
    }

    /// 确保缓存目录存在，不存在则创建并标记 isExcludedFromBackup（仅写入时调用）
    private static func ensureCacheDirectory(for userId: String) throws -> URL {
        let base = cacheDirectoryURL(for: userId)
        if !FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.createDirectory(
                at: base, withIntermediateDirectories: true
            )
            var mutableURL = base
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try mutableURL.setResourceValues(resourceValues)
            logger.debug("缓存目录已创建: \(base.path)")
        }
        return base
    }

    // MARK: - Write (atomic, fire-and-forget)

    static func write<T: Codable>(_ value: T, key: String, userId: String) {
        Task.detached(priority: .utility) {
            do {
                let dir = try ensureCacheDirectory(for: userId)
                let target = dir.appendingPathComponent("\(key).json")

                let envelope = CacheEnvelope(
                    schemaVersion: schemaVersion,
                    fetchedAt: Date(),
                    data: value
                )
                let data = try encoder.encode(envelope)
                // .atomic 内部使用系统临时文件 + rename，天然并发安全
                try data.write(to: target, options: .atomic)

                logger.debug("缓存写入成功: \(key)")
            } catch {
                logger.error("缓存写入失败: \(key) — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Read (synchronous)

    /// 读取缓存，返回 CacheResult（含 isStale 标记）；缓存不存在或解码失败返回 nil
    static func read<T: Codable>(_ type: T.Type, key: String, userId: String, ttl: TimeInterval) -> CacheResult<T>? {
        let dir = cacheDirectoryURL(for: userId)
        let file = dir.appendingPathComponent("\(key).json")

        guard FileManager.default.fileExists(atPath: file.path) else { return nil }

        do {
            let data = try Data(contentsOf: file)
            let envelope = try decoder.decode(CacheEnvelope<T>.self, from: data)

            guard envelope.schemaVersion == schemaVersion else {
                logger.warning("缓存 schema 版本不匹配，丢弃: \(key)")
                try? FileManager.default.removeItem(at: file)
                return nil
            }

            let age = Date().timeIntervalSince(envelope.fetchedAt)
            let isStale = age > ttl
            logger.debug("缓存命中: \(key), age=\(Int(age))s, stale=\(isStale)")
            return CacheResult(data: envelope.data, isStale: isStale)
        } catch {
            logger.error("缓存读取/解码失败，丢弃: \(key) — \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }

    // MARK: - Invalidate

    /// 清除指定缓存文件
    static func invalidate(key: String, userId: String) {
        let file = cacheDirectoryURL(for: userId).appendingPathComponent("\(key).json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.removeItem(at: file)
            logger.debug("缓存已清除: \(key)")
        } catch {
            logger.error("缓存清除失败: \(key) — \(error.localizedDescription)")
        }
    }

    /// 清除指定用户的所有缓存
    static func invalidateAll(userId: String) {
        let dir = cacheDirectoryURL(for: userId)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.removeItem(at: dir)
            logger.info("用户缓存已全部清除: \(userId)")
        } catch {
            logger.error("用户缓存清除失败: \(userId) — \(error.localizedDescription)")
        }
    }
}
