import AppKit
import Foundation

public struct DockApp: Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public var url: URL?

    public init(bundleID: String, name: String, url: URL?) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
    }
}

public enum DockReader {
    public static func parse(_ persistentApps: [[String: Any]]) -> [DockApp] {
        persistentApps.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let id = data["bundle-identifier"] as? String else { return nil }
            let fileData = data["file-data"] as? [String: Any]
            let urlString = fileData?["_CFURLString"] as? String
            // _CFURLStringType 为 0 时存的是路径，15 是 file:// URL
            let isPath = (fileData?["_CFURLStringType"] as? Int) == 0
            let url = urlString.flatMap { isPath ? URL(fileURLWithPath: $0) : URL(string: $0) }
            return DockApp(bundleID: id, name: data["file-label"] as? String ?? id, url: url)
        }
    }

    /// 读当前用户 Dock 里固定的 app
    public static func load() -> [DockApp] {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let raw = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] ?? []
        return parse(raw)
    }

    /// Dock 偶尔读不到（返回空）时沿用上一次的，免得所有正式员工"下班走人"
    public static func keepLastIfEmpty(_ fresh: [DockApp], previous: [DockApp]) -> [DockApp] {
        fresh.isEmpty ? previous : fresh
    }
}

public enum Roster {
    public static let finderID = "com.apple.finder"
    static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    /// 每个房间按顺序坐谁。一个位置可以写几个 bundle id（同一个 app 换过 id），用找到的第一个
    public static let rooms: [(room: Room, slots: [[String]])] = [
        (.office, [["com.google.Chrome"], ["com.anthropic.claudefordesktop"],
                   ["com.openai.chat", "com.openai.codex"], ["com.tencent.xinWeChat"]]),
        (.apple, [["com.apple.mobilephone"], ["com.apple.iCal"], ["com.apple.AddressBook"], ["com.apple.Notes"],
                  ["com.apple.reminders"], ["com.apple.TV"], ["com.apple.Music"], ["com.apple.Photos"],
                  ["com.apple.FaceTime"], ["com.apple.MobileSMS"], ["com.apple.mail"], ["com.apple.games"]]),
        (.tools, [["com.apple.iWork.Keynote"], ["com.apple.iWork.Numbers"], ["com.apple.iWork.Pages"],
                  ["com.apple.AppStore"], ["com.apple.ScreenContinuity"], ["com.apple.campo"],
                  ["com.apple.systempreferences"]]),
        (.dock, [[finderID], ["com.apple.apps.launcher"], ["com.apple.Safari"], ["com.apple.Maps"]]),
    ]

    /// 名单上所有的 bundle id
    public static var listedIDs: [String] { rooms.flatMap { $0.slots.joined() } }

    /// 名单上的 app 按房间入座（Dock 里没有、没运行、但装了的也算，没装的跳过）；
    /// Dock 里其他 app 接着坐 dock 房间；剩下运行中的 app 是临时工
    public static func merge(dock: [DockApp], installed: [DockApp] = [], running: [AppProcess]) -> [RosterEntry] {
        let dockByID = Dictionary(dock.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let installedByID = Dictionary(installed.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let runningByID = Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        // 访达总在，Dock 上没有它时用运行中的名字
        let finder = DockApp(bundleID: finderID,
                             name: dockByID[finderID]?.name ?? runningByID[finderID]?.name ?? "Finder", url: finderURL)
        let known = { (id: String) -> Bool in
            id == finderID || dockByID[id] != nil || runningByID[id] != nil || installedByID[id] != nil
        }
        var seen = Set<String>()
        var result: [RosterEntry] = []
        var seats: [Room: Int] = [:]
        func seat(_ id: String, in room: Room) {
            guard seen.insert(id).inserted else { return }
            let app = id == finderID ? finder : dockByID[id]
            let process = runningByID[id]
            let name = app?.name ?? process?.name ?? installedByID[id]?.name ?? id
            let url = app?.url ?? process?.bundleURL ?? installedByID[id]?.url
            let n = seats[room, default: 0]
            seats[room] = n + 1
            result.append(RosterEntry(id: id, name: name, kind: .staff, room: room, seat: n, bundleURL: url))
        }
        for (room, slots) in rooms {
            for ids in slots {
                // 同一个位置有好几个 id 都在时，正在运行的优先
                if let id = ids.first(where: { runningByID[$0] != nil }) ?? ids.first(where: known) {
                    seat(id, in: room)
                }
            }
        }
        for app in dock { seat(app.bundleID, in: .dock) }
        for p in running where seen.insert(p.bundleID).inserted {
            result.append(RosterEntry(id: p.bundleID, name: p.name, kind: .temp, seat: nil, bundleURL: p.bundleURL))
        }
        return result
    }
}

/// 名单上的 app 装在哪：没在 Dock 里、也没运行时靠它找到名字和位置
public enum InstalledApps {
    public static func find(_ ids: [String]) -> [DockApp] {
        ids.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let display = FileManager.default.displayName(atPath: url.path)
            let name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
            return DockApp(bundleID: id, name: name, url: url)
        }
    }
}
