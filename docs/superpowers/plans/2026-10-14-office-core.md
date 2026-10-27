# OfficeCore 实现计划（计划 1/3）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出 AppOffice 的监控核心库 `OfficeCore`，以及一个命令行工具 `officectl`，在终端里每秒刷新显示每个员工（app）的状态。

**Architecture:** `OfficeCore` 是纯 Swift 库：名单合并（Dock + 运行中）、进程 CPU/内存采样、AX 卡顿探测、网络与流量跟踪，最后由纯函数 `StateResolver` 按设计文档 2.2 的优先级表算出每个员工的状态。所有系统依赖都藏在协议后面，单元测试用假实现。`OfficeMonitor` 把各部件串起来，每次 `tick` 返回一个 `OfficeSnapshot`。

**Tech Stack:** Swift 5.9 language mode（工具链 Swift 6.4），SwiftPM，XCTest，AppKit / ApplicationServices / Network / Darwin。macOS 14+。

**设计文档：** `docs/superpowers/specs/2026-10-14-app-office-design.md`

**全部计划：**
1. **本计划**：OfficeCore + officectl
2. web 场景（Three.js + mock 数据，浏览器内可运行）
3. macOS 外壳（菜单栏、浮窗、WebBridge、AppControl），把 1 和 2 接起来

**约定：**
- 所有命令都在仓库根目录 `/Users/mi/Desktop/AppOffice` 下运行。
- 注释用中文，风格简短，与 Clothesline 一致。
- 每个任务结束都提交；提交信息末尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `Package.swift` | 三个 target：`OfficeCore`、`officectl`、`OfficeCoreTests` |
| `Sources/OfficeCore/Models.swift` | 公共数据类型：`EmployeeKind`、`EmployeeState`、`AppProcess`、`ProcessMetrics`、`RosterEntry`、`EmployeeStatus`、`NetworkState` |
| `Sources/OfficeCore/StateResolver.swift` | `Thresholds` + 状态优先级判定 + 生成 `EmployeeStatus` |
| `Sources/OfficeCore/Roster.swift` | `DockApp`、`DockReader`（解析 Dock 配置）、`Roster.merge` |
| `Sources/OfficeCore/DominantColor.swift` | `RGBColor` + 图标主色提取 |
| `Sources/OfficeCore/ActivitySampler.swift` | `ProcessUsageSource` 协议、系统实现（proc_pid_rusage）、`ActivitySampler` 计算 CPU% |
| `Sources/OfficeCore/HangDetector.swift` | `AppPinger` 协议、`AXPinger`、`HangDetector` 连续超时计数 |
| `Sources/OfficeCore/Traffic.swift` | `NettopParser`、`TrafficTracker` |
| `Sources/OfficeCore/NetworkWatcher.swift` | `NWPathMonitor` + 定期运行 nettop |
| `Sources/OfficeCore/StatusDiffer.swift` | 只挑出有变化的员工状态 |
| `Sources/OfficeCore/OfficeMonitor.swift` | `RunningAppsSource` / `WorkspaceAppsSource`、`OfficeSnapshot`、`OfficeMonitor` |
| `Sources/officectl/main.swift` | 终端实时状态表 |
| `Tests/OfficeCoreTests/*.swift` | 每个源文件一份测试 |

---

### Task 0: 包骨架

**Files:**
- Create: `Package.swift`
- Create: `Sources/OfficeCore/Models.swift`
- Create: `Sources/officectl/main.swift`
- Create: `Tests/OfficeCoreTests/ModelsTests.swift`

- [ ] **Step 1: 写 `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppOffice",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OfficeCore"),
        .executableTarget(name: "officectl", dependencies: ["OfficeCore"]),
        .testTarget(name: "OfficeCoreTests", dependencies: ["OfficeCore"]),
    ]
)
```

- [ ] **Step 2: 写失败的测试 `Tests/OfficeCoreTests/ModelsTests.swift`**

```swift
import XCTest
@testable import OfficeCore

final class ModelsTests: XCTestCase {
    func testStatusEncodesProtocolFieldNames() throws {
        let status = EmployeeStatus(id: "com.apple.Safari", state: .focused, cpu: 42, memMB: 812, launchedAt: 1_791_900_000)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as! [String: Any]
        XCTAssertEqual(json["id"] as? String, "com.apple.Safari")
        XCTAssertEqual(json["state"] as? String, "focused")
        XCTAssertEqual(json["cpu"] as? Int, 42)
        XCTAssertEqual(json["memMB"] as? Int, 812)
        XCTAssertEqual(json["launchedAt"] as? Int, 1_791_900_000)
    }

    func testStatusEncodesMissingLaunchAsNull() throws {
        let status = EmployeeStatus(id: "x", state: .off, cpu: 0, memMB: 0, launchedAt: nil)
        let text = String(decoding: try JSONEncoder().encode(status), as: UTF8.self)
        XCTAssertTrue(text.contains("\"launchedAt\":null"), text)
    }
}
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `swift test --filter ModelsTests`
Expected: 编译失败，提示 `cannot find 'EmployeeStatus' in scope`

- [ ] **Step 4: 写 `Sources/OfficeCore/Models.swift`**

```swift
import Foundation

public enum EmployeeKind: String, Codable, Sendable {
    case staff, temp
}

/// 员工状态，顺序即优先级（见设计文档 2.2）
public enum EmployeeState: String, Codable, Sendable, CaseIterable {
    case hung, offline, launching, focused, snacking, working, idle, off
}

/// 一个正在运行的普通 app 的快照
public struct AppProcess: Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public var pid: Int32
    public var bundleURL: URL?
    public var launchDate: Date?
    public var isFinishedLaunching: Bool
    public var isActive: Bool

    public init(bundleID: String, name: String, pid: Int32, bundleURL: URL? = nil, launchDate: Date? = nil,
                isFinishedLaunching: Bool = true, isActive: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
        self.bundleURL = bundleURL
        self.launchDate = launchDate
        self.isFinishedLaunching = isFinishedLaunching
        self.isActive = isActive
    }
}

public struct ProcessMetrics: Equatable, Sendable {
    /// 占单核的百分比，可以超过 100
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(cpuPercent: Double, memoryBytes: UInt64) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    public static let zero = ProcessMetrics(cpuPercent: 0, memoryBytes: 0)
}

/// 名单上的一个员工：正式员工有固定工位 seat，临时工 seat 为 nil
public struct RosterEntry: Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: EmployeeKind
    public var seat: Int?
    public var bundleURL: URL?

    public init(id: String, name: String, kind: EmployeeKind, seat: Int?, bundleURL: URL?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.seat = seat
        self.bundleURL = bundleURL
    }
}

