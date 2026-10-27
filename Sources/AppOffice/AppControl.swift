import AppKit
import OfficeCore

/// 执行网页发来的启动 / 切换 / 退出
enum AppControl {
    /// bundleID 用来在按路径启动失败时换 LaunchServices 找到的位置再试一次
    static func perform(_ operation: AppOperation, bundleID: String?, onLaunchFailed: @escaping (String) -> Void) {
        switch operation {
        case .none:
            break
        case .activate(let pid):
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            // macOS 14+ 上从没当过前台的 accessory app 调 activate() 会被系统静默拒绝；
            // 走 LaunchServices 打开已在跑的 app，等同点 Dock 图标，能可靠切过去
            guard let url = app.bundleURL else {
                app.activate()
                return
            }
            open(url) { error in
                if let error { NSLog("AppOffice: 切换到 %@ 失败：%@", url.lastPathComponent, error.localizedDescription) }
            }
        case .quit(let pid):
            // 等同 ⌘Q：有没保存的文档时 app 自己会弹窗
            NSRunningApplication(processIdentifier: pid)?.terminate()
        case .launch(let url):
            open(url) { error in
                guard let error else { return }
                // 名单里的路径可能过期（app 被挪走、Dock 记的是旧位置）：换系统找到的位置再试一次
                if let bundleID,
                   let other = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                   other.standardizedFileURL != url.standardizedFileURL {
                    open(other) { retryError in
                        guard let retryError else { return }
                        report(url, retryError, onLaunchFailed)
                    }
                } else {
                    report(url, error, onLaunchFailed)
                }
            }
        }
    }

    private static func open(_ url: URL, completion: @escaping (Error?) -> Void) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in completion(error) }
    }

    private static func report(_ url: URL, _ error: Error, _ onLaunchFailed: @escaping (String) -> Void) {
        let name = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async { onLaunchFailed(L("\(name) 没能打开：\(error.localizedDescription)", "Couldn't open \(name): \(error.localizedDescription)")) }
    }
}
