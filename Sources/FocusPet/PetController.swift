import AppKit

/// 宠物动作（与素材前缀无关的通用枚举）
enum PetAction: String, CaseIterable {
    case idle, wave, sleep, focus, celebrate, sad, run, walk, eat
}

/// 一个物种：名字、图标、各动作的素材规格
struct PetSpecies {
    let name: String
    let icon: String
    let specs: [PetAction: AnimationSpec]

    static func named(_ key: String) -> PetSpecies {
        key == "dog" ? .dog : .cat
    }

    /// 叫声文件名前缀（cat_meow / dog_bark）
    var soundPrefix: String { name == "狗" ? "dog_bark" : "cat_meow" }

    static let cat = PetSpecies(name: "猫", icon: "🐱", specs: [
        .idle:      AnimationSpec(prefix: "idle", count: 8, frameDuration: 0.28, holdLastExtra: 0.5, repeatCount: nil),
        .wave:      AnimationSpec(prefix: "wave", count: 8, frameDuration: 0.18, holdLastExtra: 0.1, repeatCount: 2),
        .sleep:     AnimationSpec(prefix: "sleep", count: 8, frameDuration: 0.45, holdLastExtra: 0.3, repeatCount: 5),
        .focus:     AnimationSpec(prefix: "focus", count: 8, frameDuration: 0.35, holdLastExtra: 0.2, repeatCount: nil),
        .celebrate: AnimationSpec(prefix: "celebrate", count: 8, frameDuration: 0.16, holdLastExtra: 0.1, repeatCount: 3),
        .sad:       AnimationSpec(prefix: "sad", count: 8, frameDuration: 0.4, holdLastExtra: 0.3, repeatCount: 2),
        .run:       AnimationSpec(prefix: "run", count: 8, frameDuration: 0.14, holdLastExtra: 0.0, repeatCount: nil),
        .walk:      AnimationSpec(prefix: "walk", count: 8, frameDuration: 0.6, holdLastExtra: 0.1, repeatCount: nil),
        .eat:       AnimationSpec(prefix: "eat", count: 8, frameDuration: 0.3, holdLastExtra: 0.1, repeatCount: 2)
    ])

    static let dog = PetSpecies(name: "狗", icon: "🐶", specs: [
        .idle:      AnimationSpec(prefix: "dog_idle", count: 8, frameDuration: 0.28, holdLastExtra: 0.5, repeatCount: nil),
        .wave:      AnimationSpec(prefix: "dog_wave", count: 8, frameDuration: 0.18, holdLastExtra: 0.1, repeatCount: 2),
        .sleep:     AnimationSpec(prefix: "dog_sleep", count: 8, frameDuration: 0.45, holdLastExtra: 0.3, repeatCount: 5),
        .focus:     AnimationSpec(prefix: "dog_focus", count: 8, frameDuration: 0.35, holdLastExtra: 0.2, repeatCount: nil),
        .celebrate: AnimationSpec(prefix: "dog_celebrate", count: 8, frameDuration: 0.16, holdLastExtra: 0.1, repeatCount: 3),
        .sad:       AnimationSpec(prefix: "dog_sad", count: 8, frameDuration: 0.4, holdLastExtra: 0.3, repeatCount: 2),
        .run:       AnimationSpec(prefix: "dog_run", count: 8, frameDuration: 0.14, holdLastExtra: 0.0, repeatCount: nil),
        .walk:      AnimationSpec(prefix: "dog_walk", count: 8, frameDuration: 0.26, holdLastExtra: 0.0, repeatCount: nil),
        .eat:       AnimationSpec(prefix: "dog_eat", count: 8, frameDuration: 0.28, holdLastExtra: 0.1, repeatCount: 2)
    ])
}

/// 一只宠物：独立的悬浮面板 + 动画 + 随机小动作 + 乱窜调度。
/// 会话状态由 AppDelegate 全局广播，自由行为各自独立。
final class PetController {
    let species: PetSpecies
    let panel: NSPanel
    let petView: PetView

    /// 由 AppDelegate 注入：会话（专注/休息）进行中
    var isSessionActive: () -> Bool = { false }
    /// 右键菜单请求（由 AppDelegate 统一构建）
    var onShowMenu: ((NSEvent) -> Void)?

