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
