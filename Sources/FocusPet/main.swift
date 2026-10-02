import AppKit

// 入口：纯 AppKit 启动， accessory 策略 = 无 Dock 图标、无主窗口
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