/// 每秒推给网页的状态（字段名即协议字段名）
public struct EmployeeStatus: Codable, Equatable, Sendable {
    public var id: String
    public var state: EmployeeState
    /// 封顶 100
    public var cpu: Int
    public var memMB: Int
    /// 启动时间，Unix 秒；未运行为 nil
    public var launchedAt: Int?

    public init(id: String, state: EmployeeState, cpu: Int, memMB: Int, launchedAt: Int?) {
        self.id = id
        self.state = state
        self.cpu = cpu
        self.memMB = memMB
        self.launchedAt = launchedAt
    }

    // 默认合成的编码会跳过 nil，协议要求显式 null
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(state, forKey: .state)
        try c.encode(cpu, forKey: .cpu)
        try c.encode(memMB, forKey: .memMB)
        try c.encode(launchedAt, forKey: .launchedAt)
    }
}

public enum NetworkState: String, Codable, Sendable {
    case online, offline
}
```

- [ ] **Step 5: 写占位的 `Sources/officectl/main.swift`**（Task 10 会替换）

```swift
import OfficeCore

print("officectl")
```

- [ ] **Step 6: 运行测试，确认通过**

Run: `swift test --filter ModelsTests`
Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 7: 提交**

```bash
git add Package.swift Sources Tests
git commit -m "feat: OfficeCore package skeleton and models

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: StateResolver

**Files:**
- Create: `Sources/OfficeCore/StateResolver.swift`
- Test: `Tests/OfficeCoreTests/StateResolverTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import OfficeCore

final class StateResolverTests: XCTestCase {
    private let gb: UInt64 = 1024 * 1024 * 1024

    private func app(launched: Bool = true, active: Bool = false) -> AppProcess {
        AppProcess(bundleID: "a", name: "A", pid: 1, isFinishedLaunching: launched, isActive: active)
    }

    private func resolve(_ p: AppProcess?, cpu: Double = 0, mem: UInt64 = 0, hung: Bool = false,
                         online: Bool = true, networked: Bool = false) -> EmployeeState {
        StateResolver.resolve(process: p, metrics: ProcessMetrics(cpuPercent: cpu, memoryBytes: mem),
                              isHung: hung, isOnline: online, isNetworked: networked)
    }

    func testEachRowOfPriorityTable() {
        XCTAssertEqual(resolve(app(), hung: true), .hung)
        XCTAssertEqual(resolve(app(), online: false, networked: true), .offline)
        XCTAssertEqual(resolve(app(launched: false)), .launching)
        XCTAssertEqual(resolve(app(active: true)), .focused)
        XCTAssertEqual(resolve(app(), mem: 2 * gb), .snacking)
        XCTAssertEqual(resolve(app(), cpu: 20), .working)
        XCTAssertEqual(resolve(app(), cpu: 19.9, mem: 2 * gb - 1), .idle)
        XCTAssertEqual(resolve(nil), .off)
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
        XCTAssertEqual(resolve(app(active: true), cpu: 90, mem: 3 * gb), .focused)
        // 吃零食压过后台干活
        XCTAssertEqual(resolve(app(), cpu: 90, mem: 3 * gb), .snacking)
    }

    func testOfflineOnlyForNetworkedApps() {
        XCTAssertEqual(resolve(app(), online: false, networked: false), .idle)
        XCTAssertEqual(resolve(app(), online: true, networked: true), .idle)
    }

    func testNotRunningIgnoresEverythingElse() {
        XCTAssertEqual(resolve(nil, cpu: 90, mem: 3 * gb, hung: true, online: false, networked: true), .off)
    }

    func testCustomThresholds() {
        var t = Thresholds()
        t.workingCPUPercent = 50
        let state = StateResolver.resolve(process: app(), metrics: ProcessMetrics(cpuPercent: 30, memoryBytes: 0),
                                          isHung: false, isOnline: true, isNetworked: false, thresholds: t)
        XCTAssertEqual(state, .idle)
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

    func testStatusForNotRunning() {
        let entry = RosterEntry(id: "a", name: "A", kind: .staff, seat: 0, bundleURL: nil)
        let s = StateResolver.status(for: entry, process: nil, metrics: .zero, state: .off)
        XCTAssertEqual(s, EmployeeStatus(id: "a", state: .off, cpu: 0, memMB: 0, launchedAt: nil))
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter StateResolverTests`
Expected: 编译失败，`cannot find 'StateResolver' in scope`

- [ ] **Step 3: 写 `Sources/OfficeCore/StateResolver.swift`**

```swift
import Foundation

public struct Thresholds: Equatable, Sendable {
    /// 后台内存达到这个值就去茶水间
    public var snackMemoryBytes: UInt64 = 2 * 1024 * 1024 * 1024
    /// 后台 CPU 达到这个值就算在干活
    public var workingCPUPercent: Double = 20

    public init() {}

    public static let `default` = Thresholds()
}

public enum StateResolver {
    /// 设计文档 2.2 的优先级表，从上往下取第一个成立的
    public static func resolve(process: AppProcess?, metrics: ProcessMetrics, isHung: Bool, isOnline: Bool,
                               isNetworked: Bool, thresholds: Thresholds = .default) -> EmployeeState {
        guard let process else { return .off }
        if isHung { return .hung }
        if !isOnline && isNetworked { return .offline }
        if !process.isFinishedLaunching { return .launching }
        if process.isActive { return .focused }
        if metrics.memoryBytes >= thresholds.snackMemoryBytes { return .snacking }
        if metrics.cpuPercent >= thresholds.workingCPUPercent { return .working }
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
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter StateResolverTests`
Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add Sources/OfficeCore/StateResolver.swift Tests/OfficeCoreTests/StateResolverTests.swift
git commit -m "feat: StateResolver priority table

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Roster 与 DockReader

Dock 配置结构（已在本机验证）：`persistent-apps` 是数组，每项形如
`{"tile-data": {"bundle-identifier": "com.apple.Safari", "file-label": "Safari", "file-data": {"_CFURLString": "file:///Applications/Safari.app/"}}}`。
访达不在这个列表里，但永远在运行，固定为 0 号工位。

