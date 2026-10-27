import Foundation

public struct Thresholds: Equatable, Sendable {
    /// 后台内存达到这个值就去茶水间
    public var snackMemoryBytes: UInt64 = 2 * 1024 * 1024 * 1024
    /// 最近 workingAverageSeconds 秒的平均 CPU（整个进程家族）达到这个值就算在干活。
    /// 本机实测：闲着的 ChatGPT 5–9%，在跑任务的 Claude 平均约 16%
    public var workingCPUPercent: Double = 12
    public var workingAverageSeconds: TimeInterval = 5
    /// 干过活之后保持这么久：AI 等服务器回复时 CPU 几乎为零，不该算摸鱼
    public var workingHoldSeconds: TimeInterval = 30
    /// 没打开、而且这么久没用过（从没用过也算）就去休闲区
    public var restAfterSeconds: TimeInterval = 7 * 24 * 3600

    public init() {}

    public static let `default` = Thresholds()
}

public enum StateResolver {
    /// 设计文档 2.2 的优先级表，从上往下取第一个成立的
    /// isBusy 来自 WorkTracker：最近在干活；isLongUnused 来自 UsageTracker：很久没用过
    public static func resolve(process: AppProcess?, metrics: ProcessMetrics, isHung: Bool, isOnline: Bool,
                               isNetworked: Bool, isBusy: Bool, isLongUnused: Bool = false,
                               thresholds: Thresholds = .default) -> EmployeeState {
        guard let process else { return isLongUnused ? .resting : .off }
        if isHung { return .hung }
        if !isOnline && isNetworked { return .offline }
        if !process.isFinishedLaunching { return .launching }
        if process.isActive { return .focused }
        if metrics.memoryBytes >= thresholds.snackMemoryBytes { return .snacking }
        if isBusy { return .working }
        return .idle
    }

    public static func status(for entry: RosterEntry, process: AppProcess?, metrics: ProcessMetrics,
                              state: EmployeeState) -> EmployeeStatus {
        guard let process else {
            return EmployeeStatus(id: entry.id, state: state, cpu: 0, memMB: 0, launchedAt: nil)
        }
        return EmployeeStatus(
            id: entry.id,
            state: state,
            cpu: min(100, Int(metrics.cpuPercent.rounded())),
            memMB: Int(metrics.memoryBytes / 1_048_576),
            launchedAt: process.launchDate.map { Int($0.timeIntervalSince1970) })
    }
}

/// 后台干活的判断：最近几秒的平均 CPU 过线就算干活，过线之后再保持一会儿。
/// 前台时也在记，所以切走的那一刻还在干活的 app 直接接着干活。非线程安全
public final class WorkTracker {
    private let thresholds: Thresholds
    private var samples: [String: [(at: TimeInterval, cpu: Double)]] = [:]
    private var lastBusy: [String: TimeInterval] = [:]

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    /// 记一个采样，返回现在算不算在干活
    public func update(id: String, cpu: Double, at now: TimeInterval) -> Bool {
        var list = samples[id, default: []].filter { now - $0.at < thresholds.workingAverageSeconds }
        list.append((now, cpu))
        samples[id] = list
        let average = list.map(\.cpu).reduce(0, +) / Double(list.count)
        if average >= thresholds.workingCPUPercent { lastBusy[id] = now }
        guard let busy = lastBusy[id] else { return false }
        return now - busy <= thresholds.workingHoldSeconds
    }

    /// app 退出了就清掉，下次打开从头算
    public func forget(_ id: String) {
        samples[id] = nil
        lastBusy[id] = nil
    }

    /// 不在名单上的（临时工走了）也清掉
    public func keep(only ids: Set<String>) {
        samples = samples.filter { ids.contains($0.key) }
        lastBusy = lastBusy.filter { ids.contains($0.key) }
    }
}
