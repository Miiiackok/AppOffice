import AppKit
import OfficeCore

/// 每秒一拍（暂停时 20 秒）：主线程收集运行列表和 Dock，后台串行队列算状态，回主线程交给 onSnapshot
final class MonitorLoop {
    var onSnapshot: ((OfficeSnapshot) -> Void)?
    /// 最近一拍的运行列表（执行网页操作时用）
    private(set) var running: [AppProcess] = []
    private let network = NetworkWatcher()
    private let monitor: OfficeMonitor
    private let workspace = WorkspaceAppsSource()
    private let worker = DispatchQueue(label: "AppOffice.tick")
    private var dock: [DockApp] = []
    private var installed: [DockApp] = []
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
        // 名单上的 app 装了没有：和 Dock 一样 10 秒查一次
        if ticks % 10 == 0 { installed = InstalledApps.find(Roster.listedIDs) }
        ticks += 1
        busy = true
        let currentDock = dock
        let currentInstalled = installed
        let currentRunning = workspace.runningApps()
        running = currentRunning
        let paused = self.paused
        worker.async { [weak self] in
            guard let self else { return }
            if !paused { self.network.refreshTraffic() }
            let snapshot = self.monitor.tick(dock: currentDock, installed: currentInstalled, running: currentRunning,
                                             detectHangs: !paused)
            DispatchQueue.main.async {
                self.busy = false
                self.onSnapshot?(snapshot)
            }
        }
    }
}
