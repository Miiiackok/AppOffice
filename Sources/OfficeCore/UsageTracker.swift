import CoreServices
import Foundation

/// app 上次用是什么时候：macOS 记的上次使用时间（Spotlight 的 kMDItemLastUsedDate），
/// 再加上 AppOffice 自己最后一次看到它开着的时刻（有的 app 开过 Spotlight 也没记）。非线程安全
public final class UsageTracker {
    private let lastUsedOf: (URL) -> Date?
    private let refresh: TimeInterval
    /// Spotlight 查一次记一阵子，不用每拍都查
    private var cache: [String: (date: Date?, at: Date)] = [:]
    private var seenRunning: [String: Date] = [:]

    public init(refresh: TimeInterval = 60, lastUsedOf: @escaping (URL) -> Date? = UsageTracker.spotlightLastUsed) {
        self.refresh = refresh
        self.lastUsedOf = lastUsedOf
    }

    public func sawRunning(_ id: String, at now: Date) {
        seenRunning[id] = now
    }

    /// nil 表示从没用过（或者 Spotlight 没记、AppOffice 也没见它开过）
    public func lastUsed(id: String, url: URL?, now: Date) -> Date? {
        var spotlight: Date?
        if let hit = cache[id], now.timeIntervalSince(hit.at) < refresh {
            spotlight = hit.date
        } else if let url {
            spotlight = lastUsedOf(url)
            cache[id] = (spotlight, now)
        }
        return [spotlight, seenRunning[id]].compactMap { $0 }.max()
    }

    public static func spotlightLastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
