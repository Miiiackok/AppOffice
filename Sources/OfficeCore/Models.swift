import Foundation

public enum EmployeeKind: String, Codable, Sendable {
    case staff, temp
}

/// 员工状态，顺序即优先级（见设计文档 2.2）
public enum EmployeeState: String, Codable, Sendable, CaseIterable {
    case hung, offline, launching, focused, snacking, working, idle, resting, off
}

/// 一个正在运行的普通 app 的快照
public struct AppProcess: Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public var pid: Int32
    public var bundleURL: URL?
    public var launchDate: Date?
    public var isFinishedLaunching: Bool
    public var isActive: Bool

    public init(bundleID: String, name: String, pid: Int32, bundleURL: URL? = nil, launchDate: Date? = nil,
                isFinishedLaunching: Bool = true, isActive: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
        self.bundleURL = bundleURL
        self.launchDate = launchDate
        self.isFinishedLaunching = isFinishedLaunching
        self.isActive = isActive
    }
}

public struct ProcessMetrics: Equatable, Sendable {
    /// 占单核的百分比，可以超过 100
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(cpuPercent: Double, memoryBytes: UInt64) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    public static let zero = ProcessMetrics(cpuPercent: 0, memoryBytes: 0)
}

/// 正式员工坐哪个房间（名单见 Roster.rooms）
public enum Room: String, Codable, Sendable, CaseIterable {
    /// 常用 app，每人一间大办公室
    case office
    /// 不常用的 12 个，合用一间小办公室
    case apple
    /// iWork、App Store、iPhone 镜像、Siri、系统设置，合用一间小办公室
    case tools
    /// 访达、启动台、Safari、地图，以及 Dock 里其他不在名单上的 app
    case dock
}

/// 名单上的一个员工：正式员工坐 room 里的第 seat 个位置，临时工 room 和 seat 都是 nil
public struct RosterEntry: Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: EmployeeKind
    public var room: Room?
    public var seat: Int?
    public var bundleURL: URL?

    public init(id: String, name: String, kind: EmployeeKind, room: Room? = nil, seat: Int?, bundleURL: URL?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.room = room
        self.seat = seat
        self.bundleURL = bundleURL
    }
}

/// 每秒推给网页的状态（字段名即协议字段名）
public struct EmployeeStatus: Codable, Equatable, Sendable {
    public var id: String
    public var state: EmployeeState
    /// 封顶 100
    public var cpu: Int
    public var memMB: Int
    /// 启动时间，Unix 秒；未运行为 nil
    public var launchedAt: Int?

    public init(id: String, state: EmployeeState, cpu: Int, memMB: Int, launchedAt: Int?) {
        self.id = id
        self.state = state
        self.cpu = cpu
        self.memMB = memMB
        self.launchedAt = launchedAt
    }

    // 默认合成的编码会跳过 nil，协议要求显式 null
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(state, forKey: .state)
        try c.encode(cpu, forKey: .cpu)
        try c.encode(memMB, forKey: .memMB)
        try c.encode(launchedAt, forKey: .launchedAt)
    }
}

public enum NetworkState: String, Codable, Sendable {
    case online, offline
}
