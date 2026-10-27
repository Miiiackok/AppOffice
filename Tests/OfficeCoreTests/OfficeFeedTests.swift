import XCTest
@testable import OfficeCore

private struct FakeIcons: IconProviding {
    func icon(for entry: RosterEntry) -> AppIcon { AppIcon(pngBase64: "png-\(entry.id)", color: "#000000") }
}

private func entry(_ id: String, seat: Int?) -> RosterEntry {
    RosterEntry(id: id, name: id.uppercased(), kind: seat == nil ? .temp : .staff, room: seat == nil ? nil : 1,
                seat: seat, bundleURL: nil)
}

private func status(_ id: String, _ state: EmployeeState, cpu: Int = 0) -> EmployeeStatus {
    EmployeeStatus(id: id, state: state, cpu: cpu, memMB: 0, launchedAt: nil)
}

private func snap(_ pairs: [(RosterEntry, EmployeeStatus)], network: NetworkState = .online) -> OfficeSnapshot {
    OfficeSnapshot(roster: pairs.map(\.0), statuses: pairs.map(\.1), network: network, hangDetectionAvailable: true)
}

private func item(_ e: RosterEntry) -> RosterItem {
    RosterItem(id: e.id, name: e.name, kind: e.kind, room: e.room, seat: e.seat, color: "#000000", iconPNG: "png-\(e.id)")
}

final class OfficeFeedTests: XCTestCase {
    private let a = entry("a", seat: 0)
    private let t = entry("t", seat: nil)

    func testNothingIsSentBeforeReady() {
        var feed = OfficeFeed(icons: FakeIcons())
        XCTAssertEqual(feed.update(snap([(a, status("a", .idle))])), [])
    }

    func testReadySendsRosterThenStatusThenPaused() {
        var feed = OfficeFeed(icons: FakeIcons())
        _ = feed.update(snap([(a, status("a", .idle))]))
        XCTAssertEqual(feed.ready(), [.roster([], [item(a)]), .status(.online, [status("a", .idle)]), .paused(false)])
    }

    func testOnlyChangesAfterReady() {
        var feed = OfficeFeed(icons: FakeIcons())
        let s1 = snap([(a, status("a", .idle))])
        _ = feed.update(s1)
        _ = feed.ready()
        XCTAssertEqual(feed.update(s1), [])
        XCTAssertEqual(feed.update(snap([(a, status("a", .focused, cpu: 50))])),
                       [.status(.online, [status("a", .focused, cpu: 50)])])
        XCTAssertEqual(feed.update(snap([(a, status("a", .focused, cpu: 50)), (t, status("t", .launching))])),
                       [.roster([], [item(a), item(t)]), .status(.online, [status("t", .launching)])])
    }

    func testReadyAgainResendsEverything() {
        var feed = OfficeFeed(icons: FakeIcons())
        let s1 = snap([(a, status("a", .idle))])
        _ = feed.update(s1)
        _ = feed.ready()
        XCTAssertEqual(feed.ready(), [.roster([], [item(a)]), .status(.online, [status("a", .idle)]), .paused(false)])
    }

    func testReadyBeforeAnySnapshot() {
        var feed = OfficeFeed(icons: FakeIcons())
        XCTAssertEqual(feed.ready(), [.paused(false)])
        XCTAssertEqual(feed.update(snap([(a, status("a", .idle))])),
                       [.roster([], [item(a)]), .status(.online, [status("a", .idle)])])
    }

    func testPausedOnlyWhenChangedAndReady() {
        var feed = OfficeFeed(icons: FakeIcons())
        XCTAssertEqual(feed.setPaused(true), [])
        XCTAssertEqual(feed.ready(), [.paused(true)])
        XCTAssertEqual(feed.setPaused(true), [])
        XCTAssertEqual(feed.setPaused(false), [.paused(false)])
    }

    func testSimulateOverridesState() {
        var feed = OfficeFeed(icons: FakeIcons())
        let s1 = snap([(a, status("a", .idle))])
        _ = feed.update(s1)
        _ = feed.ready()
        XCTAssertEqual(feed.simulate("a", .hung), [.status(.online, [status("a", .hung)])])
        XCTAssertEqual(feed.update(s1), [])
        XCTAssertEqual(feed.simulated, ["a": .hung])
        XCTAssertEqual(feed.simulate("a", nil), [.status(.online, [status("a", .idle)])])
    }

    func testNetworkOnlyChangeSendsStatusWithNoEmployees() {
        var feed = OfficeFeed(icons: FakeIcons())
        let pairs = [(a, status("a", .idle))]
        _ = feed.update(snap(pairs))
        _ = feed.ready()
        XCTAssertEqual(feed.update(snap(pairs, network: .offline)), [.status(.offline, [])])
        XCTAssertEqual(feed.update(snap(pairs, network: .offline)), [])
    }

    func testRenamedRoomResendsRoster() {
        var feed = OfficeFeed(icons: FakeIcons())
        _ = feed.update(snap([(a, status("a", .idle))]))
        _ = feed.ready()
        var renamed = snap([(a, status("a", .idle))])
        renamed.rooms = [RoomInfo(name: "生活部", kind: .shared)]
        XCTAssertEqual(feed.update(renamed), [.roster(renamed.rooms, [item(a)])])
    }

    func testResetWaitsForNextReady() {
        var feed = OfficeFeed(icons: FakeIcons())
        _ = feed.update(snap([(a, status("a", .idle))]))
        _ = feed.ready()
        feed.reset()
        XCTAssertEqual(feed.update(snap([(a, status("a", .hung))])), [])
    }
}
