import Foundation

/// office://app/... → 网页资源目录里的文件
public enum WebAssets {
    public static let scheme = "office"
    public static let indexURL = URL(string: "office://app/index.html")!

    static let mimeTypes = [
        "html": "text/html", "js": "text/javascript", "mjs": "text/javascript", "css": "text/css",
        "json": "application/json", "png": "image/png", "svg": "image/svg+xml", "ico": "image/x-icon",
        "woff2": "font/woff2",
    ]

    /// URL 路径 → 文件和 MIME；不存在、是目录、跑出资源目录都返回 nil
    /// path 是已经解码过的 URL.path（不再做百分号解码）
    public static func resolve(root: URL, path: String) -> (url: URL, mime: String)? {
        var relative = path
        while relative.hasPrefix("/") { relative.removeFirst() }
        if relative.isEmpty { relative = "index.html" }
        let base = root.standardizedFileURL
        let file = base.appendingPathComponent(relative).standardizedFileURL
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        var isDirectory: ObjCBool = false
        guard file.path.hasPrefix(prefix),
              FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return (file, mimeTypes[file.pathExtension.lowercased()] ?? "application/octet-stream")
    }

    /// 网页资源目录：APP_OFFICE_WEB → app 包里的 Resources/web → 仓库里的 web/dist（开发时）
    public static func locateRoot(bundle: Bundle = .main,
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  sourceFile: String = #filePath) -> URL? {
        let hasIndex = { (dir: URL) in FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path) }
        if let custom = environment["APP_OFFICE_WEB"] {
            let dir = URL(fileURLWithPath: custom)
            if hasIndex(dir) { return dir }
        }
        if let bundled = bundle.resourceURL?.appendingPathComponent("web"), hasIndex(bundled) { return bundled }
        // sourceFile 是 <仓库>/Sources/<target>/<文件>.swift
        let repo = URL(fileURLWithPath: sourceFile).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dist = repo.appendingPathComponent("web/dist")
        return hasIndex(dist) ? dist : nil
    }
}
