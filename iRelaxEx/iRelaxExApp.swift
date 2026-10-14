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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let timer = FocusTimer()
    private let audio = NoiseEngine()
    private let overlay = RestOverlayManager()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // timer → chimeHandler → audio 是单向引用，不存在循环引用
        timer.chimeHandler = { [weak self] in self?.audio.chime() }
        // 休息遮罩跟随 timer.phase 自动弹出/关闭（只盖主显示器）
        overlay.bind(timer: timer, audio: audio)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        let po = NSPopover()
        po.behavior = .transient // 点弹窗外面自动关闭（标准行为）
        po.animates = true
        let content = ContentView(onPhaseStarted: { [weak po] in
            // 开始工作/休息后自动关闭弹窗（原版行为）
            po?.performClose(nil)
        })
        .environmentObject(timer)
        .environmentObject(audio)
        po.contentViewController = NSHostingController(rootView: content)
        popover = po

        // 菜单栏：空闲显示图标，计时中显示倒计时（phase/remaining 变化时刷新）
        timer.$phase
            .combineLatest(timer.$remaining)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshStatusItem() }
            .store(in: &cancellables)
        refreshStatusItem()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
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
