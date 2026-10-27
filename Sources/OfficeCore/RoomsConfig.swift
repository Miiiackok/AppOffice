import AppKit
import Foundation

/// rooms.json：哪些 app 有自己的大办公室、有哪几间小办公室、里面坐谁。app 写名字或 bundle id 都行
public struct RoomsConfig: Codable, Equatable, Sendable {
    public struct SharedRoom: Codable, Equatable, Sendable {
        public var name: String
        public var apps: [String]
        /// Dock 里其他不在名单上的 app 也坐进这间（只认第一间这么写的）
        public var dock: Bool?

        public init(name: String, apps: [String], dock: Bool? = nil) {
            self.name = name
            self.apps = apps
            self.dock = dock
        }
    }

    /// 每个 app 一间大办公室
    public var offices: [String]
    public var rooms: [SharedRoom]

    public init(offices: [String], rooms: [SharedRoom]) {
        self.offices = offices
        self.rooms = rooms
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public var description: String
    }

    /// 读文件内容。顺手容忍文本编辑自动换成的弯引号和末尾多出来的逗号；写错了给一句看得懂的中文
    public static func parse(_ data: Data) throws -> RoomsConfig {
        var text = String(decoding: data, as: UTF8.self)
        for (curly, straight) in [("“", "\""), ("”", "\""), ("„", "\""), ("‘", "'"), ("’", "'")] {
            text = text.replacingOccurrences(of: curly, with: straight)
        }
        text = text.replacingOccurrences(of: #",(\s*[\]}])"#, with: "$1", options: .regularExpression)
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: Data(text.utf8))
        } catch {
            let index = (error as NSError).userInfo["NSJSONSerializationErrorIndex"] as? Int
            let line = index.map { i in text.prefix(i).filter { $0 == "\n" }.count + 1 }
            throw ParseError(description: line.map { L("第 \($0) 行附近格式不对（引号、逗号或括号）", "line \($0) looks malformed (quotes, commas or brackets)") }
                ?? L("格式不对（引号、逗号或括号）", "it is malformed (quotes, commas or brackets)"))
        }
        guard let root = json as? [String: Any] else { throw ParseError(description: L("最外层要是 { … }", "the top level must be { … }")) }
        let offices = try strings(root["offices"] ?? [], what: "offices")
        guard let rawRooms = (root["rooms"] ?? []) as? [Any] else { throw ParseError(description: L("rooms 要是 [ … ]", "rooms must be [ … ]")) }
        let rooms = try rawRooms.enumerated().map { i, raw -> SharedRoom in
            guard let room = raw as? [String: Any] else { throw ParseError(description: L("rooms 里第 \(i + 1) 个要是 { … }", "room \(i + 1) must be { … }")) }
            guard let name = room["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ParseError(description: L("rooms 里第 \(i + 1) 个缺 name（房间名字）", "room \(i + 1) is missing a name"))
            }
            let apps = try strings(room["apps"] ?? [], what: L("「\(name)」的 apps", "the apps of \"\(name)\""))
            if let dock = room["dock"], !(dock is Bool) { throw ParseError(description: L("「\(name)」的 dock 只能写 true 或 false", "dock in \"\(name)\" must be true or false")) }
            return SharedRoom(name: name, apps: apps, dock: room["dock"] as? Bool)
        }
        return RoomsConfig(offices: offices, rooms: rooms)
    }

    private static func strings(_ value: Any, what: String) throws -> [String] {
        guard let list = value as? [Any], list.allSatisfy({ $0 is String }) else {
            throw ParseError(description: L("\(what) 要是一串用引号括起来的 app 名字，比如 [\"Safari\", \"Notes\"]",
                                             "\(what) must be a list of quoted app names, like [\"Safari\", \"Notes\"]"))
        }
        return list.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 第一次打开时的默认名单：没有大办公室，访达和 Dock 里的 app 都坐一间小办公室，以后新加到 Dock 的也进来
    public static func fromDock(_ dock: [DockApp]) -> RoomsConfig {
        var names = ["Finder"]
        for app in dock where app.bundleID != Roster.finderID && !names.contains(app.name) { names.append(app.name) }
        return RoomsConfig(offices: [], rooms: [SharedRoom(name: "Dock", apps: names, dock: true)])
    }

    /// 写回文件用：缩进两格，中文不转义
    public func json() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = (try? encoder.encode(self)) ?? Data("{}".utf8)
        // JSONEncoder 缩进是 2 空格但冒号前有空格（" : "），改成常见写法
        return Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\" : ", with: "\": ").utf8)
    }
}

