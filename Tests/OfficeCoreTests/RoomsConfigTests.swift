import XCTest
@testable import OfficeCore

final class RoomsConfigTests: XCTestCase {
    override func setUp() {
        Lang.current = .zh
    }

    override func tearDown() {
        Lang.current = .system()
    }
    private func parse(_ text: String) throws -> RoomsConfig {
        try RoomsConfig.parse(Data(text.utf8))
    }

    private func message(_ text: String) -> String {
        do {
            _ = try parse(text)
            return "没报错"
        } catch {
            return (error as? RoomsConfig.ParseError)?.description ?? "\(error)"
        }
    }

    func testParsesOfficesAndRooms() throws {
        let config = try parse("""
        {
          "offices": ["Google Chrome", " Claude "],
          "rooms": [
            { "name": "生活部", "apps": ["Phone", "Notes"] },
            { "name": "Dock 部", "apps": ["Finder"], "dock": true }
          ]
        }
        """)
        XCTAssertEqual(config, RoomsConfig(offices: ["Google Chrome", "Claude"], rooms: [
            .init(name: "生活部", apps: ["Phone", "Notes"]),
            .init(name: "Dock 部", apps: ["Finder"], dock: true),
        ]))
    }

    func testToleratesCurlyQuotesAndTrailingCommas() throws {
        let config = try parse("{ “offices”: [“Safari”,], “rooms”: [], }")
        XCTAssertEqual(config.offices, ["Safari"])
    }

    func testMissingKeysMeanEmpty() throws {
        XCTAssertEqual(try parse("{}"), RoomsConfig(offices: [], rooms: []))
    }

    func testExplainsMistakesInChinese() {
        XCTAssertEqual(message("{\n  \"offices\": [\"A\" \"B\"]\n}"), "第 2 行附近格式不对（引号、逗号或括号）")
        XCTAssertEqual(message("[]"), "最外层要是 { … }")
        XCTAssertTrue(message("{\"offices\": \"Safari\"}").hasPrefix("offices 要是一串"))
        XCTAssertEqual(message("{\"rooms\": [{\"apps\": []}]}"), "rooms 里第 1 个缺 name（房间名字）")
        XCTAssertEqual(message("{\"rooms\": [{\"name\": \"A\", \"dock\": \"yes\"}]}"), "「A」的 dock 只能写 true 或 false")
    }

    func testExplainsMistakesInEnglishToo() {
        Lang.current = .en
        XCTAssertEqual(message("{\n  \"offices\": [\"A\" \"B\"]\n}"), "line 2 looks malformed (quotes, commas or brackets)")
        XCTAssertEqual(message("{\"rooms\": [{\"apps\": []}]}"), "room 1 is missing a name")
    }

    func testFollowsTheFirstPreferredLanguage() {
        XCTAssertEqual(Lang.system(preferred: ["zh-Hans-CN", "en"]), .zh)
        XCTAssertEqual(Lang.system(preferred: ["en-US", "zh-Hans"]), .en)
        XCTAssertEqual(Lang.system(preferred: ["ja-JP"]), .en)
        XCTAssertEqual(Lang.system(preferred: []), .en)
    }

