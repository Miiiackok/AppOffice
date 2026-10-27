import Foundation
import Network

public final class NetworkWatcher {
    /// 两次运行 nettop 的最小间隔
    public var nettopInterval: TimeInterval = 30

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    // 以下都只在 lock 里读写
    private var online = true
    private let tracker: TrafficTracker
    private var nettopAvailable = false  // 第一次 nettop 跑完之前也算不知道
    private var nettopRunning = false
    private var lastNettop: Date?

    private let nettopQueue = DispatchQueue(label: "AppOffice.nettop")
    private let runNettop: () -> String?

    public init(runNettop: @escaping () -> String? = { NetworkWatcher.runNettop() },
                owner: @escaping (Int32) -> Int32 = ProcessOwner.owner(of:)) {
        self.runNettop = runNettop
        self.tracker = TrafficTracker(owner: owner)
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
    public var isNettopAvailable: Bool { lock.withLock { nettopAvailable } }

    /// 不阻塞：到时间就在后台队列跑一次 nettop（本机实测约 5 秒），跑完再更新结果；上一次还没跑完就跳过
    public func refreshTraffic(now: Date = Date()) {
        let shouldRun: Bool = lock.withLock {
            if nettopRunning { return false }
            if let last = lastNettop, now.timeIntervalSince(last) < nettopInterval { return false }
            lastNettop = now
            nettopRunning = true
            return true
        }
        guard shouldRun else { return }
        nettopQueue.async { [weak self] in
            guard let self else { return }
            let output = self.runNettop()
            let totals = output.map { NettopParser.parse($0) } ?? [:]
            self.lock.withLock {
                self.nettopRunning = false
                if totals.isEmpty {
                    self.nettopAvailable = false
                } else {
                    self.nettopAvailable = true
                    self.tracker.record(totals, at: now)
                }
            }
        }
    }

    /// nil 表示不知道（nettop 不可用或解析不出任何进程），调用方应把所有运行中的 app 当成联网 app
    public func networkedPIDs(now: Date = Date()) -> Set<Int32>? {
        lock.withLock { nettopAvailable ? tracker.activePIDs(at: now) : nil }
    }

    /// 测试用：等后台的 nettop 跑完
    func waitForPendingRefresh() { nettopQueue.sync {} }

    public static func runNettop(timeout: TimeInterval = 15) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // 看门狗：超时就杀掉，避免永远卡住
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