**Files:**
- Create: `Sources/OfficeCore/Roster.swift`
- Test: `Tests/OfficeCoreTests/RosterTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import OfficeCore

final class RosterTests: XCTestCase {
    private func tile(_ id: String, _ label: String, _ url: String) -> [String: Any] {
        ["tile-data": ["bundle-identifier": id, "file-label": label, "file-data": ["_CFURLString": url]]]
    }

    func testParseDockTiles() {
        let raw: [[String: Any]] = [
            tile("com.apple.Safari", "Safari", "file:///Applications/Safari.app/"),
            ["tile-data": ["file-label": "没有 bundle id 的项"]],
            ["tile-type": "spacer-tile"],
            ["tile-data": ["bundle-identifier": "com.example.NoLabel"]],
        ]
        XCTAssertEqual(DockReader.parse(raw), [
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: URL(string: "file:///Applications/Safari.app/")),
            DockApp(bundleID: "com.example.NoLabel", name: "com.example.NoLabel", url: nil),
        ])
    }

    func testMergeStaffThenTemps() {
        let dock = [
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil),
            DockApp(bundleID: "com.apple.Notes", name: "Notes", url: nil),
        ]
        let running = [
            AppProcess(bundleID: "com.apple.finder", name: "访达", pid: 10),
            AppProcess(bundleID: "com.apple.Notes", name: "备忘录", pid: 11),
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 12),
        ]
        let roster = Roster.merge(dock: dock, running: running)
        XCTAssertEqual(roster.map(\.id), ["com.apple.finder", "com.apple.Safari", "com.apple.Notes", "com.example.Temp"])
        XCTAssertEqual(roster.map(\.kind), [.staff, .staff, .staff, .temp])
        XCTAssertEqual(roster.map(\.seat), [0, 1, 2, nil])
        // 访达用运行中的本地化名字，Dock 里的员工用 Dock 上的名字
        XCTAssertEqual(roster.map(\.name), ["访达", "Safari", "Notes", "Temp"])
    }

    func testFinderNotDuplicatedWhenInDock() {
        let dock = [DockApp(bundleID: "com.apple.finder", name: "Finder", url: nil)]
        let roster = Roster.merge(dock: dock, running: [])
        XCTAssertEqual(roster.map(\.id), ["com.apple.finder"])
        XCTAssertEqual(roster[0].name, "Finder")
    }

    func testDuplicatesCollapse() {
        let dock = [
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil),
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil),
        ]
        let running = [
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 1),
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 2),
        ]
        XCTAssertEqual(Roster.merge(dock: dock, running: running).map(\.id),
                       ["com.apple.finder", "com.apple.Safari", "com.example.Temp"])
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter RosterTests`
Expected: 编译失败，`cannot find 'DockReader' in scope`

- [ ] **Step 3: 写 `Sources/OfficeCore/Roster.swift`**

```swift
import Foundation

public struct DockApp: Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public var url: URL?

    public init(bundleID: String, name: String, url: URL?) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
    }
}

public enum DockReader {
    public static func parse(_ persistentApps: [[String: Any]]) -> [DockApp] {
        persistentApps.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let id = data["bundle-identifier"] as? String else { return nil }
            let urlString = (data["file-data"] as? [String: Any])?["_CFURLString"] as? String
            return DockApp(bundleID: id, name: data["file-label"] as? String ?? id,
                           url: urlString.flatMap(URL.init(string:)))
        }
    }

    /// 读当前用户 Dock 里固定的 app
    public static func load() -> [DockApp] {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let raw = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] ?? []
        return parse(raw)
    }
}

public enum Roster {
    public static let finderID = "com.apple.finder"
    static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    /// 访达 + Dock 固定 app 是正式员工（按顺序占工位），其余运行中的 app 是临时工
    public static func merge(dock: [DockApp], running: [AppProcess]) -> [RosterEntry] {
        let finderName = running.first { $0.bundleID == finderID }?.name ?? "Finder"
        let finder = DockApp(bundleID: finderID, name: finderName, url: finderURL)
        var seen = Set<String>()
        var result: [RosterEntry] = []
        for app in [finder] + dock.filter({ $0.bundleID != finderID }) where seen.insert(app.bundleID).inserted {
            result.append(RosterEntry(id: app.bundleID, name: app.name, kind: .staff, seat: result.count,
                                      bundleURL: app.url))
        }
        // Dock 里有访达时用 Dock 上的名字
        if let docked = dock.first(where: { $0.bundleID == finderID }) {
            result[0].name = docked.name
        }
        for p in running where seen.insert(p.bundleID).inserted {
            result.append(RosterEntry(id: p.bundleID, name: p.name, kind: .temp, seat: nil, bundleURL: p.bundleURL))
        }
        return result
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter RosterTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add Sources/OfficeCore/Roster.swift Tests/OfficeCoreTests/RosterTests.swift
git commit -m "feat: roster merge with Dock reader

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: DominantColor

算法（设计文档 2.1）：缩到 32×32；跳过 alpha < 128、亮度 < 0.15、饱和度 < 0.15 的像素；按色相分 12 个桶（每桶 30°），每个像素按饱和度加权；取权重最大的桶，返回桶内像素的平均色；没有合格像素时返回 `#9AA5B1`。

**Files:**
- Create: `Sources/OfficeCore/DominantColor.swift`
- Test: `Tests/OfficeCoreTests/DominantColorTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
import CoreGraphics
@testable import OfficeCore

final class DominantColorTests: XCTestCase {
    private func pixels(_ list: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        list.flatMap { [$0.0, $0.1, $0.2, $0.3] }
    }

    func testSolidColor() {
        let px = pixels(Array(repeating: (0x3D, 0x7B, 0xFD, 255), count: 16))
        XCTAssertEqual(DominantColor.fromRGBA(px).hex, "#3D7BFD")
    }

    func testTransparentFallsBack() {
        let px = pixels(Array(repeating: (255, 0, 0, 0), count: 16))
        XCTAssertEqual(DominantColor.fromRGBA(px), DominantColor.fallback)
        XCTAssertEqual(DominantColor.fallback.hex, "#9AA5B1")
    }

    func testBlackWhiteGrayFallsBack() {
        let px = pixels([(0, 0, 0, 255), (255, 255, 255, 255), (128, 128, 128, 255), (10, 12, 11, 255)])
        XCTAssertEqual(DominantColor.fromRGBA(px), DominantColor.fallback)
    }

    func testMajorityHueWins() {
        let blue = Array(repeating: (UInt8(20), UInt8(60), UInt8(220), UInt8(255)), count: 10)
        let red = Array(repeating: (UInt8(220), UInt8(30), UInt8(30), UInt8(255)), count: 3)
        let white = Array(repeating: (UInt8(255), UInt8(255), UInt8(255), UInt8(255)), count: 30)
        XCTAssertEqual(DominantColor.fromRGBA(pixels(blue + red + white)).hex, "#143CDC")
    }

    func testFromCGImage() {
        let size = 64
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0, green: 0.8, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let color = DominantColor.of(ctx.makeImage()!)
        XCTAssertEqual(color.r, 0)
        XCTAssertEqual(Int(color.g), 204, accuracy: 2)
        XCTAssertEqual(Int(color.b), 51, accuracy: 2)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter DominantColorTests`
Expected: 编译失败，`cannot find 'DominantColor' in scope`

- [ ] **Step 3: 写 `Sources/OfficeCore/DominantColor.swift`**

