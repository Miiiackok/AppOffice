import Foundation

public enum NettopParser {
    /// pid → 累计收发字节数
    public static func parse(_ csv: String) -> [Int32: UInt64] {
        var result: [Int32: UInt64] = [:]
        for line in csv.split(whereSeparator: \.isNewline) {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3,
                  let dot = cols[0].lastIndex(of: "."),
                  let pid = Int32(cols[0][cols[0].index(after: dot)...]),
                  let bytesIn = UInt64(cols[1]),
                  let bytesOut = UInt64(cols[2]) else { continue }
            result[pid, default: 0] += bytesIn + bytesOut
        }
        return result
    }
}

/// 记录哪些 app 最近有过网络流量（按主进程 pid 记）
public final class TrafficTracker {
    public let window: TimeInterval
    private let owner: (Int32) -> Int32
    /// 按 nettop 里的原始 pid
    private var totals: [Int32: UInt64] = [:]
    /// 按主进程 pid
    private var lastActive: [Int32: Date] = [:]

    public init(window: TimeInterval = 600, owner: @escaping (Int32) -> Int32 = { $0 }) {
        self.window = window
        self.owner = owner
    }

    public func record(_ newTotals: [Int32: UInt64], at now: Date) {
        // 增长按原始 pid 比，算到主进程头上
        for (pid, total) in newTotals where total > (totals[pid] ?? 0) {
            lastActive[owner(pid)] = now
        }
        totals = newTotals
        // nettop -P 只列有打开 socket 的进程，断网一关连接就消失，所以只按时间清理
        lastActive = lastActive.filter { now.timeIntervalSince($0.value) <= window }
    }

    public func activePIDs(at now: Date) -> Set<Int32> {
        Set(lastActive.filter { now.timeIntervalSince($0.value) <= window }.keys)
    }
}
