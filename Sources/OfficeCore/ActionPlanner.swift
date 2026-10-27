import Foundation

public enum AppOperation: Equatable, Sendable {
    case launch(URL)
    case activate(Int32)
    case quit(Int32)
    case none
}

public enum ActionPlanner {
    /// 网页看到的状态可能慢一拍：launch 在跑的 app 就切过去，activate 没在跑的就启动；访达不退出
    public static func plan(_ action: OfficeAction, running: [AppProcess], urlFor: (String) -> URL?) -> AppOperation {
        switch action {
        case .ready:
            return .none
        case .activate(let id), .launch(let id):
            if let p = running.first(where: { $0.bundleID == id }) { return .activate(p.pid) }
            return urlFor(id).map(AppOperation.launch) ?? .none
        case .quit(let id):
            guard id != Roster.finderID, let p = running.first(where: { $0.bundleID == id }) else { return .none }
            return .quit(p.pid)
        }
    }
}
