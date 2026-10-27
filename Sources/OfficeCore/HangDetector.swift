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

/// 非线程安全：只在同一个串行队列上调用
public final class HangDetector {
    private let pinger: AppPinger
    private let threshold: Int
    private var strikes: [Int32: Int] = [:]
    public private(set) var isAvailable = true

    public init(pinger: AppPinger = AXPinger(), threshold: Int = 2) {
        self.pinger = pinger
        self.threshold = threshold
    }

    /// 返回卡住的 pid。会阻塞：并发 ping，卡住的 app 每个占一个线程 0.5 秒，不要在主线程上调，也不要传入自己的 pid
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
