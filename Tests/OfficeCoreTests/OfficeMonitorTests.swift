import XCTest
@testable import OfficeCore

private final class StaticUsage: ProcessUsageSource {
    var table: [Int32: ProcessUsage] = [:]
    func usage(pid: Int32) -> ProcessUsage? { table[pid] }
}

private struct StaticPinger: AppPinger {
    var hung: Set<Int32> = []
    func ping(pid: Int32) -> PingResult { hung.contains(pid) ? .timedOut : .responsive }
}

final class OfficeMonitorTests: XCTestCase {
    private let gb: UInt64 = 1024 * 1024 * 1024
    /// 一间收留 Dock app 的小办公室，访达坐第一个
    private let dockRoom = ResolvedRooms(offices: [], rooms: [
        .init(name: "Dock", apps: [DockApp(bundleID: "com.apple.finder", name: "Finder", url: nil)], collectsDock: true),
    ])

    func testTickResolvesEveryEmployee() {
        let usage = StaticUsage()
        usage.table = [
            10: ProcessUsage(cpuNanos: 0, memoryBytes: 50 * 1_048_576),
            11: ProcessUsage(cpuNanos: 0, memoryBytes: 3 * gb),
            12: ProcessUsage(cpuNanos: 0, memoryBytes: 1),
        ]
        let monitor = OfficeMonitor(
            sampler: ActivitySampler(source: usage, family: nil, clock: { 1 }),
            hangDetector: HangDetector(pinger: StaticPinger(hung: [12]), threshold: 1),
            isOnline: { true },
            networkedPIDs: { [] })
        let dock = [
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil),
            DockApp(bundleID: "com.apple.Notes", name: "Notes", url: nil),
        ]
        let launched = Date(timeIntervalSince1970: 1_791_900_000)
        let running = [
            AppProcess(bundleID: "com.apple.finder", name: "访达", pid: 10, launchDate: launched, isActive: true),
            AppProcess(bundleID: "com.apple.Notes", name: "Notes", pid: 11),
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 12),
        ]
        let snap = monitor.tick(dock: dock, rooms: dockRoom, running: running)
        XCTAssertEqual(snap.rooms.map(\.name), ["大办公室", "Dock"])
        XCTAssertEqual(snap.roster.map(\.id), ["com.apple.finder", "com.apple.Safari", "com.apple.Notes", "com.example.Temp"])
        // Safari 没开，也查不到用过：去休闲区
        XCTAssertEqual(snap.statuses.map(\.state), [.focused, .resting, .snacking, .hung])
        XCTAssertEqual(snap.statuses[0].memMB, 50)
        XCTAssertEqual(snap.statuses[0].launchedAt, 1_791_900_000)
        XCTAssertEqual(snap.network, .online)
        XCTAssertTrue(snap.hangDetectionAvailable)
    }

    func testSkippingHangDetectionMarksNobodyHung() {
        let usage = StaticUsage()
        usage.table = [12: ProcessUsage(cpuNanos: 0, memoryBytes: 1)]
        let monitor = OfficeMonitor(
            sampler: ActivitySampler(source: usage, family: nil, clock: { 1 }),
            hangDetector: HangDetector(pinger: StaticPinger(hung: [12]), threshold: 1),
            isOnline: { true },
            networkedPIDs: { [] })
        let running = [AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 12)]
        let snap = monitor.tick(dock: [], running: running, detectHangs: false)
        let temp = snap.statuses.first { $0.id == "com.example.Temp" }
        XCTAssertNotNil(temp)
        XCTAssertNotEqual(temp?.state, .hung)
        XCTAssertTrue(snap.hangDetectionAvailable)
        // 恢复检测后照常发现卡住
        let resumed = monitor.tick(dock: [], running: running)
        XCTAssertEqual(resumed.statuses.first { $0.id == "com.example.Temp" }?.state, .hung)
    }

    func testOfflineUsesNetworkedSet() {
        let usage = StaticUsage()
        usage.table = [10: ProcessUsage(cpuNanos: 0, memoryBytes: 1), 11: ProcessUsage(cpuNanos: 0, memoryBytes: 1)]
        let monitor = OfficeMonitor(
            sampler: ActivitySampler(source: usage, family: nil, clock: { 1 }),
            hangDetector: HangDetector(pinger: StaticPinger()),
            isOnline: { false },
            networkedPIDs: { [11] })
        let running = [
            AppProcess(bundleID: "com.apple.finder", name: "Finder", pid: 10),
            AppProcess(bundleID: "com.example.Chat", name: "Chat", pid: 11),
        ]
        let snap = monitor.tick(dock: [], running: running)
        XCTAssertEqual(snap.statuses.map(\.state), [.idle, .offline])
        XCTAssertEqual(snap.network, .offline)
    }

    func testUnknownNetworkedSetMeansEveryoneGoesToGym() {
        let usage = StaticUsage()
        usage.table = [10: ProcessUsage(cpuNanos: 0, memoryBytes: 1)]
        let monitor = OfficeMonitor(
            sampler: ActivitySampler(source: usage, family: nil, clock: { 1 }),
            hangDetector: HangDetector(pinger: StaticPinger()),
            isOnline: { false },
            networkedPIDs: { nil })
        let snap = monitor.tick(dock: [], running: [AppProcess(bundleID: "com.apple.finder", name: "Finder", pid: 10)])
        XCTAssertEqual(snap.statuses.map(\.state), [.offline])
    }

    func testDuplicateBundleIDsUseFirstProcess() {
        let usage = StaticUsage()
        usage.table = [20: ProcessUsage(cpuNanos: 0, memoryBytes: 1), 21: ProcessUsage(cpuNanos: 0, memoryBytes: 1)]
        let monitor = OfficeMonitor(
            sampler: ActivitySampler(source: usage, family: nil, clock: { 1 }),
            hangDetector: HangDetector(pinger: StaticPinger(hung: [21]), threshold: 1),
            isOnline: { true },
            networkedPIDs: { [] })
        let running = [
            AppProcess(bundleID: "com.example.Dup", name: "Dup", pid: 20),
            AppProcess(bundleID: "com.example.Dup", name: "Dup", pid: 21),
        ]
        let snap = monitor.tick(dock: [], running: running)
        XCTAssertEqual(snap.roster.filter { $0.id == "com.example.Dup" }.count, 1)
        let dup = snap.statuses.filter { $0.id == "com.example.Dup" }
        XCTAssertEqual(dup.count, 1)
        XCTAssertNotEqual(dup.first?.state, .hung)
    }

    func testClosedAppsRestOnlyWhenLongUnused() {
        let usage = StaticUsage()
        usage.table = [10: ProcessUsage(cpuNanos: 0, memoryBytes: 1)]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 24 * 3600
        let lastUsed: [String: Date] = ["Recent.app": now - 2 * day, "Old.app": now - 8 * day]
        var today = now
        let monitor = OfficeMonitor(
            sampler: ActivitySampler(source: usage, family: nil, clock: { 1 }),
            hangDetector: HangDetector(pinger: StaticPinger()),
            isOnline: { true },
            networkedPIDs: { [] },
            usage: UsageTracker(lastUsedOf: { lastUsed[$0.lastPathComponent] }),
            date: { today })
        let dock = [
            DockApp(bundleID: "com.example.Recent", name: "Recent", url: URL(fileURLWithPath: "/Applications/Recent.app")),
            DockApp(bundleID: "com.example.Old", name: "Old", url: URL(fileURLWithPath: "/Applications/Old.app")),
            DockApp(bundleID: "com.example.Never", name: "Never", url: URL(fileURLWithPath: "/Applications/Never.app")),
        ]
        let state = { (snap: OfficeSnapshot, id: String) in snap.statuses.first { $0.id == id }?.state }
        // 开着的 Old：AppOffice 记住刚见过它
        let first = monitor.tick(dock: dock, rooms: dockRoom, running: [AppProcess(bundleID: "com.example.Old", name: "Old", pid: 10)])
        XCTAssertEqual(state(first, "com.example.Recent"), .off)
        XCTAssertEqual(state(first, "com.example.Never"), .resting)
        XCTAssertEqual(state(first, "com.example.Old"), .idle)
        // 关掉以后还在摸鱼，不去休闲区
        let closed = monitor.tick(dock: dock, rooms: dockRoom, running: [])
        XCTAssertEqual(state(closed, "com.example.Old"), .off)
        // 8 天后才去
        today = now + 8 * day
        XCTAssertEqual(state(monitor.tick(dock: dock, rooms: dockRoom, running: []), "com.example.Old"), .resting)
    }

    func testIsAliveForOwnProcess() {
        XCTAssertTrue(WorkspaceAppsSource.isAlive(pid: getpid()))
    }

    func testIsAliveRejectsNonPositive() {
        XCTAssertFalse(WorkspaceAppsSource.isAlive(pid: -1))
        XCTAssertFalse(WorkspaceAppsSource.isAlive(pid: 0))
    }

    func testIsAliveRejectsExitedProcess() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try p.run()
        p.waitUntilExit()
        XCTAssertFalse(WorkspaceAppsSource.isAlive(pid: p.processIdentifier))
    }
}
