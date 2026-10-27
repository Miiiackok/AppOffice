import AppKit
import OfficeCore

/// 菜单栏图标和菜单；菜单每次打开时现建，开关状态总是最新的
final class MenuBarController: NSObject, NSMenuDelegate {
    struct Toggle {
        let title: String
        let get: () -> Bool
        let set: (Bool) -> Void
    }

    static let stateTitles: [(EmployeeState, String)] = [
        (.hung, "🚽 上厕所（卡住）"), (.offline, "🏋️ 健身（断网）"), (.launching, "🎒 刚到公司"),
        (.focused, "⌨️ 疯狂干活"), (.snacking, "🍪 吃零食"), (.working, "💻 干活"),
        (.idle, "☕ 半摸鱼"), (.resting, "🎮 休闲区（很久没用）"), (.off, "😴 摸鱼（没打开）"),
    ]

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggles: [Toggle]
    private let hangDetectionAvailable: () -> Bool
    private let enableHangDetection: () -> Void
    private let employees: () -> [(id: String, name: String)]
    private let simulated: () -> [String: EmployeeState]
    private let simulate: (String, EmployeeState?) -> Void

    init(toggles: [Toggle],
         hangDetectionAvailable: @escaping () -> Bool,
         enableHangDetection: @escaping () -> Void,
         employees: @escaping () -> [(id: String, name: String)],
         simulated: @escaping () -> [String: EmployeeState],
         simulate: @escaping (String, EmployeeState?) -> Void) {
        self.toggles = toggles
        self.hangDetectionAvailable = hangDetectionAvailable
        self.enableHangDetection = enableHangDetection
        self.employees = employees
        self.simulated = simulated
        self.simulate = simulate
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
            let entry = NSMenuItem(title: toggle.title, action: #selector(flip(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.state = toggle.get() ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        if !hangDetectionAvailable() {
            let entry = NSMenuItem(title: "开启卡顿检测…", action: #selector(askForAccessibility), keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        let debug = NSMenuItem(title: "调试", action: nil, keyEquivalent: "")
        let debugMenu = NSMenu()
        let simulateItem = NSMenuItem(title: "模拟状态", action: nil, keyEquivalent: "")
        simulateItem.submenu = simulationMenu()
        debugMenu.addItem(simulateItem)
        debug.submenu = debugMenu
        menu.addItem(debug)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 AppOffice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func simulationMenu() -> NSMenu {
        let menu = NSMenu()
        // 关掉自动启用，clearAll.isEnabled 才生效；其他项都显式启用
        menu.autoenablesItems = false
        let current = simulated()
        for employee in employees() {
            let forced = current[employee.id]
            let person = NSMenuItem(title: forced == nil ? employee.name : "\(employee.name)（模拟中）", action: nil, keyEquivalent: "")
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
            let clear = NSMenuItem(title: "取消模拟", action: #selector(pickState(_:)), keyEquivalent: "")
            clear.target = self
            clear.isEnabled = true
            clear.representedObject = [employee.id, ""]
            states.addItem(clear)
            person.submenu = states
            menu.addItem(person)
        }
        menu.addItem(.separator())
        let clearAll = NSMenuItem(title: "取消全部模拟", action: #selector(clearAllSimulations), keyEquivalent: "")
        clearAll.target = self
        clearAll.isEnabled = !current.isEmpty
        menu.addItem(clearAll)
        return menu
    }

    @objc private func flip(_ sender: NSMenuItem) {
        let toggle = toggles[sender.tag]
        toggle.set(!toggle.get())
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
