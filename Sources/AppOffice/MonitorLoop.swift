import AppKit
import OfficeCore

/// 每秒一拍（暂停时 20 秒）：主线程收集运行列表和 Dock，后台串行队列算状态，回主线程交给 onSnapshot
final class MonitorLoop {
    var onSnapshot: ((OfficeSnapshot) -> Void)?
    /// rooms.json 写坏了、写不进去
    var onRoomsProblem: ((String) -> Void)?
    let roomsFile = RoomsFile()
    /// 最近一拍的运行列表（执行网页操作时用）
    private(set) var running: [AppProcess] = []
    private let network = NetworkWatcher()
    private let monitor: OfficeMonitor
    private let workspace = WorkspaceAppsSource()
    private let worker = DispatchQueue(label: "AppOffice.tick")
    private var dock: [DockApp] = []
    /// 只在 worker 上用
    private let installed = InstalledApps()
    private var rooms: ResolvedRooms = .empty
    private var roomsDirty = true
    private var ticks = 0
    private var busy = false
    private var timer: Timer?

    init() {
        monitor = OfficeMonitor(network: network)
    }

    /// 网页暂停（窗口隐藏、被挡住、锁屏）时降到 20 秒一拍，不做卡顿检测、不跑 nettop；恢复时立刻补一拍
    var paused = false {
        didSet {
            guard paused != oldValue, timer != nil else { return }
            schedule()
            if !paused { step() }
        }
    }

    func start() {
        step()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        let timer = Timer(timeInterval: paused ? 20 : 1, repeats: true) { [weak self] _ in self?.step() }
        timer.tolerance = paused ? 2 : 0.2
        RunLoop.main.add(timer, forMode: .common) // 打开菜单时也不停
        self.timer = timer
    }

    private func step() {
        // 上一拍还没算完就跳过，避免排队
        guard !busy else { return }
        // Dock 还没读到时每拍都重试
        if dock.isEmpty || ticks % 10 == 0 { dock = DockReader.keepLastIfEmpty(DockReader.load(), previous: dock) }
        // rooms.json 每拍看一眼，改了马上重排；名字对 app 和 Dock 一样 10 秒一次（装了新 app 也能对上）
        switch roomsFile.refresh(dock: dock) {
        case .created, .loaded: roomsDirty = true
        case .failed(let message): onRoomsProblem?(message)
        case .unchanged: break
        }
        let config = roomsDirty || ticks % 10 == 0 ? roomsFile.config : nil
        roomsDirty = false
        ticks += 1
        busy = true
        let currentDock = dock
        let currentRunning = workspace.runningApps()
        running = currentRunning
        let paused = self.paused
        worker.async { [weak self] in
            guard let self else { return }
            if !paused { self.network.refreshTraffic() }
            if let config {
                let candidates = currentDock.map { AppCandidate(bundleID: $0.bundleID, names: [$0.name], url: $0.url) }
                    + currentRunning.map { AppCandidate(bundleID: $0.bundleID, names: [$0.name], url: $0.bundleURL) }
                    + self.installed.candidates()
                self.rooms = RoomsResolver.resolve(config, candidates: candidates)
            }
            let snapshot = self.monitor.tick(dock: currentDock, rooms: self.rooms, running: currentRunning,
                                             detectHangs: !paused)
            DispatchQueue.main.async {
                self.busy = false
                self.onSnapshot?(snapshot)
            }
        }
    }
}
