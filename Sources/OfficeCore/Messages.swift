import Foundation

/// 网页发来的操作请求（设计文档 5.3）
public enum OfficeAction: Equatable, Sendable {
    case ready
    case activate(String)
    case launch(String)
    case quit(String)

    /// body 是 WKScriptMessage.body（字典）或 JSON 字符串；认不出来返回 nil
    public static func parse(_ body: Any) -> OfficeAction? {
        var dict = body as? [String: Any]
        if dict == nil, let text = body as? String {
            dict = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        }
        guard let dict, let action = dict["action"] as? String else { return nil }
        if action == "ready" { return .ready }
        guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
        switch action {
        case "activate": return .activate(id)
        case "launch": return .launch(id)
        case "quit": return .quit(id)
        default: return nil
        }
    }
}

/// roster 消息里的一个员工（字段名即协议字段名）
public struct RosterItem: Encodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: EmployeeKind
    public var room: Room?
    public var seat: Int?
    public var color: String
    /// 128×128 PNG 的 base64，不带 data: 前缀
    public var iconPNG: String

    public init(id: String, name: String, kind: EmployeeKind, room: Room? = nil, seat: Int?, color: String, iconPNG: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.room = room
        self.seat = seat
        self.color = color
        self.iconPNG = iconPNG
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, room, seat, color, iconPNG }

    // 临时工的 room 和 seat 要显式写 null
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(room, forKey: .room)
        try c.encode(seat, forKey: .seat)
        try c.encode(color, forKey: .color)
        try c.encode(iconPNG, forKey: .iconPNG)
    }
}

/// 推给网页的消息
public enum OutboundMessage: Equatable, Sendable {
    case roster([RosterItem])
    case status(NetworkState, [EmployeeStatus])
    case paused(Bool)

    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        switch self {
        case .roster(let employees):
            data = try! encoder.encode(RosterBody(type: "roster", employees: employees))
        case .status(let network, let employees):
            data = try! encoder.encode(StatusBody(type: "status", network: network, employees: employees))
        case .paused(let paused):
            data = try! encoder.encode(PausedBody(type: "paused", paused: paused))
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct RosterBody: Encodable { let type: String; let employees: [RosterItem] }
private struct StatusBody: Encodable { let type: String; let network: NetworkState; let employees: [EmployeeStatus] }
private struct PausedBody: Encodable { let type: String; let paused: Bool }
