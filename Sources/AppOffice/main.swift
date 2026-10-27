import AppKit

setvbuf(stdout, nil, _IOLBF, 0) // 日志重定向到文件时也逐行输出

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 只在菜单栏，没有 Dock 图标
app.run()