    private var idleWorkItem: DispatchWorkItem?
    private var roamTimer: Timer?
    private var roamAnim: Timer?
    private var roamFrom: NSPoint?
    private var roamTo: NSPoint?
    private var roamT0: CFTimeInterval = 0
    private var roamDur: CFTimeInterval = 0
    private var roamArc: CGFloat = 0

    init(species: PetSpecies, frame: NSRect) {
        self.species = species

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true

        petView = PetView(frame: NSRect(origin: .zero, size: frame.size))
        petView.play(species.specs[.idle]!)
        petView.onShowMenu = { [weak self] event in
            self?.onShowMenu?(event)
        }
        petView.onDragPickup = { [weak self] in
            self?.onDragPickup()
        }
        petView.onDragPutDown = { [weak self] dragged in
            self?.onDragPutDown(dragged: dragged)
        }
        petView.onDoubleTap = { [weak self] in
            self?.onDoubleTapped()
        }
        petView.onTap = { [weak self] in
            self?.feed()
        }
        panel.contentView = petView
        panel.orderFrontRegardless()
    }

    // MARK: - 投喂与饥饿

    /// 投喂成功回调（由 AppDelegate 重置饱腹计时）
    var onFed: (() -> Void)?
    /// 饥饿且正在专注时，请 AppDelegate 发系统通知（自带节流）
    var onHungryDuringSession: (() -> Void)?

    /// 播放本物种的叫声；kind = happy（开心）/ beg（讨食）
    private func makeSound(_ kind: String) {
        SoundManager.shared.play("\(species.soundPrefix)_\(kind)")
    }

    /// 休息时睡觉的呼噜：睡着一会儿后开始，每 6~10 秒一次
    private var snoreTimer: Timer?

    private func startSnore() {
        stopSnore()
        scheduleSnore(delay: 3.0)
    }

