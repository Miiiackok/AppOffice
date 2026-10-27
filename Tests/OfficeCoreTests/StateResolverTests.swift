import XCTest
@testable import OfficeCore

final class StateResolverTests: XCTestCase {
    private let gb: UInt64 = 1024 * 1024 * 1024

    private func app(launched: Bool = true, active: Bool = false) -> AppProcess {
        AppProcess(bundleID: "a", name: "A", pid: 1, isFinishedLaunching: launched, isActive: active)
    }

    private func resolve(_ p: AppProcess?, cpu: Double = 0, mem: UInt64 = 0, hung: Bool = false,
                         online: Bool = true, networked: Bool = false, busy: Bool = false) -> EmployeeState {
        StateResolver.resolve(process: p, metrics: ProcessMetrics(cpuPercent: cpu, memoryBytes: mem),
                              isHung: hung, isOnline: online, isNetworked: networked, isBusy: busy)
    }

    func testEachRowOfPriorityTable() {
        XCTAssertEqual(resolve(app(), hung: true), .hung)
        XCTAssertEqual(resolve(app(), online: false, networked: true), .offline)
        XCTAssertEqual(resolve(app(launched: false)), .launching)
        XCTAssertEqual(resolve(app(active: true)), .focused)
        XCTAssertEqual(resolve(app(), mem: 2 * gb), .snacking)
        XCTAssertEqual(resolve(app(), busy: true), .working)
        XCTAssertEqual(resolve(app(), cpu: 90, mem: 2 * gb - 1), .idle)
        XCTAssertEqual(resolve(nil), .off)
        XCTAssertEqual(StateResolver.resolve(process: nil, metrics: .zero, isHung: false, isOnline: true,
                                             isNetworked: false, isBusy: false, isLongUnused: true), .resting)
        // 开着就不管多久没用
        XCTAssertEqual(StateResolver.resolve(process: app(), metrics: .zero, isHung: false, isOnline: true,
                                             isNetworked: false, isBusy: false, isLongUnused: true), .idle)
    }

    func testHigherPriorityWins() {
        // 卡住压过一切
        XCTAssertEqual(resolve(app(launched: false, active: true), cpu: 90, mem: 3 * gb, hung: true,
                               online: false, networked: true), .hung)
        // 断网压过启动中和前台
        XCTAssertEqual(resolve(app(launched: false, active: true), online: false, networked: true), .offline)
        // 启动中压过前台
        XCTAssertEqual(resolve(app(launched: false, active: true)), .launching)
        // 前台压过吃零食和干活
        XCTAssertEqual(resolve(app(active: true), mem: 3 * gb, busy: true), .focused)
        // 吃零食压过后台干活
        XCTAssertEqual(resolve(app(), mem: 3 * gb, busy: true), .snacking)
    }

    func testOfflineOnlyForNetworkedApps() {
        XCTAssertEqual(resolve(app(), online: false, networked: false), .idle)
        XCTAssertEqual(resolve(app(), online: true, networked: true), .idle)
    }

    func testNotRunningIgnoresEverythingElse() {
        XCTAssertEqual(resolve(nil, mem: 3 * gb, hung: true, online: false, networked: true, busy: true), .off)
    }

    func testWorkTrackerAveragesRecentSeconds() {
        let w = WorkTracker()
        // 一秒冲高、其余闲着：5 秒平均 (40 + 0 + 0) / 3 ≈ 13 过线
        XCTAssertTrue(w.update(id: "a", cpu: 40, at: 0))
        // 闲着的 Electron app 一直 8% 左右：不算干活
        for t in 0..<10 { XCTAssertFalse(w.update(id: "b", cpu: 8, at: Double(t))) }
        // 整个家族平均 16%：算干活
        XCTAssertFalse(w.update(id: "c", cpu: 10, at: 0))
        XCTAssertTrue(w.update(id: "c", cpu: 22, at: 1))
    }

    func testWorkTrackerHoldsThirtySecondsAfterLastBusy() {
        let w = WorkTracker()
        XCTAssertTrue(w.update(id: "a", cpu: 30, at: 0))
        // 等服务器回复：CPU 归零。第 1 秒平均 (30 + 0) / 2 还过线，从那时起保持 30 秒
        for t in 1...31 { XCTAssertTrue(w.update(id: "a", cpu: 0, at: Double(t)), "\(t)") }
        XCTAssertFalse(w.update(id: "a", cpu: 0, at: 32))
        // 又忙起来：重新算
        XCTAssertTrue(w.update(id: "a", cpu: 30, at: 40))
    }

    func testWorkTrackerForgets() {
        let w = WorkTracker()
        XCTAssertTrue(w.update(id: "a", cpu: 30, at: 0))
        w.forget("a")
        XCTAssertFalse(w.update(id: "a", cpu: 0, at: 1))
        XCTAssertTrue(w.update(id: "b", cpu: 30, at: 0))
        w.keep(only: ["a"])
        XCTAssertFalse(w.update(id: "b", cpu: 0, at: 1))
    }

    func testCustomThresholds() {
        var t = Thresholds()
        t.workingCPUPercent = 50
        t.workingHoldSeconds = 0
        let w = WorkTracker(thresholds: t)
        XCTAssertFalse(w.update(id: "a", cpu: 30, at: 0))
        XCTAssertTrue(w.update(id: "a", cpu: 90, at: 1))
        XCTAssertFalse(w.update(id: "a", cpu: 0, at: 10))
    }

    func testStatusRoundsAndCaps() {
        let entry = RosterEntry(id: "a", name: "A", kind: .staff, seat: 0, bundleURL: nil)
        let launch = Date(timeIntervalSince1970: 1_791_900_000.7)
        var p = app()
        p.launchDate = launch
        let s = StateResolver.status(for: entry, process: p,
                                     metrics: ProcessMetrics(cpuPercent: 250.4, memoryBytes: 812 * 1_048_576 + 5),
                                     state: .working)
        XCTAssertEqual(s, EmployeeStatus(id: "a", state: .working, cpu: 100, memMB: 812, launchedAt: 1_791_900_000))
    }

    func testStatusRoundsCPU() {
        let entry = RosterEntry(id: "a", name: "A", kind: .staff, seat: 0, bundleURL: nil)
        func cpu(_ v: Double) -> Int {
            StateResolver.status(for: entry, process: app(), metrics: ProcessMetrics(cpuPercent: v, memoryBytes: 0),
                                 state: .working).cpu
        }
        XCTAssertEqual(cpu(42.6), 43)
        XCTAssertEqual(cpu(42.4), 42)
    }

    func testStatusForNotRunning() {
        let entry = RosterEntry(id: "a", name: "A", kind: .staff, seat: 0, bundleURL: nil)
        let s = StateResolver.status(for: entry, process: nil, metrics: .zero, state: .off)
        XCTAssertEqual(s, EmployeeStatus(id: "a", state: .off, cpu: 0, memMB: 0, launchedAt: nil))
    }
}
