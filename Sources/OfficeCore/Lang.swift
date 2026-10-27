import Foundation

/// 界面语言：中文或英文。默认跟随系统（首选语言是中文就中文，其他都英文）
public enum Lang: String, Codable, Sendable {
    case zh, en

    public static func system(preferred: [String] = Locale.preferredLanguages) -> Lang {
        preferred.first?.lowercased().hasPrefix("zh") == true ? .zh : .en
    }

    /// 只在主线程改；读的地方（菜单、通知、rooms.json 报错）也都在主线程
    nonisolated(unsafe) public static var current: Lang = .system()
}

/// 按当前语言二选一
public func L(_ zh: String, _ en: String) -> String {
    Lang.current == .en ? en : zh
}
