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
    @Published private(set) var remaining: Int = 25 * 60
    @Published private(set) var paused = false

    @Published var workMinutes: Int = 25 { didSet { save(); resetIfIdle() } }
    @Published var restMinutes: Int = 5 { didSet { save() } }
    @Published var notifyOnPhaseEnd = true { didSet { save() } }
    /// 对应原版 "NotSkip"：打开后休息阶段不可跳过
    @Published var restUnskippable = false { didSet { save() } }

    /// 阶段结束时播放提示音，由 ContentView 注入（避免循环依赖 NoiseEngine）
    var chimeHandler: (() -> Void)?

    private var tick: Timer?
    private let defaults = UserDefaults.standard

    init() {
        workMinutes = max(1, defaults.integer(forKey: "workMinutes", default: 25))
        restMinutes = max(1, defaults.integer(forKey: "restMinutes", default: 5))
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
    }

    func resume() {
        guard phase != .idle, paused else { return }
        paused = false
        scheduleTick()
    }

    func reset() {
        tick?.invalidate()
        tick = nil
        phase = .idle
        paused = false
        remaining = workMinutes * 60
    }

    func skipRest() {
        guard phase == .rest, !restUnskippable else { return }
        reset()
    }

    // MARK: - 内部

    private func begin(phase: Phase, seconds: Int) {
        tick?.invalidate()
        self.phase = phase
        self.remaining = seconds
        self.paused = false
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
        guard remaining > 0 else {
            finishPhase()
            return
        }
        remaining -= 1
        if remaining == 0 { finishPhase() }
    }

    private func finishPhase() {
        tick?.invalidate()
        tick = nil
        paused = false
        switch phase {
        case .work:
            notify(title: "工作结束", body: "该休息一下了 ☕️")
            chimeHandler?()
            begin(phase: .rest, seconds: restMinutes * 60)
        case .rest:
            notify(title: "休息结束", body: "开始下一轮工作吧 🍅")
            chimeHandler?()
            reset()
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
