import SwiftUI
import Combine

/// iRelaxEx 入口：纯菜单栏应用（LSUIElement），无 Dock 图标。
/// 使用 AppKit NSStatusItem + NSPopover（与原版 iRelax 相同的架构），
/// 因为 SwiftUI MenuBarExtra 没有公开的 API 可以程序化关闭弹窗，
/// 而原版行为要求：点"开始工作"/"开始休息"后弹窗自动关闭。
@main
struct iRelaxExApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let timer = FocusTimer()
    private let audio = NoiseEngine()
    private let overlay = RestOverlayManager()
    private let banner = WarningBannerManager()
    private var cancellables = Set<AnyCancellable>()
    /// 外部点击监听（transient 在 LSUIElement 下不可靠，显式补充）
    private var popoverMonitor: Any?
    /// monitor 触发关闭的时间戳，用于忽略"关闭后同一次按钮点击"的重开
    private var lastMonitorClose = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        // timer → chimeHandler → audio 是单向引用，不存在循环引用
        timer.chimeHandler = { [weak self] in self?.audio.chime() }
        // 休息遮罩跟随 timer.phase 自动弹出/关闭（盖所有屏，对话框只在主屏）
        overlay.bind(timer: timer, audio: audio)
        // 10 秒预警横幅：工作剩 10 秒时从主屏上方掉下
        banner.bind(timer: timer)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        let po = NSPopover()
        po.behavior = .transient // 点弹窗外面自动关闭（标准行为；另有显式监听兜底）
        po.animates = true
        po.delegate = self
        let content = ContentView(onPhaseStarted: { [weak po] in
            // 开始工作/休息后自动关闭弹窗（原版行为）
            po?.performClose(nil)
        })
        .environmentObject(timer)
        .environmentObject(audio)
        po.contentViewController = NSHostingController(rootView: content)
        popover = po

        // 系统唤醒后直接开始新一轮工作（合盖即休息，开盖重新开工）
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // 菜单栏：空闲显示图标，计时中显示倒计时（phase/remaining 变化时刷新）
        timer.$phase
            .combineLatest(timer.$remaining)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshStatusItem() }
            .store(in: &cancellables)
        refreshStatusItem()
    }

    @objc private func systemDidWake(_ note: Notification) {
        timer.handleWake()
    }

    @objc private func togglePopover(_ sender: Any?) {        guard let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            // 忽略 monitor 刚关闭后的同一次按钮点击，避免"关了又立刻重开"
            if Date().timeIntervalSince(lastMonitorClose) < 0.3 { return }
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        if let m = popoverMonitor { NSEvent.removeMonitor(m); popoverMonitor = nil }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // 显式监听外部点击：transient 在 LSUIElement 下可能不可靠，兜底关闭
        popoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopoverFromMonitor()
        }
    }

    private func closePopover() {
        if let m = popoverMonitor { NSEvent.removeMonitor(m); popoverMonitor = nil }
        popover?.performClose(nil)
    }

    private func closePopoverFromMonitor() {
        guard let popover, popover.isShown else { return }
        lastMonitorClose = Date()
        closePopover()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // 任何原因关闭（transient/Esc/performClose）都清理监听
        if let m = popoverMonitor { NSEvent.removeMonitor(m); popoverMonitor = nil }
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        if timer.phase == .idle {
            button.title = ""
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "iRelaxEx")
        } else {
            button.title = timer.menuBarTitle
            button.image = nil
        }
    }
}
