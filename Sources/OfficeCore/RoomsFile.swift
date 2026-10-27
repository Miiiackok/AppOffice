import Foundation

/// rooms.json 放在 ~/Library/Application Support/AppOffice/：没有就按 Dock 生成；改了就重新读；写坏了沿用上一版
public final class RoomsFile {
    public enum Change: Equatable {
        case unchanged
        case created
        case loaded
        /// 写坏了（或写不进去），配置沿用上一版；附一句给人看的话
        case failed(String)
    }

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("AppOffice/rooms.json")
    }

    public let url: URL
    public private(set) var config: RoomsConfig?
    private var loadedStamp: Date?

    public init(url: URL = RoomsFile.defaultURL) {
        self.url = url
    }

    /// 每拍调一次，平时只看一眼修改时间
    public func refresh(dock: [DockApp]) -> Change {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: url.path) else {
            // 还没读到 Dock 就等下一拍，免得生成一个空名单
            guard !dock.isEmpty else { return .unchanged }
            let fresh = RoomsConfig.fromDock(dock)
            config = fresh
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fresh.json().write(to: url, options: .atomic)
                loadedStamp = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                return .created
            } catch {
                return .failed(L("房间名单写不进 \(url.path)：\(error.localizedDescription)",
                                 "Couldn't write the room list to \(url.path): \(error.localizedDescription)"))
            }
        }
        let stamp = attributes[.modificationDate] as? Date
        if stamp == loadedStamp, config != nil { return .unchanged }
        loadedStamp = stamp
        do {
            config = try RoomsConfig.parse(Data(contentsOf: url))
            return .loaded
        } catch {
            let reason = (error as? RoomsConfig.ParseError)?.description ?? error.localizedDescription
            return .failed(L("rooms.json 写错了：\(reason)。先按上一版排座", "rooms.json has a mistake: \(reason). Keeping the previous seating"))
        }
    }
}
