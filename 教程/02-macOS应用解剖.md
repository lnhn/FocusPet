# 02 · macOS 应用解剖：从启动到窗口

> FocusPet 零基础开发教程 · 第 2 篇

## 1. 一个 macOS 应用是怎么启动的

你双击 `FocusPet.app`，系统实际做了这些事：

```
双击 .app
  → 找到 Contents/Info.plist（应用的"身份证"：名字、版本、图标、主类）
  → 启动 Contents/MacOS/FocusPet（真正的可执行文件）
  → 创建 NSApplication 单例（应用的"总开关"）
  → 调用 AppDelegate 的 applicationDidFinishLaunching
  → 我们的代码从这里开始接管
```

对应到代码（`AppDelegate.swift`）：

```swift
@main                          // 程序入口标记（整个项目只有这一个）
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyPetSelection()    // 创建宠物
        startHungerCheck()     // 启动饥饿计时
        // ... 组装菜单、热键、通知授权
    }
}
```

**AppDelegate 是应用的"总导演"**：它不画画、不播动画，只负责在正确的时刻调正确的人。

## 2. 为什么用 SwiftPM 而不是 Xcode 工程

项目根目录的 `Package.swift` 定义了构建方式：

```swift
let package = Package(
    name: "FocusPet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FocusPet",
            path: "Sources/FocusPet",
            exclude: ["Info.plist"],
            resources: [.copy("PetAssets")]   // 把素材文件夹打进程序包
        )
    ]
)
```

好处：`swift build` 一条命令编译，不需要 .xcodeproj 那些复杂配置；素材通过 `.copy("PetAssets")` 声明，编译后自动成为 Bundle 资源，代码里用 `Bundle.module.url(forResource:...)` 就能找到。

## 3. AppKit vs SwiftUI：本项目为什么混着用

| | AppKit（1980s 至今） | SwiftUI（2019+） |
|---|---|---|
| 本质 | 命令式：你告诉系统每一步怎么做 | 声明式：你描述"要什么样"，系统自己算怎么变 |
| 透明悬浮窗 | ✅ 完全掌控（NSPanel + 自绘） | ❌ 做不了这种像素级控制 |
| 表单/滑杆/图表 | 啰嗦 | ✅ 几行搞定 |

所以本项目分工：

- **宠物本体**（PetView）= 纯 AppKit，每一帧都自己 `draw(_:)`
- **设置/统计窗口**（SettingsView/StatsView）= SwiftUI，用 `NSHostingView` 包一层塞进 AppKit 窗口

```swift
let host = NSHostingView(rootView: SettingsView(model: settings))
panel.contentView = host     // SwiftUI 视图住进 AppKit 窗口
```

## 4. Info.plist：应用的身份证

`Sources/FocusPet/Info.plist` 里几个关键键：

| 键 | 值 | 作用 |
|---|---|---|
| `CFBundleIdentifier` | local.focuspet.app | 唯一 ID（自启、通知都靠它） |
| `CFBundleShortVersionString` | 0.7 | 版本号（关于窗口显示） |
| `CFBundleIconFile` | AppIcon | Dock/访达图标 |
| `LSUIElement` | true | **关键！**应用不在 Dock 显示、没有主菜单栏（状态栏应用标配） |

`LSUIElement=true` 是"为什么这个 app 没有 Dock 图标"的答案——它是"辅助应用"（accessory app）。这个设定也带来了一个著名的坑（第 9 篇讲：菜单弹出不响应，因为 accessory 应用默认不激活）。

## 5. NSPanel vs NSWindow

macOS 有两种窗口：

- `NSWindow`：正经窗口（有标题栏、可最小化）
- `NSPanel`：特殊窗口——可以**无边框、透明、悬浮在所有 app 之上、不抢焦点**

宠物显然要后者。创建代码（`PetController.swift`）：

```swift
panel = NSPanel(
    contentRect: frame,
    styleMask: [.borderless, .nonactivatingPanel],  // 无边框 + 点它不抢前台
    backing: .buffered,
    defer: false
)
panel.backgroundColor = .clear      // 透明底色（配合 AllowsTransparency 式效果）
panel.isOpaque = false
panel.level = .floating             // 悬浮层：永远在普通窗口之上
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
// 可以出现在所有桌面/全屏 app 之上，且切 Space 时不动
```

## 6. 事件循环（RunLoop）：一切动画和交互的地基

macOS 应用启动后进入一个永不退出的循环：

```
while true {
    取出一个事件（鼠标点击 / 键盘 / 定时器到点 / 屏幕刷新）
    分发给对应对象处理
    没有事件就休眠省电
}
```

这就是为什么我们可以**同时**有：CVDisplayLink 动画、N 个 Timer、鼠标拖拽、菜单——它们都是事件循环里的不同事件源。

## 7. 内存管理：ARC 与循环引用

Swift 自动管理内存（ARC）：对象没有"人"引用它时自动销毁。

```swift
final class PetController {
    private var roamTimer: Timer?
    // Timer 会持有闭包，闭包持有 self（若写 [self]）
    // self 持有 timer → 互相持有 → 谁也别想销毁（内存泄漏）
}
```

解法就是第 1 篇的 `[weak self]`。项目里所有定时器闭包都用了它。

## 8. 单实例保护

`applicationWillFinishLaunching` 里有个实用技巧：

```swift
let others = NSRunningApplication
    .runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != getpid() }
if !others.isEmpty { exit(0) }   // 已在运行 → 自己退出
```

否则双击两次 app 会出现两只宠物叠在一起。

## 小结

```
双击 .app → Info.plist → NSApplication → AppDelegate
                ↓
        AppKit 搭骨架（窗口/状态栏/菜单）
        PetView(AppKit) 画动画   SwiftUI 画面板
        类与类用"回调闭包"通信
                ↓
        RunLoop 让一切同时转起来
```

下一篇：11 个类怎么分工——读源码前的地图。