```swift
import CoreGraphics
import Foundation

public struct RGBColor: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

/// 图标主色：衬衫和地毯描边用
public enum DominantColor {
    public static let fallback = RGBColor(r: 0x9A, g: 0xA5, b: 0xB1)
    static let sampleSize = 32

    public static func of(_ image: CGImage) -> RGBColor {
        let n = sampleSize
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                      bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        return drawn ? fromRGBA(px) : fallback
    }

    /// 输入是 RGBA 逐像素排列的字节
    public static func fromRGBA(_ px: [UInt8]) -> RGBColor {
        var weight = [Double](repeating: 0, count: 12)
        var sums = [[Double]](repeating: [0, 0, 0], count: 12)
        var counts = [Double](repeating: 0, count: 12)
        for i in stride(from: 0, to: px.count - 3, by: 4) where px[i + 3] >= 128 {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
            let s = hi == 0 ? 0 : d / hi
            guard hi >= 0.15, s >= 0.15 else { continue }
            var h: Double
            if hi == r { h = (g - b) / d } else if hi == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
            h = (h * 60).truncatingRemainder(dividingBy: 360)
            if h < 0 { h += 360 }
            let k = min(11, Int(h / 30))
            weight[k] += s
            sums[k][0] += Double(px[i]); sums[k][1] += Double(px[i + 1]); sums[k][2] += Double(px[i + 2])
            counts[k] += 1
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return fallback }
        func avg(_ c: Int) -> UInt8 { UInt8((sums[best][c] / counts[best]).rounded()) }
        return RGBColor(r: avg(0), g: avg(1), b: avg(2))
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter DominantColorTests`
Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add Sources/OfficeCore/DominantColor.swift Tests/OfficeCoreTests/DominantColorTests.swift
git commit -m "feat: icon dominant color extraction

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: ActivitySampler

CPU% = 两次采样间进程 CPU 时间增量 ÷ 墙钟时间增量 × 100。某个 pid 第一次出现时没有上一次的数据，CPU 记为 0。
系统实现用 `proc_pid_rusage(RUSAGE_INFO_V4)`：`ri_user_time + ri_system_time` 的单位是 mach tick，要用 `mach_timebase_info` 换算成纳秒（Apple Silicon 上是 125/3）；内存取 `ri_phys_footprint`。已在本机验证能读到同一用户的其他进程。

**Files:**
- Create: `Sources/OfficeCore/ActivitySampler.swift`
- Test: `Tests/OfficeCoreTests/ActivitySamplerTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import OfficeCore

private final class FakeUsage: ProcessUsageSource {
    var table: [Int32: ProcessUsage] = [:]
    func usage(pid: Int32) -> ProcessUsage? { table[pid] }
}

final class ActivitySamplerTests: XCTestCase {
    func testFirstSampleHasZeroCPU() {
        let src = FakeUsage()
        src.table[1] = ProcessUsage(cpuNanos: 5_000_000_000, memoryBytes: 100)
        let sampler = ActivitySampler(source: src, clock: { 1_000_000_000 })
        XCTAssertEqual(sampler.sample(pids: [1]), [1: ProcessMetrics(cpuPercent: 0, memoryBytes: 100)])
    }

    func testCPUPercentFromDeltas() {
        let src = FakeUsage()
        var now: UInt64 = 0
        let sampler = ActivitySampler(source: src, clock: { now })
        src.table[1] = ProcessUsage(cpuNanos: 0, memoryBytes: 1)
        src.table[2] = ProcessUsage(cpuNanos: 0, memoryBytes: 2)
        _ = sampler.sample(pids: [1, 2])
        now = 1_000_000_000
        src.table[1] = ProcessUsage(cpuNanos: 250_000_000, memoryBytes: 1)
        src.table[2] = ProcessUsage(cpuNanos: 1_500_000_000, memoryBytes: 2)
        let m = sampler.sample(pids: [1, 2])
        XCTAssertEqual(m[1]?.cpuPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(m[2]?.cpuPercent ?? -1, 150, accuracy: 0.001)
    }

    func testMissingProcessIsSkippedAndForgotten() {
        let src = FakeUsage()
        var now: UInt64 = 0
        let sampler = ActivitySampler(source: src, clock: { now })
        src.table[1] = ProcessUsage(cpuNanos: 0, memoryBytes: 1)
        _ = sampler.sample(pids: [1])
        now = 1_000_000_000
        src.table[1] = nil
        XCTAssertEqual(sampler.sample(pids: [1]), [:])
        // pid 复用：重新出现时按第一次算
        now = 2_000_000_000
        src.table[1] = ProcessUsage(cpuNanos: 9_000_000_000, memoryBytes: 1)
        XCTAssertEqual(sampler.sample(pids: [1])[1]?.cpuPercent, 0)
    }

    func testCPUTimeGoingBackwardsIsZero() {
        let src = FakeUsage()
        var now: UInt64 = 0
        let sampler = ActivitySampler(source: src, clock: { now })
        src.table[1] = ProcessUsage(cpuNanos: 5_000, memoryBytes: 1)
        _ = sampler.sample(pids: [1])
        now = 1_000_000_000
        src.table[1] = ProcessUsage(cpuNanos: 1_000, memoryBytes: 1)
        XCTAssertEqual(sampler.sample(pids: [1])[1]?.cpuPercent, 0)
    }

    func testSystemSourceReadsOwnProcess() {
        let usage = SystemProcessUsageSource().usage(pid: getpid())
        XCTAssertNotNil(usage)
        XCTAssertGreaterThan(usage?.cpuNanos ?? 0, 0)
        XCTAssertGreaterThan(usage?.memoryBytes ?? 0, 0)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter ActivitySamplerTests`
Expected: 编译失败，`cannot find type 'ProcessUsageSource' in scope`

- [ ] **Step 3: 写 `Sources/OfficeCore/ActivitySampler.swift`**

```swift
import Darwin
import Foundation

public struct ProcessUsage: Equatable, Sendable {
    /// 累计 CPU 时间（用户态 + 内核态）
    public var cpuNanos: UInt64
    public var memoryBytes: UInt64

    public init(cpuNanos: UInt64, memoryBytes: UInt64) {
        self.cpuNanos = cpuNanos
        self.memoryBytes = memoryBytes
    }
}

public protocol ProcessUsageSource {
    func usage(pid: Int32) -> ProcessUsage?
}

public struct SystemProcessUsageSource: ProcessUsageSource {
    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    public init() {}

    public func usage(pid: Int32) -> ProcessUsage? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard rc == 0 else { return nil }
        let tb = Self.timebase
        let ticks = info.ri_user_time + info.ri_system_time
        return ProcessUsage(cpuNanos: ticks * UInt64(tb.numer) / UInt64(tb.denom), memoryBytes: info.ri_phys_footprint)
    }
}

public final class ActivitySampler {
    private let source: ProcessUsageSource
    private let clock: () -> UInt64
    private var last: [Int32: (cpu: UInt64, at: UInt64)] = [:]

    public init(source: ProcessUsageSource = SystemProcessUsageSource(),
                clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.source = source
        self.clock = clock
    }

    /// 读不到的进程不出现在结果里
    public func sample(pids: [Int32]) -> [Int32: ProcessMetrics] {
        let now = clock()
        var result: [Int32: ProcessMetrics] = [:]
        var next: [Int32: (cpu: UInt64, at: UInt64)] = [:]
        for pid in pids {
            guard let u = source.usage(pid: pid) else { continue }
            var cpu = 0.0
            if let prev = last[pid], now > prev.at, u.cpuNanos >= prev.cpu {
                cpu = Double(u.cpuNanos - prev.cpu) / Double(now - prev.at) * 100
            }
            result[pid] = ProcessMetrics(cpuPercent: cpu, memoryBytes: u.memoryBytes)
            next[pid] = (u.cpuNanos, now)
        }
        last = next
        return result
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter ActivitySamplerTests`
Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add Sources/OfficeCore/ActivitySampler.swift Tests/OfficeCoreTests/ActivitySamplerTests.swift
git commit -m "feat: per-process CPU and memory sampler

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: HangDetector

