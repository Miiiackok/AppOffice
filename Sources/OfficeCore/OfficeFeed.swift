import Foundation

public struct AppIcon: Equatable, Sendable {
    /// 128×128 PNG 的 base64
    public var pngBase64: String
    /// 主色 #RRGGBB
    public var color: String

    public init(pngBase64: String, color: String) {
        self.pngBase64 = pngBase64
        self.color = color
    }
}

public protocol IconProviding {
    func icon(for entry: RosterEntry) -> AppIcon
}

/// 决定什么时候给网页发什么：ready 之前不发；名单变了才发 roster（总在 status 前面）；状态只发变化的
/// 只在主线程用
public struct OfficeFeed {
    private let icons: IconProviding
    private var isReady = false
    private var paused = false
    private var last: OfficeSnapshot?
    private var sentRoster: (rooms: [RoomInfo], items: [RosterItem])?
    private var sentNetwork: NetworkState?
    private var differ = StatusDiffer()
    private var overrides: [String: EmployeeState] = [:]

    public init(icons: IconProviding) {
        self.icons = icons
    }

    /// 调试模拟中的员工
    public var simulated: [String: EmployeeState] { overrides }

    /// 每拍调一次
    public mutating func update(_ snapshot: OfficeSnapshot) -> [OutboundMessage] {
        last = snapshot
        return isReady ? messages(for: snapshot) : []
    }

    /// 网页（重新）加载完成：全量 roster → 全量 status → paused
    public mutating func ready() -> [OutboundMessage] {
        isReady = true
        sentRoster = nil
        sentNetwork = nil
        differ.reset()
        var out = last.map { messages(for: $0) } ?? []
        out.append(.paused(paused))
        return out
    }

    public mutating func setPaused(_ value: Bool) -> [OutboundMessage] {
        guard value != paused else { return [] }
        paused = value
        return isReady ? [.paused(value)] : []
    }

    /// 调试：强制某个员工进入某个状态；nil 取消
    public mutating func simulate(_ id: String, _ state: EmployeeState?) -> [OutboundMessage] {
        overrides[id] = state
        guard isReady, let last else { return [] }
        return messages(for: last)
    }

    /// 网页进程挂了要重新加载：等下一个 ready
    public mutating func reset() {
        isReady = false
    }

    private mutating func messages(for snapshot: OfficeSnapshot) -> [OutboundMessage] {
        var out: [OutboundMessage] = []
        let roster = snapshot.roster.map { e -> RosterItem in
            let icon = icons.icon(for: e)
            return RosterItem(id: e.id, name: e.name, kind: e.kind, room: e.room, seat: e.seat, color: icon.color, iconPNG: icon.pngBase64)
        }
        if roster != sentRoster?.items || snapshot.rooms != sentRoster?.rooms {
            out.append(.roster(snapshot.rooms, roster))
            sentRoster = (snapshot.rooms, roster)
        }
        let statuses = snapshot.statuses.map { s -> EmployeeStatus in
            var s = s
            if let forced = overrides[s.id] { s.state = forced }
            return s
        }
        let changed = differ.changes(statuses)
        // 只有网络变了也要发（changed 可以为空）
        if !changed.isEmpty || snapshot.network != sentNetwork {
            out.append(.status(snapshot.network, changed))
            sentNetwork = snapshot.network
        }
        return out
    }
}
