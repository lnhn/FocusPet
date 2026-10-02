import AppKit

/// 菜单栏状态图标：🐱/🐶 emoji + 倒计时。
/// 用显式点击事件驱动菜单弹出（ accessory 应用不自动激活，
/// 依赖系统默认的 statusItem.menu 展示行为容易无响应）。
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    /// 点击时由 AppDelegate 重新构建菜单
    var onRebuildMenu: (() -> NSMenu)?

    override init() {
        super.init()
        statusItem.button?.title = "🐱"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    func updateTitle(_ text: String) {
        statusItem.button?.title = text
    }

    @objc private func handleClick() {
        guard let button = statusItem.button,
              let menu = onRebuildMenu?() else { return }
        // 关键：先激活应用（accessory 模式默认不激活），
        // 否则菜单弹出后可能收不到点击、设置/统计窗口也可能不显示
        NSApp.activate()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height),
            in: button
        )
    }
}