`AXPinger`：对 app 的 AX 元素设 0.5 秒消息超时，读 `kAXRoleAttribute`。
- 返回 `.apiDisabled`（本机未授权时实测为 -25211）→ `.unavailable`
- 返回 `.cannotComplete` 且耗时 ≥ 超时的 90% → `.timedOut`（真卡住）
- 返回 `.cannotComplete` 但很快返回 → `.responsive`（app 本身不支持 AX，不算卡住）
- 其他 → `.responsive`

`HangDetector`：并发 ping 所有 pid；同一 pid 连续 `threshold`（默认 2）次超时才算卡住；任一 ping 返回 `.unavailable` 就把 `isAvailable` 设为 false 并返回空集合。

**Files:**
- Create: `Sources/OfficeCore/HangDetector.swift`
- Test: `Tests/OfficeCoreTests/HangDetectorTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
import AppKit
import XCTest
@testable import OfficeCore

private final class FakePinger: AppPinger, @unchecked Sendable {
    private let lock = NSLock()
    private var table: [Int32: PingResult] = [:]
    func set(_ pid: Int32, _ r: PingResult) { lock.withLock { table[pid] = r } }
    func ping(pid: Int32) -> PingResult { lock.withLock { table[pid] ?? .responsive } }
}

final class HangDetectorTests: XCTestCase {
    func testNeedsConsecutiveTimeouts() {
        let pinger = FakePinger()
        let detector = HangDetector(pinger: pinger, threshold: 2)
        pinger.set(1, .timedOut)
        XCTAssertEqual(detector.update(pids: [1, 2]), [])
        XCTAssertEqual(detector.update(pids: [1, 2]), [1])
        XCTAssertEqual(detector.update(pids: [1, 2]), [1])
        XCTAssertTrue(detector.isAvailable)
    }

    func testRecoveryResetsStrikes() {
        let pinger = FakePinger()
        let detector = HangDetector(pinger: pinger, threshold: 2)
        pinger.set(1, .timedOut)
        _ = detector.update(pids: [1])
        pinger.set(1, .responsive)
        XCTAssertEqual(detector.update(pids: [1]), [])
        pinger.set(1, .timedOut)
        XCTAssertEqual(detector.update(pids: [1]), [])
    }

    func testForgetsPidsNoLongerPassed() {
        let pinger = FakePinger()
        let detector = HangDetector(pinger: pinger, threshold: 2)
        pinger.set(1, .timedOut)
        _ = detector.update(pids: [1])
        _ = detector.update(pids: [])
        XCTAssertEqual(detector.update(pids: [1]), [])
    }

    func testUnavailableDisablesDetection() {
        let pinger = FakePinger()
        let detector = HangDetector(pinger: pinger, threshold: 1)
        pinger.set(1, .timedOut)
        pinger.set(2, .unavailable)
        XCTAssertEqual(detector.update(pids: [1, 2]), [])
        XCTAssertFalse(detector.isAvailable)
        pinger.set(2, .responsive)
        XCTAssertEqual(detector.update(pids: [1, 2]), [1])
        XCTAssertTrue(detector.isAvailable)
    }

    func testAXPingerOnFinderDoesNotTimeOut() throws {
        // 不能 ping 测试进程自己：主线程被测试占着，会真的超时。访达一直在跑且有响应：
        // 未授权时得到 unavailable，授权时得到 responsive，都不应是 timedOut
        let finder = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        XCTAssertNotEqual(AXPinger().ping(pid: finder.processIdentifier), .timedOut)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter HangDetectorTests`
Expected: 编译失败，`cannot find type 'AppPinger' in scope`

- [ ] **Step 3: 写 `Sources/OfficeCore/HangDetector.swift`**

```swift
import ApplicationServices
import Foundation

public enum PingResult: Equatable, Sendable {
    case responsive, timedOut, unavailable
}

public protocol AppPinger: Sendable {
    func ping(pid: Int32) -> PingResult
}

/// 用辅助功能接口"敲门"，需要辅助功能权限
public struct AXPinger: AppPinger {
    public var timeout: Float

    public init(timeout: Float = 0.5) {
        self.timeout = timeout
    }

    public func ping(pid: Int32) -> PingResult {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        let start = DispatchTime.now().uptimeNanoseconds
        let err = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        switch err {
        case .apiDisabled:
            return .unavailable
        case .cannotComplete:
            // 很快就失败的是不支持 AX 的 app，不是卡住
            return elapsed >= Double(timeout) * 0.9 ? .timedOut : .responsive
        default:
            return .responsive
        }
    }
}

public final class HangDetector {
    private let pinger: AppPinger
    private let threshold: Int
    private var strikes: [Int32: Int] = [:]
    public private(set) var isAvailable = true

    public init(pinger: AppPinger = AXPinger(), threshold: Int = 2) {
        self.pinger = pinger
        self.threshold = threshold
    }

    /// 返回卡住的 pid；并发 ping，最多耗时一个超时
    public func update(pids: [Int32]) -> Set<Int32> {
        var results = [PingResult](repeating: .responsive, count: pids.count)
        let pinger = self.pinger
        results.withUnsafeMutableBufferPointer { buf in
            let out = buf
            DispatchQueue.concurrentPerform(iterations: pids.count) { i in
                out[i] = pinger.ping(pid: pids[i])
            }
        }
        if results.contains(.unavailable) {
            isAvailable = false
            strikes = [:]
            return []
        }
        isAvailable = true
        var next: [Int32: Int] = [:]
        var hung = Set<Int32>()
        for (pid, result) in zip(pids, results) where result == .timedOut {
            let n = (strikes[pid] ?? 0) + 1
            next[pid] = n
            if n >= threshold { hung.insert(pid) }
        }
        strikes = next
        return hung
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter HangDetectorTests`
Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add Sources/OfficeCore/HangDetector.swift Tests/OfficeCoreTests/HangDetectorTests.swift
git commit -m "feat: AX-based hang detector

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: NettopParser 与 TrafficTracker