    private func scheduleSnore(delay: TimeInterval) {
        snoreTimer?.invalidate()
        snoreTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self,
                  self.isSessionActive(), self.inRestSession,
                  self.isPlaying(.sleep), !self.petView.isBeingDragged
            else { return }
            SoundManager.shared.play("snore")
            self.scheduleSnore(delay: TimeInterval.random(in: 6...10))
        }
    }

    private func stopSnore() {
        snoreTimer?.invalidate()
        snoreTimer = nil
    }

    /// 饥饿状态由 AppDelegate 按上次投喂时间更新
    var isHungry = false {
        didSet {
            guard isHungry != oldValue else { return }
            if isHungry {
                scheduleBeg()
            } else {
                hungerWorkItem?.cancel()
                petView.updateHunger(nil)
            }
        }
    }

    private var hungerWorkItem: DispatchWorkItem?
    private var hungerBubbleWorkItem: DispatchWorkItem?

    /// 投喂：打断当前动作，播放吃动画，吃完回状态
    func feed() {
        guard !isPlaying(.eat) else { return }
        hungerWorkItem?.cancel()
        hungerBubbleWorkItem?.cancel()
        petView.updateHunger(nil)
        // 打断移动
        if roamAnim != nil {
            roamAnim?.invalidate()
            roamAnim = nil
            roamFrom = nil
            roamTo = nil
            onArriveMove = nil
        }
        petView.bounce()
        petView.showHearts(count: 3)
        makeSound("happy")
        SoundManager.shared.play("eat_nom")
        play(.eat) { [weak self] in
            guard let self else { return }
            self.onFed?()
            if self.isSessionActive() {
                self.play(self.inRestSession ? .sleep : .focus)
            } else if self.isPlaying(.eat) {
                self.play(.idle)
            }
        }
        print("[FocusPet] 投喂了\(species.name) 🍖")
        fflush(stdout)
    }

    /// 排下一次讨食
    private func scheduleBeg(delay: TimeInterval? = nil) {
        hungerWorkItem?.cancel()
        let wait = delay ?? Double.random(in: 60...180)
        let item = DispatchWorkItem { [weak self] in
            self?.begForFood()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: item)
        hungerWorkItem = item
    }

    /// 讨食：空闲时委屈+气泡+到处找食；专注时只发通知
    private func begForFood() {
        guard isHungry, !isPlaying(.eat) else { return }
        scheduleBeg()
        if isSessionActive() {
            onHungryDuringSession?()
            return
        }
        guard roamAnim == nil else { return }
        play(.sad) { [weak self] in
            guard let self, !self.isSessionActive(), self.isPlaying(.sad) else { return }
            self.play(.idle)
        }
        petView.updateHunger("我饿了，点击喂我 🍖")
        makeSound("beg")
        hungerBubbleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.petView.updateHunger(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: item)
        hungerBubbleWorkItem = item
        // 饿得四处找吃的
        performRoam()
        print("[FocusPet] \(species.name)饿了，在讨食 🥺")
        fflush(stdout)
    }

    /// 双击互动：开心庆祝一下（空闲时才理你）
    private func onDoubleTapped() {
        guard !isSessionActive() else { return }
        // 乱窜/散步途中被打断，先停掉移动
        if roamAnim != nil {
            roamAnim?.invalidate()
            roamAnim = nil
            roamFrom = nil
            roamTo = nil
        }
        petView.bounce()
        petView.showHearts()
        makeSound("happy")
        play(.celebrate) { [weak self] in
            guard let self, !self.isSessionActive(), self.isPlaying(.celebrate) else { return }
            self.play(.idle)
        }
        print("[FocusPet] \(species.name)被你逗开心了 🎉")
        fflush(stdout)
    }

    // MARK: - 专注完成庆典

    /// 移动到后的回调（庆典用：到达屏幕中央后接大庆祝）
    private var onArriveMove: (() -> Void)?

    /// 专注完成大庆祝：先跑到屏幕中央，再弹跳 + 庆祝
    func celebrateAtScreenCenter(completion: (() -> Void)? = nil) {
        idleWorkItem?.cancel()
        roamTimer?.invalidate()
        roamAnim?.invalidate()
        roamAnim = nil
        onArriveMove = nil

        let arrive: () -> Void = { [weak self] in
            guard let self else { completion?(); return }
            self.petView.bounce()
            self.makeSound("happy")
            self.play(.celebrate, completion: completion)
        }

        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else {
            arrive()
            return
        }
        let size = panel.frame.size
        // 屏幕水平居中、偏下四分之一处（不挡视线又显眼）
        let target = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + visible.height * 0.28 - size.height / 2
        )
        let from = panel.frame.origin
        let dist = hypot(target.x - from.x, target.y - from.y)
        guard dist > 60 else {
            arrive()
            return
        }

        roamDur = TimeInterval(min(max(dist / 700, 0.5), 2.5))
        roamArc = min(110, dist * 0.18)
        roamFrom = from
        roamTo = target
        roamT0 = CACurrentMediaTime()
        onArriveMove = arrive

        // 素材脸朝左：向右走才翻转
        petView.mirrorHorizontally = target.x > from.x
        play(.run)
        startMoveTimer(action: .run)

        print("[FocusPet] \(species.name)跑去屏幕中央庆祝！距离 \(Int(dist))pt")
        fflush(stdout)
    }

    /// 移动动画定时器：驱动窗口从 roamFrom 移动到 roamTo（两种乱窜与庆典共用）
    private func startMoveTimer(action: PetAction) {
        let movingAction = action
        let anim = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard !self.petView.isBeingDragged,
                  let f = self.roamFrom,
                  let t = self.roamTo
            else { return }

            let raw = (CACurrentMediaTime() - self.roamT0) / self.roamDur
            if raw >= 1 {
                self.panel.setFrameOrigin(t)
                timer.invalidate()
                self.roamAnim = nil
                self.roamFrom = nil
                self.roamTo = nil
                if let cb = self.onArriveMove {
                    // 庆典移动：到达后接庆祝，不回待机
                    self.onArriveMove = nil
                    cb()
                } else if !self.isSessionActive() && self.isPlaying(movingAction) {
                    self.play(.idle)
                }
                self.scheduleRoam()
                return
            }
            let e = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
            self.panel.setFrameOrigin(NSPoint(
                x: f.x + (t.x - f.x) * e,
                y: f.y + (t.y - f.y) * e + self.roamArc * sin(.pi * raw)
            ))
        }
        RunLoop.main.add(anim, forMode: .common)
        roamAnim = anim
    }

    /// 当前是否在休息段（放下时恢复正确动画用）
    private(set) var inRestSession = false

    /// 被抓起：挣扎挥手（无限循环），会话期间不打扰。
    /// 注意这里不放音效——按下就会触发（含单击/双击的第一下），
    /// 叫声放在 onDragPutDown(dragged: true) 里，避免「一次点击叫两声」。
    private func onDragPickup() {
        guard !isSessionActive() else { return }
        guard let w = species.specs[.wave] else { return }
        petView.play(AnimationSpec(
            prefix: w.prefix, count: w.count,
            frameDuration: w.frameDuration,
            holdLastExtra: w.holdLastExtra,
            repeatCount: nil
        ))
    }

    /// 被放下：真的被拖拽过才「嗯」一声；会话中则回到专注/睡觉
    private func onDragPutDown(dragged: Bool) {
        if isSessionActive() {
            play(inRestSession ? .sleep : .focus)
        } else {
            if dragged { makeSound("happy") }
            petView.bounce()
            play(.idle)
        }
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - 基础封装

    func play(_ action: PetAction, completion: (() -> Void)? = nil) {
        guard let spec = species.specs[action] else { return }
        petView.play(spec, completion: completion)
    }

    func isPlaying(_ action: PetAction) -> Bool {
        petView.currentPrefix == species.specs[action]?.prefix
    }

    func updateBubble(_ text: String?, dimmed: Bool = false) {
        petView.updateTime(text, dimmed: dimmed)
    }

    func bounce() {
        petView.bounce()
    }

    /// 宠物整体缩放（0.5~1.5）：窗口保持中心点不变，内部布局自适应
    func setScale(_ scale: CGFloat) {
        let s = min(max(scale, 0.5), 1.5)
        petView.viewScale = s
        let newSize = NSSize(width: 200 * s, height: 240 * s)
        guard panel.frame.size != newSize else {
            petView.needsDisplay = true
            return
        }
        let center = NSPoint(
            x: panel.frame.midX,
            y: panel.frame.midY
        )
        panel.setFrame(
            NSRect(x: center.x - newSize.width / 2,
                   y: center.y - newSize.height / 2,
                   width: newSize.width,
                   height: newSize.height),
            display: true,
            animate: false
        )
        petView.frame = NSRect(origin: .zero, size: newSize)
        petView.needsDisplay = true
    }

    func setVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
            petView.resumeRendering()
        } else {
            panel.orderOut(nil)
            petView.pauseRendering()
        }
    }

    func teardown() {
        idleWorkItem?.cancel()
        roamTimer?.invalidate()
        roamAnim?.invalidate()
        stopSnore()
        panel.orderOut(nil)
    }

    // MARK: - 会话联动

    /// 会话开始：停下自由行为，专注=看书，休息=趴睡
    func onSessionStart(isRest: Bool) {
        inRestSession = isRest
        idleWorkItem?.cancel()
        roamTimer?.invalidate()
        play(isRest ? .sleep : .focus)
        if isRest {
            startSnore()   // 休息睡觉：一会儿后呼噜声起
        } else {
            stopSnore()
        }
    }

    /// 会话彻底结束：挥挥手回待机，恢复自由行为
    func onSessionEnd() {
        stopSnore()
        makeSound("happy")
        play(.wave) { [weak self] in
            guard let self, !self.isSessionActive(), self.isPlaying(.wave) else { return }
            self.play(.idle)
        }
        scheduleRandomBehavior()
        scheduleRoam()
    }

    /// 自由生活开始（应用启动 / 会话结束）
    func startIdleLife() {
        play(.idle)
        scheduleRandomBehavior()
        scheduleRoam()
    }

    // MARK: - 随机小动作

    private func scheduleRandomBehavior(first: Bool = false) {
        idleWorkItem?.cancel()
        let delay = first
            ? Double.random(in: 3...5)
            : Double.random(in: 5...12)
        let item = DispatchWorkItem { [weak self] in
            self?.performRandomBehavior()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        idleWorkItem = item
    }

    private func performRandomBehavior() {
        guard !isSessionActive() else { return }
        scheduleRandomBehavior()
        switch Int.random(in: 0..<10) {
        case 0...4:
            // 散步是最常见的自由行为，idle 不会显得发呆
            performStroll()
        case 5...6:
            play(.wave) { [weak self] in
                guard let self, !self.isSessionActive(), self.isPlaying(.wave) else { return }
                self.play(.idle)
            }
        case 7...8:
            play(.sleep) { [weak self] in
                guard let self, !self.isSessionActive(), self.isPlaying(.sleep) else { return }
                self.play(.idle)
            }
        default:
            break
        }
    }

    // MARK: - 随机乱窜 / 散步

    /// 移动风格：dash = 全屏乱跑（跑动画）；stroll = 短距离慢步（走动画）
    private enum MoveKind {
        case dash
        case stroll
    }

    private func scheduleRoam(first: Bool = false) {
        roamTimer?.invalidate()
        let delay = first
            ? Double.random(in: 3...6)
            : Double.random(in: 12...30)
        roamTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performRoam()
        }
    }

    private func performRoam() {
        startMove(.dash, retryWithSchedule: true)
    }

    /// 散步：idle 生活的常态。走得慢、时间长，猫慵懒踱步、狗欢快蹦跳
    private func performStroll() {
        startMove(.stroll)
    }

    private func startMove(_ kind: MoveKind, retryWithSchedule: Bool = false) {
        // 会话期间不移动；乱窜调度（onSessionEnd）会重新安排
        guard !isSessionActive() else { return }
        guard !petView.isBeingDragged,
              roamAnim == nil,
              let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
        else {
            if retryWithSchedule { scheduleRoam() }
            return
        }

        let size = panel.frame.size
        let margin: CGFloat = 24
        let minX = visible.minX + margin
        let minY = visible.minY + margin
        let maxX = max(minX + 1, visible.maxX - size.width - margin)
        let maxY = max(minY + 1, visible.maxY - size.height - margin)
        let from = panel.frame.origin

        let to: NSPoint
        let speed: CGFloat
        let maxDur: CFTimeInterval
        switch kind {
        case .dash:
            to = NSPoint(
                x: CGFloat.random(in: minX...maxX),
                y: CGFloat.random(in: minY...maxY)
            )
            speed = CGFloat.random(in: 550...900)
            maxDur = 3.2
        case .stroll:
            // 主要在水平方向踱步，目标就在附近
            let dx = CGFloat.random(in: 260...680) * (Bool.random() ? 1 : -1)
            let dy = CGFloat.random(in: -60...60)
            to = NSPoint(
                x: min(max(from.x + dx, minX), maxX),
                y: min(max(from.y + dy, minY), maxY)
            )
            // 狗蹦跳快走，猫懒洋洋慢走
            speed = species.name == "狗" ? CGFloat.random(in: 130...190) : CGFloat.random(in: 55...95)
            maxDur = 20
        }

        let dist = hypot(to.x - from.x, to.y - from.y)
        guard dist > (kind == .dash ? 80 : 120) else {
            if retryWithSchedule { scheduleRoam() }
            return
        }

        roamDur = TimeInterval(min(max(dist / speed, 0.7), maxDur))
        roamArc = kind == .dash
            ? min(110, dist * 0.18)
            : (species.name == "狗" ? min(60, dist * 0.16) : min(14, dist * 0.05))
        roamFrom = from
        roamTo = to
        roamT0 = CACurrentMediaTime()

        // 素材脸朝左：向右走才需要水平翻转（之前逻辑反了，导致倒着走）
        petView.mirrorHorizontally = to.x > from.x
        play(kind == .dash ? .run : .walk)

        let label = kind == .dash ? "开窜" : "散步"
        print("[FocusPet] \(species.name)\(label)！距离 \(Int(dist))pt，预计 \(String(format: "%.1f", roamDur))s")
        fflush(stdout)

        startMoveTimer(action: kind == .dash ? .run : .walk)
    }
}
