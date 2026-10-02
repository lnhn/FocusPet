import Foundation

/// 番茄钟引擎：支持 专注 → 短休/长休 的完整循环。
///
/// 会话流：startFocus() 开始专注，专注完成自动由调用方决定下一步（通常 startRest()）；
/// 休息完成回到 idle，等待下一轮。纯逻辑不碰 UI。
final class FocusEngine {
    enum Kind: String {
        case focus
        case shortRest
        case longRest

        var isRest: Bool { self != .focus }
    }

    enum Phase {
        case idle
        case running
        case paused
    }

    struct Session {
        let kind: Kind
        let duration: TimeInterval
    }

    // MARK: 配置（可在设置面板中随时修改）

    var focusDuration: TimeInterval
    var shortRestDuration: TimeInterval
    var longRestDuration: TimeInterval
    /// 每完成几个专注来一次长休息（经典番茄钟 = 4）
    var focusesPerCycle: Int

    // MARK: 状态

    private(set) var phase: Phase = .idle
    private(set) var session: Session?
    private(set) var remaining: TimeInterval = 0
    private(set) var completedFocuses = 0

    // MARK: 回调

    /// 每秒回调一次剩余秒数
    var onTick: ((TimeInterval) -> Void)?
    /// 运行/暂停/空闲 切换
    var onPhaseChange: ((Phase) -> Void)?
    /// 新会话开始
    var onSessionStart: ((Session) -> Void)?
    /// 会话自然走完（专注/休息完成）
    var onSessionComplete: ((Session) -> Void)?

    private var timer: Timer?

    init(
        focusDuration: TimeInterval = 25 * 60,
        shortRestDuration: TimeInterval = 5 * 60,
        longRestDuration: TimeInterval = 15 * 60,
        focusesPerCycle: Int = 4
    ) {
        self.focusDuration = focusDuration
        self.shortRestDuration = shortRestDuration
        self.longRestDuration = longRestDuration
        self.focusesPerCycle = focusesPerCycle
    }

    // MARK: - 控制

    func startFocus() {
        start(session: Session(kind: .focus, duration: focusDuration))
    }

    /// 按「已完成专注数」决定短休还是长休（每 focusesPerCycle 轮一次长休）
    func startRest() {
        let isLong = completedFocuses > 0 && completedFocuses % focusesPerCycle == 0
        start(session: Session(
            kind: isLong ? .longRest : .shortRest,
            duration: isLong ? longRestDuration : shortRestDuration
        ))
    }

    func pause() {
        guard phase == .running else { return }
        setPhase(.paused)
    }

    func resume() {
        guard phase == .paused else { return }
        setPhase(.running)
    }

    /// 提前结束当前会话（放弃专注 / 跳过休息），不计入完成数
    func stop() {
        stopTimer()
        session = nil
        remaining = 0
        setPhase(.idle)
    }

    // MARK: - 内部

    private func start(session newSession: Session) {
        stopTimer()
        session = newSession
        remaining = newSession.duration
        setPhase(.running)
        onSessionStart?(newSession)
        // 暂停时不倒计时，所以 timer 常驻、闸控即可，避免暂停/恢复计时漂移
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.phase == .running else { return }
            self.remaining = max(0, self.remaining - 1)
            self.onTick?(self.remaining)
            if self.remaining <= 0 {
                self.completeSession()
            }
        }
    }

    private func completeSession() {
        stopTimer()
        guard let finished = session else { return }
        if finished.kind == .focus {
            completedFocuses += 1
        }
        session = nil
        remaining = 0
        setPhase(.idle)
        onSessionComplete?(finished)
    }

    private func setPhase(_ newPhase: Phase) {
        guard phase != newPhase else { return }
        phase = newPhase
        onPhaseChange?(newPhase)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
