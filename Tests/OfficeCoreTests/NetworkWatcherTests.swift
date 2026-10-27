import XCTest
@testable import OfficeCore

final class NetworkWatcherTests: XCTestCase {
    private final class Counter {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }

    func testParsesTrafficFromRunner() {
        let watcher = NetworkWatcher(runNettop: { ",bytes_in,bytes_out,\nSafari.42,10,5,\nidle.7,0,0,\n" })
        let t0 = Date()
        watcher.refreshTraffic(now: t0)
        watcher.waitForPendingRefresh()
        XCTAssertEqual(watcher.networkedPIDs(now: t0), [42])
        XCTAssertTrue(watcher.isNettopAvailable)
    }

    func testUnknownBeforeFirstRun() {
        let watcher = NetworkWatcher(runNettop: { ",bytes_in,bytes_out,\nSafari.42,10,5,\n" })
        XCTAssertNil(watcher.networkedPIDs())
        XCTAssertFalse(watcher.isNettopAvailable)
    }

    func testEmptyOutputMeansUnknown() {
        let watcher = NetworkWatcher(runNettop: { ",bytes_in,bytes_out,\n" })
        let t0 = Date()
        watcher.refreshTraffic(now: t0)
        watcher.waitForPendingRefresh()
        XCTAssertNil(watcher.networkedPIDs(now: t0))
        XCTAssertFalse(watcher.isNettopAvailable)
    }

    func testFailedRunMeansUnknown() {
        let watcher = NetworkWatcher(runNettop: { nil })
        let t0 = Date()
        watcher.refreshTraffic(now: t0)
        watcher.waitForPendingRefresh()
        XCTAssertNil(watcher.networkedPIDs(now: t0))
        XCTAssertFalse(watcher.isNettopAvailable)
    }

    func testOwnerMappingApplied() {
        let watcher = NetworkWatcher(runNettop: { ",bytes_in,bytes_out,\nGoogle Chrome H.2604,10,5,\n" },
                                     owner: { $0 == 2604 ? 2515 : $0 })
        let t0 = Date()
        watcher.refreshTraffic(now: t0)
        watcher.waitForPendingRefresh()
        XCTAssertEqual(watcher.networkedPIDs(now: t0), [2515])
    }

    func testRespectsInterval() {
        let counter = Counter()
        let watcher = NetworkWatcher(runNettop: {
            counter.bump()
            return ",bytes_in,bytes_out,\nSafari.42,10,5,\n"
        })
        let t0 = Date()
        watcher.refreshTraffic(now: t0)
        watcher.waitForPendingRefresh()
        watcher.refreshTraffic(now: t0.addingTimeInterval(10))
        watcher.waitForPendingRefresh()
        XCTAssertEqual(counter.value, 1)
        watcher.refreshTraffic(now: t0.addingTimeInterval(31))
        watcher.waitForPendingRefresh()
        XCTAssertEqual(counter.value, 2)
    }
}
