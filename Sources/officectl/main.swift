import AppKit
import OfficeCore

// 终端里每秒刷新：每个员工现在在干嘛
setvbuf(stdout, nil, _IONBF, 0)

let network = NetworkWatcher()
let monitor = OfficeMonitor(network: network)
let workspace = WorkspaceAppsSource()
let worker = DispatchQueue(label: "officectl.tick")

let labels: [EmployeeState: String] = [
    .hung: L("🚽 上厕所（卡住）", "🚽 restroom (frozen)"), .offline: L("🏋️ 健身（断网）", "🏋️ gym (offline)"),
    .launching: L("🎒 刚到公司", "🎒 arriving"), .focused: L("⌨️ 疯狂干活", "⌨️ typing like mad"),
    .snacking: L("🍪 吃零食", "🍪 snacking"), .working: L("💻 干活", "💻 working"),
    .idle: L("☕ 半摸鱼", "☕ idle"), .resting: L("🎮 休闲区", "🎮 lounge"), .off: L("😴 摸鱼", "😴 slacking"),
]

// 以下只在主线程读写
var dock: [DockApp] = []
let roomsFile = RoomsFile()
let installed = InstalledApps()
var rooms: ResolvedRooms = .empty
var ticks = 0
var busy = false

func render(_ snap: OfficeSnapshot, trafficReady: Bool) {
    var out = "\u{1B}[2J\u{1B}[H"
    let hang = snap.hangDetectionAvailable ? L("开", "on") : L("关（终端需要辅助功能权限）", "off (Terminal needs Accessibility)")
    let traffic = trafficReady ? L("已就绪", "ready") : L("未就绪（nettop 首次运行约 5 秒）", "not ready (first nettop run takes ~5 s)")
    out += L("网络: ", "network: ") + snap.network.rawValue + L("    卡顿检测: ", "    hang detection: ") + hang
    out += L("    流量数据: ", "    traffic: ") + traffic + "\n\n"
    for (entry, status) in zip(snap.roster, snap.statuses) {
        let room = entry.room.flatMap { i -> String? in
            guard snap.rooms.indices.contains(i) else { return nil }
            return snap.rooms[i].kind == .offices ? L("大办公室", "Offices") : snap.rooms[i].name
        } ?? ""
        let kind = entry.kind == .staff ? "\(room) #\(entry.seat ?? 0)" : L("临时", "temp")
        out += "\(kind)\t\(labels[status.state] ?? "")\tCPU \(status.cpu)%\t\(status.memMB) MB\t\(entry.name)\n"
    }
    print(out, terminator: "")
}

/// 在主线程调：读 Dock 和运行列表，交给后台算一拍，算完回主线程画
func step() {
    // 上一拍还没算完就跳过，避免排队
    if busy { return }
    busy = true
    if ticks % 10 == 0 { dock = DockReader.load() }
    if case .failed(let message) = roomsFile.refresh(dock: dock) { print(message) }
    let config = roomsFile.config
    ticks += 1
    let currentDock = dock
    let running = workspace.runningApps()
    worker.async {
        network.refreshTraffic()
        if let config {
            let candidates = currentDock.map { AppCandidate(bundleID: $0.bundleID, names: [$0.name], url: $0.url) }
                + running.map { AppCandidate(bundleID: $0.bundleID, names: [$0.name], url: $0.bundleURL) }
                + installed.candidates()
            rooms = RoomsResolver.resolve(config, candidates: candidates)
        }
        let snap = monitor.tick(dock: currentDock, rooms: rooms, running: running)
        let trafficReady = network.isNettopAvailable
        DispatchQueue.main.async {
            render(snap, trafficReady: trafficReady)
            busy = false
        }
    }
}

// 启动就先画一帧，不等 1 秒
step()
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in step() }

RunLoop.main.run()
