import XCTest
@testable import OfficeCore

final class RosterTests: XCTestCase {
    private func tile(_ id: String, _ label: String, _ url: String) -> [String: Any] {
        ["tile-data": ["bundle-identifier": id, "file-label": label, "file-data": ["_CFURLString": url]]]
    }

    func testParseDockTiles() {
        let raw: [[String: Any]] = [
            tile("com.apple.Safari", "Safari", "file:///Applications/Safari.app/"),
            ["tile-data": ["file-label": "没有 bundle id 的项"]],
            ["tile-type": "spacer-tile"],
            ["tile-data": ["bundle-identifier": "com.example.NoLabel"]],
        ]
        XCTAssertEqual(DockReader.parse(raw), [
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: URL(string: "file:///Applications/Safari.app/")),
            DockApp(bundleID: "com.example.NoLabel", name: "com.example.NoLabel", url: nil),
        ])
    }

    func testParseDockTileWithPath() {
        let raw: [[String: Any]] = [
            ["tile-data": ["bundle-identifier": "com.example.Path", "file-label": "Path",
                           "file-data": ["_CFURLString": "/Applications/Path App.app", "_CFURLStringType": 0]]],
        ]
        let url = DockReader.parse(raw).first?.url
        XCTAssertEqual(url, URL(fileURLWithPath: "/Applications/Path App.app"))
        XCTAssertEqual(url?.isFileURL, true)
    }

    private func app(_ id: String, _ name: String, _ url: String? = nil) -> DockApp {
        DockApp(bundleID: id, name: name, url: url.map { URL(fileURLWithPath: $0) })
    }

    func testMergeSeatsOfficesThenRoomsThenTemps() {
        let rooms = ResolvedRooms(
            offices: [app("com.google.Chrome", "Google Chrome"), app("com.tencent.xinWeChat", "WeChat")],
            rooms: [
                .init(name: "生活部", apps: [app("com.apple.Notes", "Notes"), app("com.apple.mail", "Mail")], collectsDock: false),
                .init(name: "Dock 部", apps: [app("com.apple.finder", "Finder")], collectsDock: true),
            ])
        let dock = [app("com.apple.Safari", "Safari"), app("com.apple.Notes", "备忘录")]
        let running = [
            AppProcess(bundleID: "com.apple.finder", name: "访达", pid: 10),
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 12),
        ]
        let (info, roster) = Roster.merge(rooms: rooms, dock: dock, running: running)
        XCTAssertEqual(info, [RoomInfo(name: "offices", kind: .offices), RoomInfo(name: "生活部", kind: .shared),
                              RoomInfo(name: "Dock 部", kind: .shared)])
        XCTAssertEqual(roster.map(\.id), ["com.google.Chrome", "com.tencent.xinWeChat", "com.apple.Notes", "com.apple.mail",
                                          "com.apple.finder", "com.apple.Safari", "com.example.Temp"])
        XCTAssertEqual(roster.map(\.room), [0, 0, 1, 1, 2, 2, nil])
        XCTAssertEqual(roster.map(\.seat), [0, 1, 0, 1, 0, 1, nil])
        XCTAssertEqual(roster.map(\.kind), [.staff, .staff, .staff, .staff, .staff, .staff, .temp])
        // Dock 上的名字优先，其次运行时的名字
        XCTAssertEqual(roster.map(\.name), ["Google Chrome", "WeChat", "备忘录", "Mail", "访达", "Safari", "Temp"])
    }

    func testUnlistedDockAppsAreTempsWithoutACollectingRoom() {
        let rooms = ResolvedRooms(offices: [], rooms: [.init(name: "A", apps: [], collectsDock: false)])
        let dock = [app("com.apple.Safari", "Safari")]
        let running = [AppProcess(bundleID: "com.apple.Safari", name: "Safari", pid: 1)]
        let (_, roster) = Roster.merge(rooms: rooms, dock: dock, running: running)
        XCTAssertEqual(roster.map(\.kind), [.temp])
        // 没开就不出现
        XCTAssertEqual(Roster.merge(rooms: rooms, dock: dock, running: []).roster, [])
    }

    func testAnAppListedTwiceSitsInTheFirstPlace() {
        let notes = app("com.apple.Notes", "Notes")
        let rooms = ResolvedRooms(offices: [notes], rooms: [.init(name: "A", apps: [notes], collectsDock: true)])
        let (_, roster) = Roster.merge(rooms: rooms, dock: [notes], running: [])
        XCTAssertEqual(roster.map(\.room), [0])
    }

    func testStaffURLPrefersDockThenRunningThenResolved() {
        let rooms = ResolvedRooms(offices: [app("a", "A", "/Installed/A.app"), app("b", "B", "/Installed/B.app"),
                                            app("c", "C", "/Installed/C.app")], rooms: [])
        let dock = [app("a", "A", "/Dock/A.app")]
        let running = [AppProcess(bundleID: "b", name: "B", pid: 1, bundleURL: URL(fileURLWithPath: "/Running/B.app"))]
        let (_, roster) = Roster.merge(rooms: rooms, dock: dock, running: running)
        XCTAssertEqual(roster.map { $0.bundleURL?.path }, ["/Dock/A.app", "/Running/B.app", "/Installed/C.app"])
    }

    func testDuplicateRunningProcessesCollapse() {
        let running = [
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 1),
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 2),
        ]
        XCTAssertEqual(Roster.merge(rooms: .empty, dock: [], running: running).roster.map(\.id), ["com.example.Temp"])
    }

    func testKeepsLastDockWhenReadFails() {
        let last = [DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil)]
        XCTAssertEqual(DockReader.keepLastIfEmpty([], previous: last), last)
        let fresh = [DockApp(bundleID: "com.apple.Notes", name: "Notes", url: nil)]
        XCTAssertEqual(DockReader.keepLastIfEmpty(fresh, previous: last), fresh)
        XCTAssertEqual(DockReader.keepLastIfEmpty([], previous: []), [])
    }
}