`nettop -P -L 1 -x -J bytes_in,bytes_out` 的实际输出（本机验证）：

```
,bytes_in,bytes_out,
launchd.1,0,0,
apsd.577,13709,30051,
mDNSResponder.686,65967583,8522824,
```

第一列是 `进程名.pid`（进程名本身可能带点），后两列是进程启动以来的累计字节数。`TrafficTracker` 记录每个 pid 累计字节数上一次增长的时间：第一次见到且字节数 > 0 也算一次增长。最近 `window`（默认 600 秒）内增长过的 pid 视为"联网 app"。

**Files:**
- Create: `Sources/OfficeCore/Traffic.swift`
- Test: `Tests/OfficeCoreTests/TrafficTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import OfficeCore

final class TrafficTests: XCTestCase {
    func testParseNettop() {
        let csv = """
        ,bytes_in,bytes_out,
        launchd.1,0,0,
        apsd.577,13709,30051,
        com.docker.backend.4242,10,5,
        garbage line
        noPid,1,2,
        """
        XCTAssertEqual(NettopParser.parse(csv), [1: 0, 577: 43760, 4242: 15])
    }

    func testFirstSightWithTrafficCounts() {
        let t = TrafficTracker(window: 600)
        let t0 = Date(timeIntervalSince1970: 0)
        t.record([1: 0, 2: 100], at: t0)
        XCTAssertEqual(t.activePIDs(at: t0), [2])
    }

    func testGrowthRefreshesAndWindowExpires() {
        let t = TrafficTracker(window: 600)
        let t0 = Date(timeIntervalSince1970: 0)
        t.record([1: 100], at: t0)
        t.record([1: 100], at: t0.addingTimeInterval(300))
        XCTAssertEqual(t.activePIDs(at: t0.addingTimeInterval(600)), [1])
        XCTAssertEqual(t.activePIDs(at: t0.addingTimeInterval(601)), [])
        t.record([1: 150], at: t0.addingTimeInterval(700))
        XCTAssertEqual(t.activePIDs(at: t0.addingTimeInterval(1200)), [1])
    }

    func testDeadPidsAreDropped() {
        let t = TrafficTracker(window: 600)
        let t0 = Date(timeIntervalSince1970: 0)
        t.record([1: 100], at: t0)
        t.record([:], at: t0.addingTimeInterval(30))
        XCTAssertEqual(t.activePIDs(at: t0.addingTimeInterval(30)), [])
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter TrafficTests`
Expected: 编译失败，`cannot find 'NettopParser' in scope`

- [ ] **Step 3: 写 `Sources/OfficeCore/Traffic.swift`**

```swift
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

/// 记录哪些进程最近有过网络流量
public final class TrafficTracker {
    public let window: TimeInterval
    private var totals: [Int32: UInt64] = [:]
    private var lastActive: [Int32: Date] = [:]

    public init(window: TimeInterval = 600) {
        self.window = window
    }

    public func record(_ newTotals: [Int32: UInt64], at now: Date) {
        for (pid, total) in newTotals where total > (totals[pid] ?? 0) {
            lastActive[pid] = now
        }
        totals = newTotals
        lastActive = lastActive.filter { newTotals[$0.key] != nil }
    }

    public func activePIDs(at now: Date) -> Set<Int32> {
        Set(lastActive.filter { now.timeIntervalSince($0.value) <= window }.keys)
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter TrafficTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add Sources/OfficeCore/Traffic.swift Tests/OfficeCoreTests/TrafficTests.swift
git commit -m "feat: nettop parser and traffic tracker

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: NetworkWatcher

把 `NWPathMonitor`（整机在线状态）和定期运行 nettop 包起来。这层只是在系统调用外面套一层，不写单元测试，在 Task 10 里手动验证。

**Files:**
- Create: `Sources/OfficeCore/NetworkWatcher.swift`

- [ ] **Step 1: 写 `Sources/OfficeCore/NetworkWatcher.swift`**

```swift
import Foundation
import Network

public final class NetworkWatcher {
    public let tracker = TrafficTracker()
    public private(set) var nettopAvailable = true
    /// 两次运行 nettop 的最小间隔
    public var nettopInterval: TimeInterval = 30

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true
    private var lastNettop: Date?

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.withLock { self.online = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "AppOffice.network"))
    }

    deinit {
        monitor.cancel()
    }

    public var isOnline: Bool { lock.withLock { online } }

    /// 每次 tick 都可以调；距上次运行不到 nettopInterval 就直接返回
    public func refreshTraffic(now: Date = Date()) {
        if let last = lastNettop, now.timeIntervalSince(last) < nettopInterval { return }
        lastNettop = now
        guard let output = Self.runNettop() else {
            nettopAvailable = false
            return
        }
        nettopAvailable = true
        tracker.record(NettopParser.parse(output), at: now)
    }

    /// nil 表示不知道（nettop 不可用），调用方应把所有运行中的 app 当成联网 app
    public func networkedPIDs(now: Date = Date()) -> Set<Int32>? {
        nettopAvailable ? tracker.activePIDs(at: now) : nil
    }

    static func runNettop() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 2: 确认能编译**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 提交**

```bash
git add Sources/OfficeCore/NetworkWatcher.swift
git commit -m "feat: network watcher with periodic nettop

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: StatusDiffer

**Files:**
- Create: `Sources/OfficeCore/StatusDiffer.swift`
- Test: `Tests/OfficeCoreTests/StatusDifferTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import OfficeCore

final class StatusDifferTests: XCTestCase {
    private func s(_ id: String, _ state: EmployeeState, cpu: Int = 0) -> EmployeeStatus {
        EmployeeStatus(id: id, state: state, cpu: cpu, memMB: 0, launchedAt: nil)
    }

    func testFirstCallReturnsEverything() {
        var d = StatusDiffer()
        XCTAssertEqual(d.changes([s("a", .off), s("b", .idle)]), [s("a", .off), s("b", .idle)])
    }

    func testOnlyChangedAfterwards() {
        var d = StatusDiffer()
        _ = d.changes([s("a", .off), s("b", .idle)])
        XCTAssertEqual(d.changes([s("a", .off), s("b", .idle, cpu: 3)]), [s("b", .idle, cpu: 3)])
        XCTAssertEqual(d.changes([s("a", .off), s("b", .idle, cpu: 3)]), [])
    }

