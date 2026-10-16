import Foundation
import UserNotifications

/// 番茄钟倒计时模型。clean-room 重实现：行为对标原版（工作/休息两阶段、
/// 分钟级时长配置、阶段结束提醒），实现全部重写。
///
/// CPU 友好设计：只用一个 1Hz 的 Timer 驱动倒计时，不做高频 UI 轮询——
/// 这正是原版在新 macOS 上 CPU 居高不下的最可能病因（见 docs/RE-NOTES.md）。
final class FocusTimer: ObservableObject {
    enum Phase {
        case idle, work, rest
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: Int = 20 * 60
    @Published private(set) var paused = false

    @Published var workMinutes: Int = 20 { didSet { save(); resetIfIdle() } }
    @Published var restMinutes: Int = 2 { didSet { save() } }
    @Published var notifyOnPhaseEnd = true { didSet { save() } }
    /// 对应原版 "NotSkip"：打开后休息阶段不可跳过
    @Published var restUnskippable = false { didSet { save() } }

    /// 阶段结束时播放提示音，由 ContentView 注入（避免循环依赖 NoiseEngine）
    var chimeHandler: (() -> Void)?

    private var tick: Timer?
    private let defaults = UserDefaults.standard
    private let defaultsVersionKey = "irelaxex.defaultsVersion"
    /// 当前阶段的 wall-clock 截止时间。睡眠期间 timer 不触发，
    /// 醒来后用它校准 remaining，避免 tick 计数漂移。
    private var endDate: Date?

    init() {
        // v2: 默认值强制对齐原版（工作 20 分钟 / 休息 2 分钟）。
        // v1 只在 version key 缺失时迁移，但旧 build 的 didSet→save 可能已写入 25/5
        // 且 version key 已存在，导致 v1 迁移被跳过、5 分钟残留；v2 直接覆盖一次。
        if defaults.integer(forKey: defaultsVersionKey) < 2 {
            defaults.set(20, forKey: "workMinutes")
            defaults.set(2, forKey: "restMinutes")
            defaults.set(2, forKey: defaultsVersionKey)
        }
        workMinutes = max(1, defaults.integer(forKey: "workMinutes", default: 20))
        restMinutes = max(1, defaults.integer(forKey: "restMinutes", default: 2))
        notifyOnPhaseEnd = defaults.bool(forKey: "notifyOnPhaseEnd", default: true)
        restUnskippable = defaults.bool(forKey: "restUnskippable", default: false)
        remaining = workMinutes * 60
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 派生状态

    var totalSeconds: Int {
        switch phase {
        case .work: return workMinutes * 60
        case .rest: return restMinutes * 60
        case .idle: return workMinutes * 60
        }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1.0 - Double(remaining) / Double(totalSeconds)
    }

    var menuBarTitle: String {
        switch phase {
        case .idle: return "⏱"
        case .work: return "🍅 " + formatted
        case .rest: return "☕️ " + formatted
        }
    }

    var formatted: String {
        String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    var phaseName: String {
        switch phase {
        case .idle: return "就绪"
        case .work: return "工作中"
        case .rest: return "休息中"
        }
    }

    // MARK: - 控制

    func startWork() {
        begin(phase: .work, seconds: workMinutes * 60)
    }

    func startRest() {
        begin(phase: .rest, seconds: restMinutes * 60)
    }

    func pause() {
        paused = true
        tick?.invalidate()
        tick = nil
        endDate = nil
    }

    func resume() {
        guard phase != .idle, paused else { return }
        paused = false
        endDate = Date().addingTimeInterval(TimeInterval(remaining))
        scheduleTick()
    }

    func reset() {
        tick?.invalidate()
        tick = nil
        phase = .idle
        paused = false
        remaining = workMinutes * 60
        endDate = nil
    }

    func skipRest() {
        guard phase == .rest, !restUnskippable else { return }
        // 跳过休息后回到从头计时（直接开始一轮新的工作），而不是回到空闲
        startWork()
    }

    // MARK: - 内部

    private func begin(phase: Phase, seconds: Int) {
        tick?.invalidate()
        self.phase = phase
        self.remaining = seconds
        self.paused = false
        self.endDate = Date().addingTimeInterval(TimeInterval(seconds))
        scheduleTick()
    }

    private func scheduleTick() {
        tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        // 让 timer 在 UI 追踪（如拖动 slider）时也不停
        if let tick { RunLoop.main.add(tick, forMode: .common) }
    }

    private func onTick() {
        // 用 wall-clock 校准剩余时间：睡眠期间 timer 不触发，
        // 醒来后按实际流逝时间结算，而不是按 tick 次数
        if let end = endDate {
            remaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        } else if remaining > 0 {
            remaining -= 1
        }
        if remaining <= 0 {
            finishPhase()
        }
    }

    private func finishPhase() {
        tick?.invalidate()
        tick = nil
        paused = false
        endDate = nil
        // 先切换状态，再做副作用（通知/音效）：chimeHandler 在睡眠唤醒后
        // 可能因音频引擎状态异常而卡住，必须不能让它阻塞状态机流转，
        // 否则就会卡在 00:00 的 work 状态再也走不下去
        let finished = phase
        switch finished {
        case .work:
            begin(phase: .rest, seconds: restMinutes * 60)
        case .rest:
            // 休息结束自动开始下一轮工作（番茄钟循环），而不是回到空闲
            startWork()
        case .idle:
            break
        }
        switch finished {
        case .work:
            notify(title: "工作结束", body: "该休息一下了 ☕️")
        case .rest:
            notify(title: "休息结束", body: "开始下一轮工作吧 🍅")
        case .idle:
            break
        }
        // 音效异步触发，即使音频引擎异常也不影响已切换的状态
        if finished != .idle {
            DispatchQueue.main.async { [weak self] in
                self?.chimeHandler?()
            }
        }
    }

    /// 系统从睡眠唤醒后调用：当前阶段从新计时（睡眠时间不计入专注/休息时长）
    func handleWake() {
        guard phase != .idle, !paused else { return }
        switch phase {
        case .work:
            begin(phase: .work, seconds: workMinutes * 60)
        case .rest:
            begin(phase: .rest, seconds: restMinutes * 60)
        case .idle:
            break
        }
    }

    private func notify(title: String, body: String) {
        guard notifyOnPhaseEnd else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func resetIfIdle() {
        if phase == .idle { remaining = workMinutes * 60 }
    }

    private func save() {
        defaults.set(workMinutes, forKey: "workMinutes")
        defaults.set(restMinutes, forKey: "restMinutes")
        defaults.set(notifyOnPhaseEnd, forKey: "notifyOnPhaseEnd")
        defaults.set(restUnskippable, forKey: "restUnskippable")
    }
}

private extension UserDefaults {
    func integer(forKey key: String, default value: Int) -> Int {
        object(forKey: key) == nil ? value : integer(forKey: key)
    }
    func bool(forKey key: String, default value: Bool) -> Bool {
        object(forKey: key) == nil ? value : bool(forKey: key)
    }
}
