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

    /// 按 rooms.json 入座：先一排大办公室（每人一间），再一间间小办公室；装了就有座位，和 Dock、开没开无关。
    /// Dock 里不在名单上的 app 坐进标了 dock 的那间（没有就不坐）；剩下运行中的 app 是临时工。
    /// 返回的 rooms 第 0 间是大办公室那排，之后是小办公室，RosterEntry.room 是它的下标
    public static func merge(rooms: ResolvedRooms, dock: [DockApp], running: [AppProcess])
        -> (rooms: [RoomInfo], roster: [RosterEntry]) {
        let dockByID = Dictionary(dock.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let runningByID = Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let info = [RoomInfo(name: "offices", kind: .offices)] + rooms.rooms.map { RoomInfo(name: $0.name, kind: .shared) }
        var seen = Set<String>()
        var result: [RosterEntry] = []
        var seats = [Int](repeating: 0, count: info.count)
        func seat(_ app: DockApp, in room: Int) {
            guard seen.insert(app.bundleID).inserted else { return }
            // Dock 上的名字优先，其次运行时的名字
            let process = runningByID[app.bundleID]
            let name = dockByID[app.bundleID]?.name ?? process?.name ?? app.name
            let url = dockByID[app.bundleID]?.url ?? process?.bundleURL ?? app.url
            result.append(RosterEntry(id: app.bundleID, name: name, kind: .staff, room: room, seat: seats[room], bundleURL: url))
            seats[room] += 1
        }
        for app in rooms.offices { seat(app, in: 0) }
        for (i, room) in rooms.rooms.enumerated() {
            for app in room.apps { seat(app, in: i + 1) }
            if room.collectsDock { for app in dock { seat(app, in: i + 1) } }
        }
        for p in running where seen.insert(p.bundleID).inserted {
            result.append(RosterEntry(id: p.bundleID, name: p.name, kind: .temp, seat: nil, bundleURL: p.bundleURL))
        }
        return (info, result)
    }
}