/// 按名字找到的一个 app 候选：Dock、正在运行的、装在电脑上的
public struct AppCandidate: Equatable, Sendable {
    public var bundleID: String
    /// 能用来匹配的名字：Dock 上的名字、运行时的名字、文件名、本地化名字
    public var names: [String]
    public var url: URL?

    public init(bundleID: String, names: [String], url: URL?) {
        self.bundleID = bundleID
        self.names = names
        self.url = url
    }
}

/// 名字对上 app 之后的房间名单
public struct ResolvedRooms: Equatable, Sendable {
    public struct Room: Equatable, Sendable {
        public var name: String
        public var apps: [DockApp]
        public var collectsDock: Bool

        public init(name: String, apps: [DockApp], collectsDock: Bool) {
            self.name = name
            self.apps = apps
            self.collectsDock = collectsDock
        }
    }

    public var offices: [DockApp]
    public var rooms: [Room]

    public init(offices: [DockApp], rooms: [Room]) {
        self.offices = offices
        self.rooms = rooms
    }

    public static let empty = ResolvedRooms(offices: [], rooms: [])
}

public enum RoomsResolver {
    /// 名单里的每一项先当 bundle id 找，再按名字找（不分大小写）；找不到（没装）就跳过。
    /// 候选按 Dock、运行中、已安装的顺序给，名字取第一个候选的第一个名字
    public static func resolve(_ config: RoomsConfig, candidates: [AppCandidate]) -> ResolvedRooms {
        let lookup = { (entry: String) -> DockApp? in
            let key = entry.lowercased()
            let hit = candidates.first { $0.bundleID.lowercased() == key }
                ?? candidates.first { $0.names.contains { $0.lowercased() == key } }
            guard let hit else { return nil }
            // 同一个 app 可能有好几个候选（Dock 上一个、装的一个），合起来
            let same = candidates.filter { $0.bundleID == hit.bundleID }
            let name = same.lazy.compactMap(\.names.first).first ?? entry
            return DockApp(bundleID: hit.bundleID, name: name, url: same.lazy.compactMap(\.url).first)
        }
        let collector = config.rooms.firstIndex { $0.dock == true }
        return ResolvedRooms(
            offices: config.offices.compactMap(lookup),
            rooms: config.rooms.enumerated().map { i, room in
                ResolvedRooms.Room(name: room.name, apps: room.apps.compactMap(lookup), collectsDock: i == collector)
            })
    }
}

/// 电脑上装的 app（应用程序、系统应用、~/Applications、访达），用来按名字找 app。非线程安全
public final class InstalledApps {
    static let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                          "/System/Applications/Utilities", "/System/Library/CoreServices",
                          NSHomeDirectory() + "/Applications"]
    private let refresh: TimeInterval
    private var cache: [AppCandidate] = []
    private var scannedAt: Date?

    public init(refresh: TimeInterval = 60) {
        self.refresh = refresh
    }

    /// 一分钟扫一次文件夹
    public func candidates(now: Date = Date()) -> [AppCandidate] {
        if let at = scannedAt, now.timeIntervalSince(at) < refresh { return cache }
        cache = Self.scan()
        scannedAt = now
        return cache
    }

    static func scan() -> [AppCandidate] {
        let fm = FileManager.default
        var result: [AppCandidate] = []
        for folder in folders {
            let base = URL(fileURLWithPath: folder).standardizedFileURL
            guard let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
                let file = url.deletingPathExtension().lastPathComponent
                var display = fm.displayName(atPath: url.path)
                if display.hasSuffix(".app") { display = String(display.dropLast(4)) }
                let localized = Bundle(url: url)?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                let names = [file, display, localized].compactMap { $0 }.reduce(into: [String]()) { list, n in
                    if !list.contains(n) { list.append(n) }
                }
                result.append(AppCandidate(bundleID: id, names: names, url: url))
            }
        }
        return result
    }
}
