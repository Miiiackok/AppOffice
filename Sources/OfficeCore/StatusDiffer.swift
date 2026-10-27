/// 只挑出和上次不一样的员工状态；网页重新加载后调 reset 再全量推一次
public struct StatusDiffer {
    private var last: [String: EmployeeStatus] = [:]

    public init() {}

    public mutating func changes(_ statuses: [EmployeeStatus]) -> [EmployeeStatus] {
        let changed = statuses.filter { last[$0.id] != $0 }
        last = Dictionary(statuses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return changed
    }

    public mutating func reset() {
        last = [:]
    }
}
