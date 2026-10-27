import AppKit
import ApplicationServices
import OfficeCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let defaults = UserDefaults.standard
    private let loop = MonitorLoop()
    private var feed = OfficeFeed(icons: WorkspaceIcons())
    private var latest: OfficeSnapshot?
    private var bridge: WebBridge?
    private var panel: OfficePanel!
    private var menuBar: MenuBarController!
    private let notice = NSTextField(labelWithString: "")
    private var hovering = false
    private var screenLocked = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["showOffice": true, "pinOnTop": true, "translucent": false, "language": "auto"])
        applyLanguage()
        // swift run 时没有 bundle id，用不了通知中心
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        panel = OfficePanel(content: makeContent())
        panel.pinned = defaults.bool(forKey: "pinOnTop")
        panel.onHoverChange = { [weak self] inside in
            self?.hovering = inside
            self?.applyTranslucency()
            if !inside { self?.bridge?.hover(atWindowPoint: nil) }
        }
        panel.onMouseMove = { [weak self] point in self?.bridge?.hover(atWindowPoint: point) }
        observeVisibility()
        menuBar = makeMenuBar()

        loop.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.latest = snapshot
            self.bridge?.send(self.feed.update(snapshot))
        }
        loop.onRoomsProblem = { [weak self] message in self?.notify(message) }
        loop.start()
        bridge?.load()
        if defaults.bool(forKey: "showOffice") { panel.orderFrontRegardless() }
        resetHover()
        updatePaused()
    }

    /// 已经在跑时再双击 app：显示办公室（同菜单里的"显示办公室"）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOffice = true
        return true
    }

    /// 自己在前台时也弹横幅（默认会被系统吞掉）
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    // MARK: - 窗口内容

    private func makeContent() -> NSView {
        let container = NSView()
        notice.alignment = .center
        notice.textColor = .secondaryLabelColor
        notice.isHidden = true
        notice.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        if let root = WebAssets.locateRoot() {
            let bridge = WebBridge(webRoot: root)
            bridge.webView.autoresizingMask = [.width, .height]
            container.addSubview(bridge.webView)
            bridge.onAction = { [weak self] action in self?.handle(action) }
            bridge.onCrash = { [weak self] in self?.feed.reset() }
            bridge.onGiveUp = { [weak self] in self?.showNotice(L("网页反复崩溃，已停止重新加载", "The office page keeps crashing, stopped reloading it")) }
            bridge.onLoadFailed = { [weak self] message in self?.showNotice(L("网页没加载出来：\(message)", "The office page didn't load: \(message)")) }
            self.bridge = bridge
        } else {
            showNotice(L("找不到网页资源：先在 web/ 里运行 npm run build", "Web assets not found: run npm run build in web/ first"))
        }
        container.addSubview(notice)
        container.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: container, queue: .main) { [weak self] _ in
            self?.layout(container)
        }
        return container
    }

    private func layout(_ container: NSView) {
        bridge?.webView.frame = container.bounds
        notice.frame = NSRect(x: 12, y: container.bounds.midY - 10, width: max(0, container.bounds.width - 24), height: 20)
    }

    private func showNotice(_ text: String) {
        notice.stringValue = text
        notice.isHidden = false
    }

    // MARK: - 网页操作

    private func handle(_ action: OfficeAction) {
        if action == .ready {
            notice.isHidden = true
            // 先告诉网页用什么语言，再发名单
            bridge?.send([.locale(Lang.current)] + feed.ready())
            updatePaused()
            return
        }
        let roster = latest?.roster ?? []
        // 优先用名单里记下的 app 路径（必须是本地文件且还在），否则问 LaunchServices
        let operation = ActionPlanner.plan(action, running: loop.running) { id in
            if let url = roster.first(where: { $0.id == id })?.bundleURL,
               url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
        let appID: String? = switch action {
        case .ready: nil
        case .activate(let id), .launch(let id), .quit(let id): id
        }
        switch (action, operation) {
        case (.launch(let id), .none), (.activate(let id), .none):
            let name = roster.first(where: { $0.id == id })?.name ?? id
            notify(L("找不到这个 app：\(name)", "Can't find this app: \(name)"))
        default:
            AppControl.perform(operation, bundleID: appID) { [weak self] message in self?.notify(message) }
        }
    }

    /// 打不开 app、rooms.json 写坏了这类事弹个横幅
    private func notify(_ message: String) {
        NSLog("AppOffice: %@", message)
        // swift run 时没有 bundle id，用不了通知中心
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "AppOffice"
            content.body = message
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // MARK: - 显示、钉住、透明、暂停

    private var showOffice: Bool {
        get { panel.isVisible }
        set {
            defaults.set(newValue, forKey: "showOffice")
            if newValue {
                panel.orderFrontRegardless()
                resetHover()
            } else {
                panel.orderOut(nil)
            }
            updatePaused()
        }
    }

    private func applyTranslucency() {
        panel.alphaValue = defaults.bool(forKey: "translucent") && !hovering ? 0.5 : 1
    }

    /// 窗口隐藏期间收不到鼠标进出事件：显示时按鼠标当前位置重新算悬停
    private func resetHover() {
        hovering = panel.isVisible && panel.frame.contains(NSEvent.mouseLocation)
        applyTranslucency()
    }

    private func observeVisibility() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        center.addObserver(self, selector: #selector(panelWillClose), name: NSWindow.willCloseNotification, object: panel)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenDidLock), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenDidUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func visibilityChanged() { updatePaused() }

    @objc private func panelWillClose() {
        defaults.set(false, forKey: "showOffice")
        hovering = false
        applyTranslucency()
        DispatchQueue.main.async { self.updatePaused() }
    }

    @objc private func screenDidLock() {
        screenLocked = true
        updatePaused()
    }

    @objc private func screenDidUnlock() {
        screenLocked = false
        updatePaused()
    }

    /// 窗口隐藏、被完全挡住或锁屏时网页停止渲染
    private func updatePaused() {
        let paused = !panel.isVisible || !panel.occlusionState.contains(.visible) || screenLocked
        loop.paused = paused
        bridge?.send(feed.setPaused(paused))
    }

    // MARK: - 菜单栏

    private func makeMenuBar() -> MenuBarController {
        MenuBarController(
            toggles: [
                .init(title: { L("显示办公室", "Show Office") }, get: { [weak self] in self?.showOffice ?? false },
                      set: { [weak self] in self?.showOffice = $0 }),
                .init(title: { L("钉在最上层", "Keep on Top") }, get: { [weak self] in self?.panel.pinned ?? false },
                      set: { [weak self] in
                          self?.defaults.set($0, forKey: "pinOnTop")
                          self?.panel.pinned = $0
                      }),
                .init(title: { L("透明模式", "Translucent When Idle") }, get: { [weak self] in self?.defaults.bool(forKey: "translucent") ?? false },
                      set: { [weak self] in
                          self?.defaults.set($0, forKey: "translucent")
                          self?.applyTranslucency()
                      }),
            ],
            hangDetectionAvailable: { [weak self] in self?.latest?.hangDetectionAvailable ?? true },
            enableHangDetection: { [weak self] in self?.askForAccessibility() },
            employees: { [weak self] in self?.latest?.roster.map { (id: $0.id, name: $0.name) } ?? [] },
            simulated: { [weak self] in self?.feed.simulated ?? [:] },
            simulate: { [weak self] id, state in
                guard let self else { return }
                self.bridge?.send(self.feed.simulate(id, state))
            },
            editRooms: { [weak self] in self?.editRooms() },
            language: { [weak self] in self?.defaults.string(forKey: "language") ?? "auto" },
            setLanguage: { [weak self] in self?.setLanguage($0) })
    }

    /// "auto" 跟随系统，"zh"、"en" 固定；网页跟着换牌子和名片
    private func setLanguage(_ value: String) {
        defaults.set(value, forKey: "language")
        applyLanguage()
        bridge?.send([.locale(Lang.current)])
    }

    private func applyLanguage() {
        Lang.current = Lang(rawValue: defaults.string(forKey: "language") ?? "") ?? .system()
    }

    /// 用文本编辑器打开 rooms.json；保存后下一拍就重新排座
    private func editRooms() {
        let url = loop.roomsFile.url
        guard FileManager.default.fileExists(atPath: url.path) else {
            notify(L("房间名单还没生成，过一秒再试", "The room list isn't ready yet, try again in a second"))
            return
        }
        // .json 没有默认程序时用文本编辑打开
        let editor = NSWorkspace.shared.urlForApplication(toOpen: url)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        guard let editor else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 第一次只弹系统的辅助功能授权提示；系统之后不会再弹，所以再点就直接打开系统设置对应页面
    private func askForAccessibility() {
        let firstAsk = !defaults.bool(forKey: "askedAccessibility")
        defaults.set(true, forKey: "askedAccessibility")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options), !firstAsk,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
