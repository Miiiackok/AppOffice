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

    func testMergeSeatsListedAppsByRoomThenTemps() {
        let dock = [
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil),
            DockApp(bundleID: "com.apple.Notes", name: "Notes", url: nil),
        ]
        let running = [
            AppProcess(bundleID: "com.apple.finder", name: "访达", pid: 10),
            AppProcess(bundleID: "com.apple.Notes", name: "备忘录", pid: 11),
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 12),
        ]
        let roster = Roster.merge(dock: dock, running: running)
        XCTAssertEqual(roster.map(\.id), ["com.apple.Notes", "com.apple.finder", "com.apple.Safari", "com.example.Temp"])
        XCTAssertEqual(roster.map(\.kind), [.staff, .staff, .staff, .temp])
        XCTAssertEqual(roster.map(\.room), [.apple, .dock, .dock, nil])
        XCTAssertEqual(roster.map(\.seat), [0, 0, 1, nil])
        // 访达用运行中的本地化名字，Dock 里的员工用 Dock 上的名字
        XCTAssertEqual(roster.map(\.name), ["Notes", "访达", "Safari", "Temp"])
    }

    func testListedAppsKeepTheirSeatWithoutDock() {
        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let installed = [
            DockApp(bundleID: "com.google.Chrome", name: "Google Chrome", url: chromeURL),
            DockApp(bundleID: "com.tencent.xinWeChat", name: "WeChat", url: nil),
            DockApp(bundleID: "com.apple.iWork.Pages", name: "Pages", url: nil),
        ]
        let running = [AppProcess(bundleID: "com.anthropic.claudefordesktop", name: "Claude", pid: 5)]
        let roster = Roster.merge(dock: [], installed: installed, running: running)
        // 没装的（ChatGPT）跳过，后面的往前坐
        XCTAssertEqual(roster.map(\.id), ["com.google.Chrome", "com.anthropic.claudefordesktop", "com.tencent.xinWeChat",
                                          "com.apple.iWork.Pages", "com.apple.finder"])
        XCTAssertEqual(roster.map(\.room), [.office, .office, .office, .tools, .dock])
        XCTAssertEqual(roster.map(\.seat), [0, 1, 2, 0, 0])
        XCTAssertEqual(roster.map(\.kind), [.staff, .staff, .staff, .staff, .staff])
        XCTAssertEqual(roster[0].bundleURL, chromeURL)
        XCTAssertEqual(roster[0].name, "Google Chrome")
    }

    func testUnlistedDockAppsJoinTheDockRoom() {
        let dock = [
            DockApp(bundleID: "com.example.Pinned", name: "Pinned", url: nil),
            DockApp(bundleID: "com.apple.Maps", name: "Maps", url: nil),
            DockApp(bundleID: "com.apple.apps.launcher", name: "Apps", url: nil),
        ]
        let roster = Roster.merge(dock: dock, running: [])
        XCTAssertEqual(roster.map(\.id), ["com.apple.finder", "com.apple.apps.launcher", "com.apple.Maps", "com.example.Pinned"])
        XCTAssertEqual(roster.map(\.room), [.dock, .dock, .dock, .dock])
        XCTAssertEqual(roster.map(\.seat), [0, 1, 2, 3])
    }

    func testRunningIDWinsASharedSlot() {
        let installed = [
            DockApp(bundleID: "com.openai.chat", name: "ChatGPT", url: nil),
            DockApp(bundleID: "com.openai.codex", name: "ChatGPT", url: nil),
        ]
        let running = [AppProcess(bundleID: "com.openai.codex", name: "ChatGPT", pid: 7)]
        let roster = Roster.merge(dock: [], installed: installed, running: running)
        XCTAssertEqual(roster.first?.id, "com.openai.codex")
        XCTAssertEqual(roster.first?.room, .office)
        XCTAssertFalse(roster.contains { $0.id == "com.openai.chat" })
    }

    func testEveryListedIDIsUnique() {
        XCTAssertEqual(Set(Roster.listedIDs).count, Roster.listedIDs.count)
        XCTAssertEqual(Roster.rooms.first { $0.room == .office }?.slots.count, 4)
        XCTAssertEqual(Roster.rooms.first { $0.room == .apple }?.slots.count, 12)
        XCTAssertEqual(Roster.rooms.first { $0.room == .tools }?.slots.count, 7)
    }

    func testFinderNotDuplicatedWhenInDock() {
        let dock = [DockApp(bundleID: "com.apple.finder", name: "Finder", url: nil)]
        let roster = Roster.merge(dock: dock, running: [])
        XCTAssertEqual(roster.map(\.id), ["com.apple.finder"])
        XCTAssertEqual(roster[0].name, "Finder")
    }

    func testDuplicatesCollapse() {
        let dock = [
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil),
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil),
        ]
        let running = [
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 1),
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 2),
        ]
        XCTAssertEqual(Roster.merge(dock: dock, running: running).map(\.id),
                       ["com.apple.finder", "com.apple.Safari", "com.example.Temp"])
    }

    func testFinderInDockAndRunningUsesDockLabel() {
        let dock = [DockApp(bundleID: "com.apple.finder", name: "Finder", url: nil)]
        let running = [AppProcess(bundleID: "com.apple.finder", name: "访达", pid: 10)]
        let roster = Roster.merge(dock: dock, running: running)
        XCTAssertEqual(roster.map(\.id), ["com.apple.finder"])
        XCTAssertEqual(roster[0].name, "Finder")
    }

    func testStaffURLFallsBackToRunning() {
        let safariURL = URL(string: "file:///Applications/Safari.app/")
        let tempURL = URL(string: "file:///Applications/Temp.app/")
        let dock = [DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil)]
        let running = [
            AppProcess(bundleID: "com.apple.Safari", name: "Safari", pid: 1, bundleURL: safariURL),
            AppProcess(bundleID: "com.example.Temp", name: "Temp", pid: 2, bundleURL: tempURL),
        ]
        let roster = Roster.merge(dock: dock, running: running)
        XCTAssertEqual(roster[1].bundleURL, safariURL)
        XCTAssertEqual(roster[2].bundleURL, tempURL)
    }

    func testKeepsLastDockWhenReadFails() {
        let last = [DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil)]
        XCTAssertEqual(DockReader.keepLastIfEmpty([], previous: last), last)
        let fresh = [DockApp(bundleID: "com.apple.Notes", name: "Notes", url: nil)]
        XCTAssertEqual(DockReader.keepLastIfEmpty(fresh, previous: last), fresh)
        XCTAssertEqual(DockReader.keepLastIfEmpty([], previous: []), [])
    }
}
