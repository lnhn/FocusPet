import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

/// 应用委托：单宠物管理 + 番茄钟引擎接线 + 通知/音效 + 统计 + 状态栏
/// + 设置 + 自启 + 全局快捷键。宠物可在猫咪/狗狗之间随时切换（只留一只）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 当前桌面宠物（同一时间只有一只）
    private var pet: PetController?
    private let statusBar = StatusBarController()
    private let settings = SettingsModel()
    private let hotkey = HotkeyManager()
    private var statsPanel: NSPanel?
    private var settingsPanel: NSPanel?

    /// 专注引擎：默认 25/5/15 分钟节奏（可被设置面板实时修改）；
    /// 命令行 `--demo-focus 秒数` 进入演示模式（专注用指定秒数，休息 6/8 秒，便于调试）
    private let engine: FocusEngine = {
        if let index = CommandLine.arguments.firstIndex(of: "--demo-focus"),
           index + 1 < CommandLine.arguments.count,
           let seconds = TimeInterval(CommandLine.arguments[index + 1]) {
            return FocusEngine(
                focusDuration: seconds,
                shortRestDuration: 6,
                longRestDuration: 8
            )
        }
        return FocusEngine(focusDuration: 25 * 60)
    }()

    /// 当前会话记录用的元数据
    private var sessionStartTime: Date?
    private var sessionPlanned: TimeInterval = 0
    private var sessionKindRaw: String?

    /// 会话进行中标志（注入给 PetController）
    private var isSessionActiveFlag = false

    // MARK: - 饱腹状态

    private static let lastFedKey = "lastFedAt"
    private static let hungerThreshold: TimeInterval = 2 * 3600
    private var lastHungerNotifyAt: Date?
    private var hungerCheckTimer: Timer?

    private var lastFedAt: Date {
        get {
            let ts = UserDefaults.standard.object(forKey: Self.lastFedKey) as? TimeInterval
            return ts.map(Date.init(timeIntervalSince1970:)) ?? Date()
        }
        set {
            UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: Self.lastFedKey)
        }
    }

    /// 每 30 秒检查一次宠物是否饿了
    private func startHungerCheck() {
        hungerCheckTimer?.invalidate()
        hungerCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateHungerState()
        }
        updateHungerState()
    }

    private func updateHungerState() {
        pet?.isHungry = Date().timeIntervalSince(lastFedAt) > Self.hungerThreshold
    }

    /// 投喂成功：重置饱腹计时
    private func didFeed() {
        lastFedAt = Date()
        pet?.isHungry = false
    }

    /// 专注中饿了：发系统通知提醒（30 分钟最多一条，避免轰炸）
    private func notifyHungryThrottled() {
        if let last = lastHungerNotifyAt, Date().timeIntervalSince(last) < 1800 { return }
        lastHungerNotifyAt = Date()
        notify(
            title: "\(settings.currentPetName)饿了 🍖",
            body: "它正在努力不打扰你，结束后记得点击它喂点吃的～"
        )
    }

    /// 系统通知只有在正式 .app bundle 中才可用（swift run / Xcode 直接跑的裸可执行文件
    /// 调用 UNUserNotificationCenter 会直接崩溃）
    private var notificationsAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 单实例保护：同一 bundle 已有实例在跑就直接退出，避免多只宠物叠加
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty {
            print("[FocusPet] 已有实例在运行，退出本次启动")
            fflush(stdout)
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyPetSelection()
        statusBar.updateTitle(pet?.species.icon ?? "🐱")
        startHungerCheck()

        // 状态栏菜单与宠物右键菜单共用一份构建逻辑
        statusBar.onRebuildMenu = { [weak self] in
            self?.buildMenu() ?? NSMenu()
        }

        // 通知授权（仅正式 .app 环境）
        if notificationsAvailable {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                print("[FocusPet] 通知授权: \(granted ? "已允许" : "被拒绝")")
                fflush(stdout)
            }
        } else {
            print("[FocusPet] 非 .app 环境（swift run / Xcode），系统通知已停用")
            fflush(stdout)
        }

        // 引擎回调接线
        engine.onTick = { [weak self] _ in
            self?.updateBubble()
        }
        engine.onSessionStart = { [weak self] session in
            self?.handleSessionStart(session)
        }
        engine.onSessionComplete = { [weak self] session in
            self?.handleSessionComplete(session)
        }

        // 设置：变化即时生效
        settings.onChange = { [weak self] in
            self?.applySettings()
            self?.applyPetSelection()
        }
        applySettings()

        // 全局快捷键：⇧⌘P 开始 / 暂停 / 继续
        hotkey.onTrigger = { [weak self] in
            guard let self else { return }
            switch (self.engine.phase, self.engine.session?.kind) {
            case (.idle, _):
                self.startFocus()
            case (.running, .focus?):
                self.pauseSession()
            case (.paused, .focus?):
                self.resumeSession()
            default:
                break
            }
        }

        // 演示模式：1 秒后自动开始专注
        if CommandLine.arguments.contains("--demo-focus") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.startFocus()
            }
        }
    }

    // MARK: - 宠物切换（同一时间只留一只）

    private func defaultPetFrame() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        return NSRect(
            x: screenFrame.minX + 120,
            y: screenFrame.minY + 120,
            width: 200,
            height: 240
        )
    }

    /// 按设置换上对应宠物；切换时保留原位置，若正在会话则让新宠物立刻进入状态
    private func applyPetSelection() {
        let desired = PetSpecies.named(settings.selectedPet)
        guard pet?.species.name != desired.name else { return }

        let oldFrame = pet?.panel.frame ?? defaultPetFrame()
        pet?.teardown()

        let newPet = PetController(species: desired, frame: oldFrame)
        newPet.isSessionActive = { [weak self] in
            self?.isSessionActiveFlag ?? false
        }
        newPet.onShowMenu = { [weak self] event in
            guard let self, let pet = self.pet else { return }
            NSMenu.popUpContextMenu(self.buildMenu(), with: event, for: pet.petView)
        }
        newPet.onFed = { [weak self] in
            self?.didFeed()
        }
        newPet.onHungryDuringSession = { [weak self] in
            self?.notifyHungryThrottled()
        }
        pet = newPet
        newPet.setScale(settings.petSizePercent / 100)
        updateHungerState()

        if isSessionActiveFlag {
            newPet.onSessionStart(isRest: engine.session?.kind.isRest ?? false)
            updateBubble()
        } else {
            newPet.startIdleLife()
        }
        statusBar.updateTitle(newPet.species.icon)
        print("[FocusPet] 已切换为\(desired.name == "狗" ? "狗狗 🐶" : "猫咪 🐱")")
        fflush(stdout)
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        settings.selectedPet = sender.tag == 1 ? "dog" : "cat"
    }

    // MARK: - 设置应用

    private func applySettings() {
        // 演示模式下保留命令行指定的时长，不被设置覆盖
        if !CommandLine.arguments.contains("--demo-focus") {
            engine.focusDuration = settings.focusMinutes * 60
            engine.shortRestDuration = settings.shortRestMinutes * 60
            engine.longRestDuration = settings.longRestMinutes * 60
            engine.focusesPerCycle = Int(settings.cycleCount)
        }

        // 开机自启
        if settings.launchAtLogin {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("[FocusPet] 自启注册失败: \(error.localizedDescription)")
                fflush(stdout)
            }
        } else {
            try? SMAppService.mainApp.unregister()
        }

        // 全局快捷键
        if settings.hotkeyEnabled {
            hotkey.register()
        } else {
            hotkey.unregister()
        }

        // 宠物音效开关
        SoundManager.shared.enabled = settings.soundEnabled

        // 宠物大小（即时生效）
        pet?.setScale(settings.petSizePercent / 100)
    }

    // MARK: - 番茄钟

    private var petIcon: String { pet?.species.icon ?? "🐱" }

    private func updateBubble() {
        guard let pet else { return }
        let total = Int(engine.remaining)
        let text = String(format: "%02d:%02d", total / 60, total % 60)
        pet.updateBubble(text, dimmed: engine.phase == .paused)

        // 状态栏同步显示倒计时
        if engine.phase == .idle || engine.session == nil {
            statusBar.updateTitle(petIcon)
        } else {
            let icon = engine.session?.kind.isRest == true ? "😴" : petIcon
            statusBar.updateTitle("\(icon) \(text)")
        }
    }

    private func handleSessionStart(_ session: FocusEngine.Session) {
        print("[FocusPet] 会话开始: \(session.kind.rawValue)（\(Int(session.duration))s）")
        fflush(stdout)
        isSessionActiveFlag = true
        sessionStartTime = Date()
        sessionPlanned = session.duration
        sessionKindRaw = session.kind.rawValue
        pet?.onSessionStart(isRest: session.kind.isRest)
        updateBubble()
    }

    private func handleSessionComplete(_ session: FocusEngine.Session) {
        print("[FocusPet] 会话完成: \(session.kind.rawValue)，已累计完成 \(engine.completedFocuses) 次专注")
        fflush(stdout)
        recordSession(completed: true)

        switch session.kind {
        case .focus:
            notify(
                title: "专注完成 🎉",
                body: "又拿下一段专注时光，休息一下吧～"
            )
            NSSound(named: "Glass")?.play()
            pet?.updateBubble(nil)
            // 大庆祝：先跑到屏幕中央，播完自动进入休息
            pet?.celebrateAtScreenCenter { [weak self] in
                guard let self else { return }
                guard self.engine.phase == .idle, self.engine.session == nil else { return }
                self.engine.startRest()
            }
            updateBubble()   // 状态栏回到宠物图标（庆祝间隙）
        case .shortRest, .longRest:
            notify(
                title: "休息结束",
                body: "该开始下一轮专注啦，\(settings.currentPetName)已经准备好了～"
            )
            NSSound(named: "Pop")?.play()
            endSessionUI()
        }
    }

    /// 记录当前会话到统计存储
    private func recordSession(completed: Bool) {
        guard let start = sessionStartTime, let kind = sessionKindRaw else { return }
        StatsStore.shared.add(SessionRecord(
            kind: kind,
            startedAt: start,
            endedAt: Date(),
            plannedSeconds: sessionPlanned,
            completed: completed
        ))
        sessionStartTime = nil
        sessionKindRaw = nil
    }

    /// 会话彻底结束（UI 侧）：收气泡、回待机、恢复随机行为
    private func endSessionUI() {
        isSessionActiveFlag = false
        statusBar.updateTitle(petIcon)
        pet?.updateBubble(nil)
        pet?.onSessionEnd()
    }

    @objc private func startFocus() {
        engine.startFocus()
    }

    @objc private func pauseSession() {
        engine.pause()
    }

    @objc private func resumeSession() {
        engine.resume()
    }

    @objc private func giveUpSession() {
        let wasFocus = engine.session?.kind == .focus
        recordSession(completed: false)
        engine.stop()
        if wasFocus {
            pet?.play(.sad) { [weak self] in
                self?.endSessionUI()
            }
        } else {
            endSessionUI()
        }
    }

    // MARK: - 统计 / 设置窗口

    @objc private func showStats() {
        print("[FocusPet] 打开统计窗口")
        fflush(stdout)
        let snapshot = StatsStore.shared.snapshot()
        let name = settings.currentPetName
        let host = NSHostingView(rootView: StatsView(
            stats: snapshot,
            petName: name,
            petBirthday: settings.currentPetBirthday,
            adoptionDate: settings.adoptionDate
        ))
        if statsPanel == nil {
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newPanel.isReleasedWhenClosed = false
            newPanel.center()
            statsPanel = newPanel
        }
        statsPanel?.title = "\(name) 的专注统计"
        NSApp.activate()
        statsPanel?.contentView = host
        statsPanel?.makeKeyAndOrderFront(nil)
    }

    @objc private func showSettings() {
        print("[FocusPet] 打开设置窗口")
        fflush(stdout)
        let host = NSHostingView(rootView: SettingsView(model: settings))
        if settingsPanel == nil {
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newPanel.title = "设置"
            newPanel.isReleasedWhenClosed = false
            newPanel.center()
            settingsPanel = newPanel
        }
        NSApp.activate()
        settingsPanel?.contentView = host
        settingsPanel?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 通知

    private func notify(title: String, body: String) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 菜单（宠物右键 & 状态栏共用）

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "FocusPet")

        switch (engine.phase, engine.session?.kind) {
        case (.idle, _):
            let startItem = NSMenuItem(
                title: "开始专注 \(Int(settings.focusMinutes)) 分钟",
                action: #selector(startFocus),
                keyEquivalent: ""
            )
            startItem.target = self
            menu.addItem(startItem)

        case (.running, .focus?), (.paused, .focus?):
            let pauseItem = NSMenuItem(
                title: engine.phase == .running ? "暂停专注" : "继续专注",
                action: engine.phase == .running
                    ? #selector(pauseSession)
                    : #selector(resumeSession),
                keyEquivalent: ""
            )
            pauseItem.target = self
            menu.addItem(pauseItem)
            addGiveUpItem(to: menu, label: "提前结束（它会难过）")

        case (.running, .shortRest?), (.paused, .shortRest?),
             (.running, .longRest?), (.paused, .longRest?):
            let pauseItem = NSMenuItem(
                title: engine.phase == .running ? "暂停休息" : "继续休息",
                action: engine.phase == .running
                    ? #selector(pauseSession)
                    : #selector(resumeSession),
                keyEquivalent: ""
            )
            pauseItem.target = self
            menu.addItem(pauseItem)
            addGiveUpItem(to: menu, label: "跳过休息")

        default:
            break
        }

        menu.addItem(.separator())

        // 宠物切换（单选，桌面只留一只）
        let catItem = NSMenuItem(
            title: "猫咪 🐱 · \(settings.catName)",
            action: #selector(selectPet(_:)),
            keyEquivalent: ""
        )
        catItem.tag = 0
        catItem.state = settings.selectedPet == "cat" ? .on : .off
        catItem.target = self
        menu.addItem(catItem)

        let dogItem = NSMenuItem(
            title: "狗狗 🐶 · \(settings.dogName)",
            action: #selector(selectPet(_:)),
            keyEquivalent: ""
        )
        dogItem.tag = 1
        dogItem.state = settings.selectedPet == "dog" ? .on : .off
        dogItem.target = self
        menu.addItem(dogItem)

        menu.addItem(.separator())

        let statsItem = NSMenuItem(
            title: "📊 专注统计…",
            action: #selector(showStats),
            keyEquivalent: ""
        )
        statsItem.target = self
        menu.addItem(statsItem)

        let settingsItem = NSMenuItem(
            title: "⚙️ 设置…",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let hideItem = NSMenuItem(
            title: pet?.isVisible == true ? "隐藏宠物" : "显示宠物",
            action: #selector(toggleHidden),
            keyEquivalent: ""
        )
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let feedItem = NSMenuItem(
            title: "🍖 投喂",
            action: #selector(feedPet),
            keyEquivalent: ""
        )
        feedItem.target = self
        menu.addItem(feedItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "关于 FocusPet",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "退出 FocusPet",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }

    /// 原生关于面板：图标取应用图标，版本号读自 Info.plist，附自定义致谢
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(
            string: "陪伴你专注的桌面小猫小狗 🐱🐶\n\n动画素材由 AI 生成 · 用 Swift + AppKit 手工打造",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "FocusPet 专注宠物",
            .credits: credits
        ])
    }

    private func addGiveUpItem(to menu: NSMenu, label: String) {
        let item = NSMenuItem(
            title: label,
            action: #selector(giveUpSession),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleHidden() {
        guard let pet else { return }
        pet.setVisible(!pet.isVisible)
    }

    @objc private func feedPet() {
        pet?.feed()
    }
}
