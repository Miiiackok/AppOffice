import AppKit
import OfficeCore

/// 菜单栏图标和菜单；菜单每次打开时现建，开关状态总是最新的
final class MenuBarController: NSObject, NSMenuDelegate {
    struct Toggle {
        /// 每次打开菜单时取，切换语言后跟着变
        let title: () -> String
        let get: () -> Bool
        let set: (Bool) -> Void
    }

    static var stateTitles: [(EmployeeState, String)] {
        [
            (.hung, L("🚽 上厕所（卡住）", "🚽 Restroom (frozen)")), (.offline, L("🏋️ 健身（断网）", "🏋️ Gym (offline)")),
            (.launching, L("🎒 刚到公司", "🎒 Arriving")), (.focused, L("⌨️ 疯狂干活", "⌨️ Typing like mad")),
            (.snacking, L("🍪 吃零食", "🍪 Snacking")), (.working, L("💻 干活", "💻 Working")),
            (.idle, L("☕ 半摸鱼", "☕ Idle")), (.resting, L("🎮 休闲区（很久没用）", "🎮 Lounge (long unused)")),
            (.off, L("😴 摸鱼（没打开）", "😴 Slacking (not running)")),
        ]
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggles: [Toggle]
    private let hangDetectionAvailable: () -> Bool
    private let enableHangDetection: () -> Void
    private let employees: () -> [(id: String, name: String)]
    private let simulated: () -> [String: EmployeeState]
    private let simulate: (String, EmployeeState?) -> Void
    private let editRooms: () -> Void
    /// "auto"（跟随系统）、"zh"、"en"
    private let language: () -> String
    private let setLanguage: (String) -> Void

    init(toggles: [Toggle],
         hangDetectionAvailable: @escaping () -> Bool,
         enableHangDetection: @escaping () -> Void,
         employees: @escaping () -> [(id: String, name: String)],
         simulated: @escaping () -> [String: EmployeeState],
         simulate: @escaping (String, EmployeeState?) -> Void,
         editRooms: @escaping () -> Void,
         language: @escaping () -> String,
         setLanguage: @escaping (String) -> Void) {
        self.toggles = toggles
        self.hangDetectionAvailable = hangDetectionAvailable
        self.enableHangDetection = enableHangDetection
        self.employees = employees
        self.simulated = simulated
        self.simulate = simulate
        self.editRooms = editRooms
        self.language = language
        self.setLanguage = setLanguage
        super.init()
        let image = NSImage(systemSymbolName: "building.2", accessibilityDescription: "AppOffice")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (index, toggle) in toggles.enumerated() {
            let entry = NSMenuItem(title: toggle.title(), action: #selector(flip(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.state = toggle.get() ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let rooms = NSMenuItem(title: L("编辑房间名单…", "Edit Room List…"), action: #selector(openRooms), keyEquivalent: "")
        rooms.target = self
        menu.addItem(rooms)
        let lang = NSMenuItem(title: "语言 / Language", action: nil, keyEquivalent: "")
        lang.submenu = languageMenu()
        menu.addItem(lang)
        if !hangDetectionAvailable() {
            let entry = NSMenuItem(title: L("开启卡顿检测…", "Enable Hang Detection…"), action: #selector(askForAccessibility), keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        let debug = NSMenuItem(title: L("调试", "Debug"), action: nil, keyEquivalent: "")
        let debugMenu = NSMenu()
        let simulateItem = NSMenuItem(title: L("模拟状态", "Simulate State"), action: nil, keyEquivalent: "")
        simulateItem.submenu = simulationMenu()
        debugMenu.addItem(simulateItem)
        debug.submenu = debugMenu
        menu.addItem(debug)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("退出 AppOffice", "Quit AppOffice"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func simulationMenu() -> NSMenu {
        let menu = NSMenu()
        // 关掉自动启用，clearAll.isEnabled 才生效；其他项都显式启用
        menu.autoenablesItems = false
        let current = simulated()
        for employee in employees() {
            let forced = current[employee.id]
            let person = NSMenuItem(title: forced == nil ? employee.name : L("\(employee.name)（模拟中）", "\(employee.name) (simulated)"), action: nil, keyEquivalent: "")
            person.isEnabled = true
            let states = NSMenu()
            states.autoenablesItems = false
            for (state, title) in Self.stateTitles {
                let entry = NSMenuItem(title: title, action: #selector(pickState(_:)), keyEquivalent: "")
                entry.target = self
                entry.isEnabled = true
                entry.representedObject = [employee.id, state.rawValue]
                entry.state = forced == state ? .on : .off
                states.addItem(entry)
            }
            states.addItem(.separator())
            let clear = NSMenuItem(title: L("取消模拟", "Stop Simulating"), action: #selector(pickState(_:)), keyEquivalent: "")
            clear.target = self
            clear.isEnabled = true
            clear.representedObject = [employee.id, ""]
            states.addItem(clear)
            person.submenu = states
            menu.addItem(person)
        }
        menu.addItem(.separator())
        let clearAll = NSMenuItem(title: L("取消全部模拟", "Stop All Simulations"), action: #selector(clearAllSimulations), keyEquivalent: "")
        clearAll.target = self
        clearAll.isEnabled = !current.isEmpty
        menu.addItem(clearAll)
        return menu
    }

    private func languageMenu() -> NSMenu {
        let menu = NSMenu()
        let current = language()
        for (value, title) in [("auto", L("跟随系统", "Follow System")), ("zh", "中文"), ("en", "English")] {
            let entry = NSMenuItem(title: title, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = value
            entry.state = current == value ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        setLanguage(value)
    }

    @objc private func flip(_ sender: NSMenuItem) {
        let toggle = toggles[sender.tag]
        toggle.set(!toggle.get())
    }

    @objc private func openRooms() {
        editRooms()
    }

    @objc private func askForAccessibility() {
        enableHangDetection()
    }

    @objc private func pickState(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        simulate(pair[0], EmployeeState(rawValue: pair[1]))
    }

    @objc private func clearAllSimulations() {
        for id in simulated().keys { simulate(id, nil) }
    }
}
