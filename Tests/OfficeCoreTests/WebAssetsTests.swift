import XCTest
@testable import OfficeCore

final class WebAssetsTests: XCTestCase {
    private var root: URL!
    private var outside: URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data("<html>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("x".utf8).write(to: root.appendingPathComponent("assets/index-1.js"))
        try Data("y".utf8).write(to: root.appendingPathComponent("assets/a b.png"))
        outside = root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent)-outside.txt")
        try Data("secret".utf8).write(to: outside)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    func testResolvesFilesWithMimeTypes() {
        XCTAssertEqual(WebAssets.resolve(root: root, path: "/index.html")?.mime, "text/html")
        XCTAssertEqual(WebAssets.resolve(root: root, path: "/assets/index-1.js")?.mime, "text/javascript")
        XCTAssertEqual(WebAssets.resolve(root: root, path: "/")?.url.lastPathComponent, "index.html")
        XCTAssertEqual(WebAssets.resolve(root: root, path: "/assets/a b.png")?.mime, "image/png")
    }

    func testRejectsMissingFilesDirectoriesAndEscapes() {
        XCTAssertNil(WebAssets.resolve(root: root, path: "/nope.js"))
        // path 已解码，字面的 % 文件名不存在
        XCTAssertNil(WebAssets.resolve(root: root, path: "/assets/a%20b.png"))
        XCTAssertNil(WebAssets.resolve(root: root, path: "/assets"))
        XCTAssertNil(WebAssets.resolve(root: root, path: "/../\(outside.lastPathComponent)"))
        XCTAssertNil(WebAssets.resolve(root: root, path: "/assets/../../\(outside.lastPathComponent)"))
    }

    func testLocatesTheWebRoot() throws {
        // 环境变量优先
        XCTAssertEqual(WebAssets.locateRoot(bundle: Bundle(for: Self.self), environment: ["APP_OFFICE_WEB": root.path],
                                            sourceFile: "/nowhere/Sources/AppOffice/AppDelegate.swift")?.path, root.path)
        // 开发时：源码旁边仓库里的 web/dist
        let repo = root.appendingPathComponent("repo")
        let dist = repo.appendingPathComponent("web/dist")
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data("<html>".utf8).write(to: dist.appendingPathComponent("index.html"))
        let source = repo.appendingPathComponent("Sources/AppOffice/AppDelegate.swift").path
        XCTAssertEqual(WebAssets.locateRoot(bundle: Bundle(for: Self.self), environment: [:], sourceFile: source)?.path, dist.path)
        // 都没有
        XCTAssertNil(WebAssets.locateRoot(bundle: Bundle(for: Self.self), environment: [:],
                                          sourceFile: "/nowhere/Sources/AppOffice/AppDelegate.swift"))
    }
}
