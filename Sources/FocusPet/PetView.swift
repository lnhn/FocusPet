import AppKit
import CoreVideo

/// 动画规格：一套序列帧的播放参数
struct AnimationSpec {
    let prefix: String
    let count: Int
    let frameDuration: CFTimeInterval
    let holdLastExtra: CFTimeInterval   // 每轮最后一帧额外停留（制造节奏感）
    let repeatCount: Int?               // nil = 无限循环；数字 = 播完后停在最后一帧

    static let idle      = AnimationSpec(prefix: "idle", count: 8, frameDuration: 0.28, holdLastExtra: 0.5, repeatCount: nil)
    static let wave      = AnimationSpec(prefix: "wave", count: 8, frameDuration: 0.18, holdLastExtra: 0.1, repeatCount: 2)
    static let sleep     = AnimationSpec(prefix: "sleep", count: 8, frameDuration: 0.45, holdLastExtra: 0.3, repeatCount: 5)
    static let focus     = AnimationSpec(prefix: "focus", count: 8, frameDuration: 0.35, holdLastExtra: 0.2, repeatCount: nil)
    static let celebrate = AnimationSpec(prefix: "celebrate", count: 8, frameDuration: 0.16, holdLastExtra: 0.1, repeatCount: 3)
    static let sad       = AnimationSpec(prefix: "sad", count: 8, frameDuration: 0.4, holdLastExtra: 0.3, repeatCount: 2)
    static let run       = AnimationSpec(prefix: "run", count: 8, frameDuration: 0.14, holdLastExtra: 0.0, repeatCount: nil)
}

/// 宠物视图：序列帧动画（CVDisplayLink）+ 倒计时气泡 + 拖拽 + 右键
///
/// 布局：底部是正方形宠物区（side × side），顶部留给倒计时气泡。
/// 注意：不用 layer-backed 视图（透明窗口里 layer 快速重绘会有 CA 事务残影）。
final class PetView: NSView {
    private var frameCache: [String: [NSImage]] = [:]
    private var frames: [NSImage] = []
    private var frameDurations: [CFTimeInterval] = []
    private var frameIndex = 0
    private var drawnFrameIndex = -1   // 上次实际绘制过的帧序号（省电：没变不重绘）
    private var frameStartTime: CFTimeInterval = CACurrentMediaTime()
    private var displayLink: CVDisplayLink?

    /// 有限循环播完后的回调
    private var completion: (() -> Void)?
    private var loopsDone = 0
    private var finished = false
    private var currentRepeatCount: Int?

    /// 当前动画标识（供外部判断是否可以安全切回待机）
    private(set) var currentPrefix = ""

    /// 水平镜像（向左边跑时转身）；注意不能用 flipped，NSView 已有同名属性
    var mirrorHorizontally = false

    /// 宠物整体缩放（0.5~1.5，气泡同步缩放）
    var viewScale: CGFloat = 1

    /// 用户正在拖拽中（此时暂停乱窜）
    private(set) var isBeingDragged = false

    /// 弹跳动画进度（手动实现，不依赖 CA 图层动画）
    private var bounceT0: CFTimeInterval?
    private let bounceKeys: [CGFloat] = [1.0, 1.15, 0.95, 1.1, 1.0]
    private let bounceDuration: CFTimeInterval = 0.5

    /// 倒计时气泡：nil 表示隐藏
    private var timeText: String?
    private var timeDimmed = false

    /// 饥饿气泡：nil 表示不饿（画在倒计时气泡上方）
    private var hungerText: String?

    /// 更新饥饿气泡；传 nil 清除
    func updateHunger(_ text: String?) {
        hungerText = text
        needsDisplay = true
    }

    /// 爱心粒子（双击互动时飘出）
    private struct Heart {
        var x: CGFloat
        var y: CGFloat
        var t0: CFTimeInterval
        var emoji: String
        var size: CGFloat
        var sway: CGFloat
    }
    private var hearts: [Heart] = []
    private let heartLife: CFTimeInterval = 1.8

