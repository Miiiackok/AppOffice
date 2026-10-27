import AppKit
import Foundation

public protocol RunningAppsSource {
    func runningApps() -> [AppProcess]
}

/// 系统里正在运行的普通 app（有 Dock 图标的那种），排除自己
public struct WorkspaceAppsSource: RunningAppsSource {
    public init() {}

    /// 被系统自动终止的 app 还留在运行列表里，pid 是 -1 或已经不存在
    static func isAlive(pid: Int32) -> Bool { pid > 0 && (kill(pid, 0) == 0 || errno == EPERM) }

    /// 在主线程调用：NSWorkspace 靠主 run loop 更新运行列表
    public func runningApps() -> [AppProcess] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  app.processIdentifier != me, Self.isAlive(pid: app.processIdentifier) else { return nil }
            return AppProcess(bundleID: id, name: app.localizedName ?? id, pid: app.processIdentifier,
                              bundleURL: app.bundleURL, launchDate: app.launchDate,
                              isFinishedLaunching: app.isFinishedLaunching, isActive: app.isActive)
        }
    }
}

public struct OfficeSnapshot: Equatable, Sendable {
    /// 第 0 间是大办公室那排，之后是小办公室
    public var rooms: [RoomInfo]
    public var roster: [RosterEntry]
    /// 与 roster 一一对应、顺序相同
    public var statuses: [EmployeeStatus]
    public var network: NetworkState
    public var hangDetectionAvailable: Bool

    public init(rooms: [RoomInfo] = [], roster: [RosterEntry], statuses: [EmployeeStatus], network: NetworkState,
                hangDetectionAvailable: Bool) {
        self.rooms = rooms
        self.roster = roster
        self.statuses = statuses
        self.network = network
        self.hangDetectionAvailable = hangDetectionAvailable
    }
}

/// 非线程安全：tick 只在同一个串行队列上调
public final class OfficeMonitor {
    private let sampler: ActivitySampler
    private let hangDetector: HangDetector
    private let isOnline: () -> Bool
    private let networkedPIDs: () -> Set<Int32>?
    private let thresholds: Thresholds
    private let work: WorkTracker
    private let usage: UsageTracker
    /// 秒，单调递增
    private let clock: () -> TimeInterval
    /// 墙上时间，和上次使用时间比
    private let date: () -> Date

    public init(sampler: ActivitySampler = ActivitySampler(), hangDetector: HangDetector = HangDetector(),
                isOnline: @escaping () -> Bool, networkedPIDs: @escaping () -> Set<Int32>?,
                thresholds: Thresholds = .default, usage: UsageTracker = UsageTracker(),
                clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                date: @escaping () -> Date = Date.init) {
        self.sampler = sampler
        self.hangDetector = hangDetector
        self.isOnline = isOnline
        self.networkedPIDs = networkedPIDs
        self.thresholds = thresholds
        self.work = WorkTracker(thresholds: thresholds)
        self.usage = usage
        self.clock = clock
        self.date = date
    }

    public convenience init(network: NetworkWatcher) {
        self.init(isOnline: { network.isOnline }, networkedPIDs: { network.networkedPIDs() })
    }

    /// 可能阻塞最多一个 AX 超时（0.5 秒），不要在主线程上调。
    /// detectHangs 为 false 时不 ping，谁都不算卡住，hangDetectionAvailable 沿用上一次的。
    /// rooms 是 rooms.json 对上 app 之后的名单（见 RoomsResolver）
    public func tick(dock: [DockApp], rooms: ResolvedRooms = .empty, running: [AppProcess],
                     detectHangs: Bool = true) -> OfficeSnapshot {
        let (roomInfo, roster) = Roster.merge(rooms: rooms, dock: dock, running: running)
        let byID = Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let pids = byID.values.map(\.pid)
        let metrics = sampler.sample(pids: pids)
        let hung = detectHangs ? hangDetector.update(pids: pids) : []
        let online = isOnline()
        let networked = networkedPIDs()
        let now = clock()
        let today = date()
        work.keep(only: Set(roster.map(\.id)))
        let statuses = roster.map { entry -> EmployeeStatus in
            let process = byID[entry.id]
            let m = process.flatMap { metrics[$0.pid] } ?? .zero
            if process == nil { work.forget(entry.id) } else { usage.sawRunning(entry.id, at: today) }
            let busy = process != nil && work.update(id: entry.id, cpu: m.cpuPercent, at: now)
            let longUnused = process == nil && usage.lastUsed(id: entry.id, url: entry.bundleURL, now: today)
                .map { today.timeIntervalSince($0) > thresholds.restAfterSeconds } ?? true
            let state = StateResolver.resolve(
                process: process, metrics: m,
                isHung: process.map { hung.contains($0.pid) } ?? false,
                isOnline: online,
                isNetworked: process.map { networked?.contains($0.pid) ?? true } ?? false,
                isBusy: busy,
                isLongUnused: longUnused,
                thresholds: thresholds)
            return StateResolver.status(for: entry, process: process, metrics: m, state: state)
        }
        return OfficeSnapshot(rooms: roomInfo, roster: roster, statuses: statuses, network: online ? .online : .offline,
                              hangDetectionAvailable: hangDetector.isAvailable)
    }
}