    func testDefaultComesFromTheDock() {
        let dock = [
            DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil),
            DockApp(bundleID: "com.apple.finder", name: "Finder", url: nil),
            DockApp(bundleID: "com.apple.Notes", name: "Notes", url: nil),
        ]
        XCTAssertEqual(RoomsConfig.fromDock(dock),
                       RoomsConfig(offices: [], rooms: [.init(name: "Dock", apps: ["Finder", "Safari", "Notes"], dock: true)]))
    }

    func testJSONRoundTripsAndKeepsChineseReadable() throws {
        let config = RoomsConfig(offices: ["WeChat"], rooms: [.init(name: "生活部", apps: ["Phone"], dock: true)])
        let text = String(decoding: config.json(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"name\": \"生活部\""))
        XCTAssertEqual(try RoomsConfig.parse(config.json()), config)
    }

    func testResolverMatchesBundleIDsAndNamesCaseInsensitively() {
        let candidates = [
            AppCandidate(bundleID: "com.apple.Safari", names: ["Safari"], url: nil),
            AppCandidate(bundleID: "com.tencent.xinWeChat", names: ["WeChat", "微信"],
                         url: URL(fileURLWithPath: "/Applications/WeChat.app")),
            AppCandidate(bundleID: "com.apple.mail", names: ["邮件"], url: nil),
            AppCandidate(bundleID: "com.apple.mail", names: ["Mail"], url: URL(fileURLWithPath: "/System/Applications/Mail.app")),
        ]
        let config = RoomsConfig(offices: ["微信", "Not Installed"], rooms: [
            .init(name: "A", apps: ["safari", "com.apple.mail"]),
            .init(name: "B", apps: [], dock: true),
            .init(name: "C", apps: [], dock: true),
        ])
        let resolved = RoomsResolver.resolve(config, candidates: candidates)
        // 没装的跳过；名字取第一个候选的第一个名字，路径取找得到的第一个
        XCTAssertEqual(resolved.offices, [DockApp(bundleID: "com.tencent.xinWeChat", name: "WeChat",
                                                  url: URL(fileURLWithPath: "/Applications/WeChat.app"))])
        XCTAssertEqual(resolved.rooms[0].apps.map(\.bundleID), ["com.apple.Safari", "com.apple.mail"])
        XCTAssertEqual(resolved.rooms[0].apps[1].name, "邮件")
        XCTAssertEqual(resolved.rooms[0].apps[1].url?.path, "/System/Applications/Mail.app")
        // 只有第一间标了 dock 的收留 Dock 里其他 app
        XCTAssertEqual(resolved.rooms.map(\.collectsDock), [false, true, false])
    }

    func testInstalledAppsFindsFinder() {
        let candidates = InstalledApps().candidates()
        XCTAssertTrue(candidates.contains { $0.bundleID == Roster.finderID && $0.names.contains("Finder") })
    }
}

final class RoomsFileTests: XCTestCase {
    private var dir: URL!

    override func tearDown() {
        Lang.current = .system()
    }

    override func setUpWithError() throws {
        Lang.current = .zh
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rooms-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testCreatesFromDockThenReloadsEditsAndKeepsLastGoodVersion() throws {
        let file = RoomsFile(url: dir.appendingPathComponent("AppOffice/rooms.json"))
        let dock = [DockApp(bundleID: "com.apple.Safari", name: "Safari", url: nil)]
        // Dock 还没读到：先不生成
        XCTAssertEqual(file.refresh(dock: []), .unchanged)
        XCTAssertNil(file.config)
        XCTAssertEqual(file.refresh(dock: dock), .created)
        XCTAssertEqual(file.config?.rooms.first?.apps, ["Finder", "Safari"])
        XCTAssertEqual(try RoomsConfig.parse(Data(contentsOf: file.url)), file.config)
        XCTAssertEqual(file.refresh(dock: dock), .unchanged)

        try Data("{\"offices\": [\"Safari\"]}".utf8).write(to: file.url)
        try touch(file.url, secondsLater: 2)
        XCTAssertEqual(file.refresh(dock: dock), .loaded)
        XCTAssertEqual(file.config?.offices, ["Safari"])

        try Data("{ oops".utf8).write(to: file.url)
        try touch(file.url, secondsLater: 4)
        guard case .failed(let message) = file.refresh(dock: dock) else { return XCTFail("应该报错") }
        XCTAssertTrue(message.contains("先按上一版排座"))
        XCTAssertEqual(file.config?.offices, ["Safari"])
        // 同一个坏文件只报一次
        XCTAssertEqual(file.refresh(dock: dock), .unchanged)
    }

    /// 文件修改时间精度有限，测试里手动往后拨
    private func touch(_ url: URL, secondsLater: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(secondsLater)], ofItemAtPath: url.path)
    }
}