    /// 飘出一串爱心
    func showHearts(count: Int = 6) {
        let emojis = ["❤️", "🧡", "💖", "💕", "💗"]
        let now = CACurrentMediaTime()
        let area = petArea
        for i in 0..<count {
            hearts.append(Heart(
                x: area.minX + CGFloat.random(in: area.width * 0.2...area.width * 0.8),
                y: area.minY + CGFloat.random(in: area.height * 0.35...area.height * 0.7),
                t0: now + Double(i) * 0.12,
                emoji: emojis.randomElement() ?? "❤️",
                size: CGFloat.random(in: 13...20) * viewScale,
                sway: CGFloat.random(in: 0...(.pi * 2))
            ))
        }
        startDisplayLink()
    }

    private func drawHearts(_ now: CFTimeInterval) {
        hearts.removeAll { now - $0.t0 > heartLife }
        guard !hearts.isEmpty else { return }
        for heart in hearts {
            let age = now - heart.t0
            guard age >= 0 else { continue }
            let p = age / heartLife
            let rise = p * 50 * viewScale
            let x = heart.x + sin(p * .pi * 2 + heart.sway) * 7 * viewScale
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: heart.size),
                .foregroundColor: NSColor.white.withAlphaComponent(max(0, 1 - p * p))
            ]
            heart.emoji.draw(at: NSPoint(x: x, y: heart.y + rise), withAttributes: attrs)
        }
    }

    /// 右键回调（由 AppDelegate 弹出菜单）
    var onShowMenu: ((NSEvent) -> Void)?

    /// 单击回调（投喂）；双击会取消未决的单击
    var onTap: (() -> Void)?

    /// 单击判定窗口：按下到抬起间隔太短会被双击判定点干扰，延迟确认
    private var tapWorkItem: DispatchWorkItem?

    /// 被抓起 / 被放下（由 PetController 接上对应表情）
    /// onDragPutDown 的 Bool 参数 = 这次是否真的拖动了（原地单击为 false）
    var onDragPickup: (() -> Void)?
    var onDragPutDown: ((Bool) -> Void)?

    /// 双击互动（由 PetController 接上庆祝动作）
    var onDoubleTap: (() -> Void)?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // 刻意不用 wantsLayer：layer-backed 视图在透明窗口里高频重绘会有残影
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        stopDisplayLink()
    }

    /// 无边框面板里的第一下点击也要能被接住
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 动画

    /// 切换到指定动画。有限循环的动画播完后停在最后一帧并触发 completion。
    func play(_ spec: AnimationSpec, completion: (() -> Void)? = nil) {
        currentPrefix = spec.prefix
        if frameCache[spec.prefix] == nil {
            frameCache[spec.prefix] = (1...spec.count).compactMap { index in
                guard let url = Bundle.module.url(
                    forResource: "\(spec.prefix)_\(index)",
                    withExtension: "png",
                    subdirectory: "PetAssets"
                ) else {
                    print("⚠️ 缺少素材: \(spec.prefix)_\(index).png")
                    return nil
                }
                return NSImage(contentsOf: url)
            }
        }
        frames = frameCache[spec.prefix] ?? []
        frameDurations = (0..<frames.count).map {
            $0 == frames.count - 1
                ? spec.frameDuration + spec.holdLastExtra
                : spec.frameDuration
        }
        frameIndex = 0
        drawnFrameIndex = -1
        frameStartTime = CACurrentMediaTime()
        loopsDone = 0
        finished = false
        currentRepeatCount = spec.repeatCount
        self.completion = completion
        startDisplayLink()
        needsDisplay = true
    }

    /// CVDisplayLink 在独立线程按屏幕实际刷新率回调，再在主线程推进动画，
    /// 比 Timer 精准且不受 RunLoop 模式影响。
    private func startDisplayLink() {
        if displayLink != nil { return } // 已运行则复用
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, context in
            guard let context else { return kCVReturnError }
            let view = Unmanaged<PetView>.fromOpaque(context).takeUnretainedValue()
            let now = CACurrentMediaTime()
            // 省电：没有即将到来的画面变化时，连主线程派发都省掉
            guard view.hasPendingWork(at: now) else { return kCVReturnSuccess }
            DispatchQueue.main.async {
                view.tick(now)
            }
            return kCVReturnSuccess
        }, userInfo)

        CVDisplayLinkStart(link)
        displayLink = link
    }

    /// 指定时刻是否有画面要变：到下一帧时刻 / 弹跳中 / 爱心飘浮中
    private func hasPendingWork(at now: CFTimeInterval) -> Bool {
        if !frames.isEmpty && !finished {
            return now >= frameStartTime + frameDurations[frameIndex]
        }
        return bounceT0 != nil || !hearts.isEmpty
    }

    private func stopDisplayLink() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
    }

    /// 窗口隐藏时调用：彻底暂停渲染省电
    func pauseRendering() {
        stopDisplayLink()
    }

    /// 窗口重新显示时调用：有未完成动画则恢复刷新
    func resumeRendering() {
        if !finished || bounceT0 != nil || !hearts.isEmpty {
            startDisplayLink()
        }
    }

    private func tick(_ now: CFTimeInterval) {
        guard !frames.isEmpty else { return }
        if !finished {
            if now - frameStartTime >= frameDurations[frameIndex] {
                frameIndex += 1
                frameStartTime = now
                if frameIndex >= frames.count {
                    loopsDone += 1
                    if let completion, loopsDone >= (currentRepeatCount ?? .max) {
                        // 有限循环播完：停在最后一帧，只回调一次
                        frameIndex = frames.count - 1
                        finished = true
                        self.completion = nil
                        completion()
                    } else {
                        frameIndex = 0
                    }
                }
            }
        }
        // 省电：画面内容没变就不重绘（静止帧 / 未到下一帧时刻）
        if frameIndex != drawnFrameIndex {
            drawnFrameIndex = frameIndex
            needsDisplay = true
        }
        // 弹跳与爱心是连续动画，需要持续重绘；全部静止后停掉 DisplayLink
        let hasMotion = !finished || bounceT0 != nil || !hearts.isEmpty
        if hasMotion {
            needsDisplay = true
        } else {
            stopDisplayLink()
        }
    }

    /// 开心弹跳一下：用 displayLink 手动驱动缩放，不碰 CA 图层
    func bounce() {
        bounceT0 = CACurrentMediaTime()
        startDisplayLink()
    }

    private var bounceScale: CGFloat {
        guard let bounceT0 else { return 1.0 }
        let p = (CACurrentMediaTime() - bounceT0) / bounceDuration
        if p >= 1 {
            self.bounceT0 = nil
            return 1.0
        }
        let f = p * CGFloat(bounceKeys.count - 1)
        let i = min(Int(f), bounceKeys.count - 2)
        let frac = f - CGFloat(i)
        return bounceKeys[i] + (bounceKeys[i + 1] - bounceKeys[i]) * frac
    }

    // MARK: - 倒计时气泡

    /// 更新气泡文字；传 nil 隐藏气泡
    func updateTime(_ text: String?, dimmed: Bool = false) {
        timeText = text
        timeDimmed = dimmed
        needsDisplay = true
    }

    // MARK: - 绘制

    /// 宠物本体区域：底部正方形
    private var petArea: NSRect {
        let side = min(bounds.width, bounds.height)
        return NSRect(x: 0, y: 0, width: bounds.width, height: side)
    }

    private func contentRect(for image: NSImage, in area: NSRect) -> NSRect {
        let padding: CGFloat = 8
        let s = bounceScale
        let scale = s * min(
            (area.width - padding * 2) / image.size.width,
            (area.height - padding * 2) / image.size.height
        )
        let w = image.size.width * scale
        let h = image.size.height * scale
        return NSRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    /// 画一帧；支持水平镜像（转身）
    private func drawFrame(_ image: NSImage, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext.current!.cgContext
        if mirrorHorizontally {
            ctx.translateBy(x: rect.midX, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.translateBy(x: -rect.midX, y: 0)
        }
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBubble() {
        guard let timeText else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: max(10, 17 * viewScale), weight: .semibold)
        let textColor = NSColor.white.withAlphaComponent(timeDimmed ? 0.6 : 1.0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = timeText.size(withAttributes: attrs)

        let padX: CGFloat = 14 * viewScale
        let padY: CGFloat = 6 * viewScale
        let bubbleW = textSize.width + padX * 2
        let bubbleH = textSize.height + padY * 2
        let x = (bounds.width - bubbleW) / 2
        let y = petArea.maxY + 8 * viewScale
        let rect = NSRect(x: x, y: y, width: bubbleW, height: bubbleH)

        // 气泡主体
        let path = NSBezierPath(roundedRect: rect, xRadius: bubbleH / 2, yRadius: bubbleH / 2)
        NSColor(calibratedWhite: 0.12, alpha: timeDimmed ? 0.45 : 0.78).setFill()
        path.fill()

        // 指向猫头顶的小尾巴
        let tipX = bounds.width / 2
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tipX - 6 * viewScale, y: y + 1))
        tail.line(to: NSPoint(x: tipX + 6 * viewScale, y: y + 1))
        tail.line(to: NSPoint(x: tipX, y: y - 7 * viewScale))
        tail.close()
        tail.fill()

        // 文字垂直居中
        timeText.draw(
            at: NSPoint(x: x + padX, y: y + (bubbleH - textSize.height) / 2 - 1),
            withAttributes: attrs
        )
    }

    private func drawHungerBubble() {
        guard let hungerText else { return }

        let font = NSFont.systemFont(ofSize: max(10, 13 * viewScale), weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = hungerText.size(withAttributes: attrs)

        let padX: CGFloat = 12 * viewScale
        let padY: CGFloat = 5 * viewScale
        let bubbleW = textSize.width + padX * 2
        let bubbleH = textSize.height + padY * 2
        let x = (bounds.width - bubbleW) / 2
        // 有倒计时气泡时叠在它上方，否则贴在宠物头顶
        let y = (timeText != nil)
            ? petArea.maxY + 8 * viewScale + (17 * viewScale + 12 * viewScale) + 6 * viewScale
            : petArea.maxY + 8 * viewScale
        let rect = NSRect(x: x, y: y, width: bubbleW, height: bubbleH)

        let path = NSBezierPath(roundedRect: rect, xRadius: bubbleH / 2, yRadius: bubbleH / 2)
        NSColor(calibratedRed: 0.85, green: 0.45, blue: 0.25, alpha: 0.85).setFill()
        path.fill()

        // 指向头顶的小尾巴
        let tipX = bounds.width / 2
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tipX - 5 * viewScale, y: y + 1))
        tail.line(to: NSPoint(x: tipX + 5 * viewScale, y: y + 1))
        tail.line(to: NSPoint(x: tipX, y: y - 6 * viewScale))
        tail.close()
        tail.fill()

        hungerText.draw(
            at: NSPoint(x: x + padX, y: y + (bubbleH - textSize.height) / 2 - 1),
            withAttributes: attrs
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)

        guard let index = AnimationFrameSelection.currentIndex(frameIndex, frameCount: frames.count) else { return }
        let area = petArea
        drawFrame(frames[index], in: contentRect(for: frames[index], in: area))

        drawHearts(CACurrentMediaTime())
        drawBubble()
        drawHungerBubble()
    }

    // MARK: - 拖拽移动窗口

    override func mouseDown(with event: NSEvent) {
        // 双击：触发互动，不进入拖拽；同时取消刚排队的单击（避免双击变两次投喂）
        if event.clickCount >= 2 {
            tapWorkItem?.cancel()
            tapWorkItem = nil
            onDoubleTap?()
            return
        }
        isBeingDragged = true
        onDragPickup?()
        let originBefore = window?.frame.origin
        // 交给 WindowServer 拖拽：窗口纹理直接跟随光标，不经过事件队列，零延迟。
        // performDrag 会在鼠标抬起时才返回，期间乱窜调度看到 isBeingDragged 会自动避让。
        window?.performDrag(with: event)
        isBeingDragged = false
        // 松手：通知是否真的是拖拽（决定「被放下」音效/动画）
        if let before = originBefore, let after = window?.frame.origin {
            let dist = hypot(after.x - before.x, after.y - before.y)
            onDragPutDown?(dist >= 6)
            // 原地单击（几乎没拖动）→ 延迟确认投喂，给双击判定留窗口
            if dist < 6 {
                tapWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self, !self.isBeingDragged else { return }
                    self.onTap?()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: item)
                tapWorkItem = item
            } else {
                tapWorkItem?.cancel()
                tapWorkItem = nil
            }
        } else {
            onDragPutDown?(false)
            tapWorkItem?.cancel()
            tapWorkItem = nil
        }
    }

    // 注意：不要再覆写 mouseDragged 手动 setFrameOrigin —— 那条路径走事件队列，
    // 主线程被动画绘制占住时会跟不上光标（宠物被甩在鼠标后面）。

    // MARK: - 右键

    override func rightMouseDown(with event: NSEvent) {
        onShowMenu?(event)
    }
}