    func testResetSendsEverythingAgain() {
        var d = StatusDiffer()
        _ = d.changes([s("a", .off)])
        d.reset()
        XCTAssertEqual(d.changes([s("a", .off)]), [s("a", .off)])
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter StatusDifferTests`
Expected: 编译失败，`cannot find 'StatusDiffer' in scope`

- [ ] **Step 3: 写 `Sources/OfficeCore/StatusDiffer.swift`**

```swift
/// 只挑出和上次不一样的员工状态；网页重新加载后调 reset 再全量推一次
public struct StatusDiffer {
    private var last: [String: EmployeeStatus] = [:]

    public init() {}

    public mutating func changes(_ statuses: [EmployeeStatus]) -> [EmployeeStatus] {
        let changed = statuses.filter { last[$0.id] != $0 }
        last = Dictionary(statuses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return changed
    }

    public mutating func reset() {
        last = [:]
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter StatusDifferTests`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add Sources/OfficeCore/StatusDiffer.swift Tests/OfficeCoreTests/StatusDifferTests.swift
git commit -m "feat: status differ

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: OfficeMonitor

把前面的部件串起来。系统依赖通过构造参数注入：`ActivitySampler`、`HangDetector`、`isOnline` 闭包和 `networkedPIDs` 闭包。`networkedPIDs` 返回 nil 时，所有运行中的 app 都当作联网 app（设计文档第 6 节）。名单和运行列表由调用方传入，这样测试不依赖真实的 Dock 和 NSWorkspace。

**Files:**
- Create: `Sources/OfficeCore/OfficeMonitor.swift`
- Test: `Tests/OfficeCoreTests/OfficeMonitorTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
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

    func testTickResolvesEveryEmployee() {
        let usage = StaticUsage()
        usage.table = [
            10: ProcessUsage(cpuNanos: 0, memoryBytes: 50 * 1_048_576),
            11: ProcessUsage(cpuNanos: 0, memoryBytes: 3 * gb),
            12: ProcessUsage(cpuNanos: 0, memoryBytes: 1),
        ]
        let monitor = OfficeMonitor(
            sampler: ActivitySampler(source: usage, clock: { 1 }),
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
        let snap = monitor.tick(dock: dock, running: running)
        XCTAssertEqual(snap.roster.map(\.id), ["com.apple.finder", "com.apple.Safari", "com.apple.Notes", "com.example.Temp"])
        XCTAssertEqual(snap.statuses.map(\.state), [.focused, .off, .snacking, .hung])
        XCTAssertEqual(snap.statuses[0].memMB, 50)
        XCTAssertEqual(snap.statuses[0].launchedAt, 1_791_900_000)
        XCTAssertEqual(snap.network, .online)
        XCTAssertTrue(snap.hangDetectionAvailable)
    }

    func testOfflineUsesNetworkedSet() {
        let usage = StaticUsage()
        usage.table = [10: ProcessUsage(cpuNanos: 0, memoryBytes: 1), 11: ProcessUsage(cpuNanos: 0, memoryBytes: 1)]
        let monitor = OfficeMonitor(
            sampler: ActivitySampler(source: usage, clock: { 1 }),
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
            sampler: ActivitySampler(source: usage, clock: { 1 }),
            hangDetector: HangDetector(pinger: StaticPinger()),
            isOnline: { false },
            networkedPIDs: { nil })
        let snap = monitor.tick(dock: [], running: [AppProcess(bundleID: "com.apple.finder", name: "Finder", pid: 10)])
        XCTAssertEqual(snap.statuses.map(\.state), [.offline])
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter OfficeMonitorTests`
Expected: 编译失败，`cannot find 'OfficeMonitor' in scope`

- [ ] **Step 3: 写 `Sources/OfficeCore/OfficeMonitor.swift`**

```swift
import AppKit
import Foundation

public protocol RunningAppsSource {
    func runningApps() -> [AppProcess]
}

/// 系统里正在运行的普通 app（有 Dock 图标的那种），排除自己
public struct WorkspaceAppsSource: RunningAppsSource {
    public init() {}

    public func runningApps() -> [AppProcess] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  app.processIdentifier != me else { return nil }
            return AppProcess(bundleID: id, name: app.localizedName ?? id, pid: app.processIdentifier,
                              bundleURL: app.bundleURL, launchDate: app.launchDate,
                              isFinishedLaunching: app.isFinishedLaunching, isActive: app.isActive)
        }
    }
}

public struct OfficeSnapshot: Equatable, Sendable {
    public var roster: [RosterEntry]
    /// 与 roster 一一对应、顺序相同
    public var statuses: [EmployeeStatus]
    public var network: NetworkState
    public var hangDetectionAvailable: Bool
}

public final class OfficeMonitor {
    private let sampler: ActivitySampler
    private let hangDetector: HangDetector
    private let isOnline: () -> Bool
    private let networkedPIDs: () -> Set<Int32>?
    private let thresholds: Thresholds

    public init(sampler: ActivitySampler = ActivitySampler(), hangDetector: HangDetector = HangDetector(),
                isOnline: @escaping () -> Bool, networkedPIDs: @escaping () -> Set<Int32>?,
                thresholds: Thresholds = .default) {
        self.sampler = sampler
        self.hangDetector = hangDetector
        self.isOnline = isOnline
        self.networkedPIDs = networkedPIDs
        self.thresholds = thresholds
    }

    public convenience init(network: NetworkWatcher) {
        self.init(isOnline: { network.isOnline }, networkedPIDs: { network.networkedPIDs() })
    }

    /// 可能阻塞最多一个 AX 超时（0.5 秒），不要在主线程上调
    public func tick(dock: [DockApp], running: [AppProcess]) -> OfficeSnapshot {
        let roster = Roster.merge(dock: dock, running: running)
        let byID = Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let pids = running.map(\.pid)
        let metrics = sampler.sample(pids: pids)
        let hung = hangDetector.update(pids: pids)
        let online = isOnline()
        let networked = networkedPIDs()
        let statuses = roster.map { entry -> EmployeeStatus in
            let process = byID[entry.id]
            let m = process.flatMap { metrics[$0.pid] } ?? .zero
            let state = StateResolver.resolve(
                process: process, metrics: m,
                isHung: process.map { hung.contains($0.pid) } ?? false,
                isOnline: online,
                isNetworked: process.map { networked?.contains($0.pid) ?? true } ?? false,
                thresholds: thresholds)
            return StateResolver.status(for: entry, process: process, metrics: m, state: state)
        }
        return OfficeSnapshot(roster: roster, statuses: statuses, network: online ? .online : .offline,
                              hangDetectionAvailable: hangDetector.isAvailable)
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter OfficeMonitorTests`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 5: 运行全部测试**

Run: `swift test`
Expected: 所有测试通过，`with 0 failures`

- [ ] **Step 6: 提交**

```bash
git add Sources/OfficeCore/OfficeMonitor.swift Tests/OfficeCoreTests/OfficeMonitorTests.swift
git commit -m "feat: OfficeMonitor wiring all detectors

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: officectl 命令行工具

每秒刷新一次终端，显示所有员工的状态。`NSWorkspace` 需要主 run loop 转起来才会更新运行列表，所以计时器挂在主线程上：主线程收集运行列表，`tick` 在后台串行队列里跑。Dock 每 10 秒重新读一次。

**Files:**
- Modify: `Sources/officectl/main.swift`（整体替换）

- [ ] **Step 1: 写 `Sources/officectl/main.swift`**

```swift
import AppKit
import OfficeCore

// 终端里每秒刷新：每个员工现在在干嘛
setvbuf(stdout, nil, _IONBF, 0)

let network = NetworkWatcher()
let monitor = OfficeMonitor(network: network)
let workspace = WorkspaceAppsSource()
let worker = DispatchQueue(label: "officectl.tick")

let labels: [EmployeeState: String] = [
    .hung: "🚽 上厕所（卡住）", .offline: "🏋️ 健身（断网）", .launching: "🎒 刚到公司",
    .focused: "⌨️ 疯狂干活", .snacking: "🍪 吃零食", .working: "💻 干活",
    .idle: "☕ 半摸鱼", .off: "😴 摸鱼",
]

var dock = DockReader.load()
var ticks = 0

func render(_ snap: OfficeSnapshot) {
    var out = "\u{1B}[2J\u{1B}[H"
    out += "网络: \(snap.network.rawValue)    卡顿检测: \(snap.hangDetectionAvailable ? "开" : "关（终端需要辅助功能权限）")\n\n"
    for (entry, status) in zip(snap.roster, snap.statuses) {
        let kind = entry.kind == .staff ? "正式 #\(entry.seat ?? 0)" : "临时"
        out += "\(kind)\t\(labels[status.state] ?? "")\tCPU \(status.cpu)%\t\(status.memMB) MB\t\(entry.name)\n"
    }
    print(out, terminator: "")
}

Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    if ticks % 10 == 0 { dock = DockReader.load() }
    ticks += 1
    let currentDock = dock
    let running = workspace.runningApps()
    worker.async {
        network.refreshTraffic()
        let snap = monitor.tick(dock: currentDock, running: running)
        DispatchQueue.main.async { render(snap) }
    }
}

RunLoop.main.run()
```

- [ ] **Step 2: 编译**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 手动验证**

Run: `swift run officectl`（按 Ctrl+C 退出）

逐项检查：
1. 第一行是 `正式 #0 ... 访达`，接着按 Dock 顺序列出正式员工，最后是临时工。
2. 切换到别的 app，1 秒内它变成 `⌨️ 疯狂干活`，之前的前台 app 变回 `☕ 半摸鱼` 或 `💻 干活`。
3. 打开一个 Dock 里但没开着的 app：短暂显示 `🎒 刚到公司`，然后变成 `⌨️ 疯狂干活`；退出它后变成 `😴 摸鱼`。
4. 打开一个不在 Dock 里的 app：它作为 `临时` 出现在列表末尾；退出后从列表消失。
5. 关掉 Wi‑Fi：第一行变成 `网络: offline`，开过浏览器或聊天软件的员工变成 `🏋️ 健身（断网）`。重新打开 Wi‑Fi 后恢复。注意 nettop 每 30 秒才跑一次，刚启动 officectl 时最多要等 30 秒才知道谁联过网。
6. 卡顿检测：在系统设置 → 隐私与安全性 → 辅助功能里给终端（或运行 officectl 的 app）授权，重启 officectl，第一行变成 `卡顿检测: 开`。要验证"上厕所"，可以在终端里运行 `kill -STOP <某个 app 的 pid>` 让它冻住（pid 可以用 `pgrep -x TextEdit` 查），2 到 3 秒内它会变成 `🚽 上厕所（卡住）`；再运行 `kill -CONT <pid>` 恢复，它会回到正常状态。

- [ ] **Step 4: 提交**

```bash
git add Sources/officectl/main.swift
git commit -m "feat: officectl live terminal view

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 计划 1 完成标准

- `swift test` 全部通过。
- `swift run officectl` 的 6 项手动检查都符合预期。
- 设计文档覆盖情况：2.1 名单与主色、2.2 状态与优先级、5.3 `status` 消息字段、第 6 节中"未授权辅助功能"和"nettop 不可用"两种情况，都由本计划实现。设施排队、画面、互动、菜单栏、图标 PNG 和 `roster` 消息不在本计划内，分别属于计划 2 和计划 3。

---

## 实施记录（与上文计划的偏差）

逐任务审查和最终审查之后，实际代码在这些地方和上面的计划不同，以代码为准：

| 位置 | 改动 | 原因 |
|---|---|---|
| `Roster.merge` | 访达名字一开始就算好（Dock 标签 → 运行中名字 → "Finder"）；正式员工 `bundleURL` 缺失时用运行中 app 的 URL | 原写法按下标覆盖，不直观；后面拿图标要用 URL |
| `DominantColor.fromRGBA` | 输入视为预乘 alpha，先还原再算 | 图标圆角边缘半透明像素会把颜色压暗 |
| `NetworkWatcher` | nettop 在自己的队列上异步跑，15 秒看门狗；输出为空或失败 → 不知道（nil）；第一次跑完之前也是不知道；状态都在锁里；`runNettop` 可注入、`public static` | 本机实测 nettop 一次约 5 秒，原写法会卡住每秒一拍的采样 |
| `ProcessOwner`（新增） | nettop 的 pid 先算回 app 主进程（`responsibility_get_pid_responsible_for_pid`，退回父进程） | nettop 把流量记在 Chrome Helper、WebKit.Networking 这类 helper 进程上 |
| `TrafficTracker` | 按 owner pid 记录；`lastActive` 只按时间窗口淘汰 | nettop 只列出当前有 socket 的进程，原写法一断开连接就忘了 |
| `OfficeMonitor` | `OfficeSnapshot` 有 public init；每个 bundle id 只采样/ping 一个 pid；`WorkspaceAppsSource` 跳过 pid ≤ 0 或已不存在的"幽灵" app | 系统自动终止的 app 还留在运行列表里，会永远显示"刚到公司" |
| `officectl` | 上一拍没算完就跳过；启动立刻出第一帧；表头显示流量数据是否就绪 | 防止卡住时任务排队 |

**给计划 3（macOS 外壳）的要求：**
- 照搬 officectl 的模式：主线程定时器收集运行列表和 Dock（Dock 每 10 秒读一次），串行 worker 队列跑 `refreshTraffic` + `tick`，回主线程更新；有 busy 标记，上一拍没算完就跳过。
- 测一下每秒 AX ping（`kAXRoleAttribute`）会不会让 Chrome / Electron 打开辅助功能模式、内存明显上涨；会的话换一个属性或降低频率。
- 用 URL 启动 app 失败时退回 `NSWorkspace.urlForApplication(withBundleIdentifier:)`（有些 Dock 项存的是路径不是 URL）。
