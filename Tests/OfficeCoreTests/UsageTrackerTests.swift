import XCTest
@testable import OfficeCore

final class UsageTrackerTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/Applications/A.app")

    func testUsesTheLaterOfSpotlightAndSeenRunning() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let tracker = UsageTracker(lastUsedOf: { _ in t0 })
        XCTAssertEqual(tracker.lastUsed(id: "a", url: url, now: t0 + 10), t0)
        tracker.sawRunning("a", at: t0 + 20)
        XCTAssertEqual(tracker.lastUsed(id: "a", url: url, now: t0 + 30), t0 + 20)
        // Spotlight 没记、也没见过：nil
        XCTAssertNil(UsageTracker(lastUsedOf: { _ in nil }).lastUsed(id: "b", url: url, now: t0))
        XCTAssertNil(tracker.lastUsed(id: "c", url: nil, now: t0))
    }

    func testCachesSpotlightForAWhile() {
        var calls = 0
        let t0 = Date(timeIntervalSince1970: 1_000)
        let tracker = UsageTracker(refresh: 60, lastUsedOf: { _ in calls += 1; return nil })
        _ = tracker.lastUsed(id: "a", url: url, now: t0)
        _ = tracker.lastUsed(id: "a", url: url, now: t0 + 59)
        XCTAssertEqual(calls, 1)
        _ = tracker.lastUsed(id: "a", url: url, now: t0 + 61)
        XCTAssertEqual(calls, 2)
    }

    func testSpotlightReadsFinder() {
        // 访达一直开着，Spotlight 一定记过；查不到也不该崩
        _ = UsageTracker.spotlightLastUsed(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
    }
}
