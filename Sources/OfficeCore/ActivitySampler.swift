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

/// 一个 app 不只主进程在干活：Electron 的 Helper、浏览器的渲染进程、它启动的命令行工具都算它的
public protocol ProcessFamilySource {
    /// 系统里所有进程
    func allPIDs() -> [Int32]
    /// 负责这个进程的 app 主进程 pid
    func owner(of pid: Int32) -> Int32
}

public struct SystemProcessFamilySource: ProcessFamilySource {
    public init() {}

    public func allPIDs() -> [Int32] {
        // 先问要多大的缓冲区，多留一些给这期间新起的进程
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return n > 0 ? pids.prefix(Int(n)).filter { $0 > 0 } : []
    }

    public func owner(of pid: Int32) -> Int32 { ProcessOwner.owner(of: pid) }
}

public final class ActivitySampler {
    private let source: ProcessUsageSource
    private let family: ProcessFamilySource?
    private let clock: () -> UInt64
    private var last: [Int32: (cpu: UInt64, at: UInt64)] = [:]
    /// 进程 → 主进程，进程活着期间不会变，查一次就记住
    private var owners: [Int32: Int32] = [:]

    /// family 为 nil 时只看主进程
    public init(source: ProcessUsageSource = SystemProcessUsageSource(),
                family: ProcessFamilySource? = SystemProcessFamilySource(),
                clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.source = source
        self.family = family
        self.clock = clock
    }

    /// 按 app 主进程给结果：CPU 是整个进程家族加起来，内存只算主进程。读不到的主进程不出现在结果里
    public func sample(pids: [Int32]) -> [Int32: ProcessMetrics] {
        let now = clock()
        let apps = Set(pids)
        var members: [Int32: Int32] = Dictionary(pids.map { ($0, $0) }, uniquingKeysWith: { a, _ in a })
        if let family {
            let all = family.allPIDs()
            let alive = Set(all)
            owners = owners.filter { alive.contains($0.key) }
            for pid in all where members[pid] == nil {
                let owner = owners[pid] ?? family.owner(of: pid)
                owners[pid] = owner
                if apps.contains(owner) { members[pid] = owner }
            }
        }
        var cpu: [Int32: Double] = [:]
        var memory: [Int32: UInt64] = [:]
        var next: [Int32: (cpu: UInt64, at: UInt64)] = [:]
        for (pid, app) in members {
            guard let u = source.usage(pid: pid) else { continue }
            if pid == app { memory[app] = u.memoryBytes }
            // 第一次见到的进程没有上一次可比，这一拍算 0
            if let prev = last[pid], now > prev.at, u.cpuNanos >= prev.cpu {
                cpu[app, default: 0] += Double(u.cpuNanos - prev.cpu) / Double(now - prev.at) * 100
            }
            next[pid] = (u.cpuNanos, now)
        }
        last = next
        return memory.reduce(into: [:]) { result, entry in
            result[entry.key] = ProcessMetrics(cpuPercent: cpu[entry.key] ?? 0, memoryBytes: entry.value)
        }
    }
}
