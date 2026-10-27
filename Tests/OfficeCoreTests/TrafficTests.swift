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

    func testAbsentPidStaysActiveWithinWindow() {
        let t = TrafficTracker(window: 600)
        let t0 = Date(timeIntervalSince1970: 0)
        t.record([1: 100], at: t0)
        t.record([:], at: t0.addingTimeInterval(30))
        XCTAssertEqual(t.activePIDs(at: t0.addingTimeInterval(30)), [1])
        XCTAssertEqual(t.activePIDs(at: t0.addingTimeInterval(601)), [])
    }

    func testHelperTrafficCountsForOwner() {
        let t = TrafficTracker(window: 600, owner: { $0 == 2604 ? 2515 : $0 })
        let t0 = Date(timeIntervalSince1970: 0)
        t.record([2604: 500], at: t0)
        XCTAssertEqual(t.activePIDs(at: t0), [2515])
    }
}
