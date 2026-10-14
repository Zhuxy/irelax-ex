import SwiftUI

/// iRelaxEx 入口：纯菜单栏应用（LSUIElement），无 Dock 图标。
@main
struct iRelaxExApp: App {
    @StateObject private var timer: FocusTimer
    @StateObject private var audio: NoiseEngine
    private let overlay: RestOverlayManager

    init() {
        let timer = FocusTimer()
        let audio = NoiseEngine()
        let overlay = RestOverlayManager()
        // 休息遮罩跟随 timer.phase 自动弹出/关闭
        overlay.bind(timer: timer, audio: audio)
        _timer = StateObject(wrappedValue: timer)
        _audio = StateObject(wrappedValue: audio)
        self.overlay = overlay
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(timer)
                .environmentObject(audio)
        } label: {
            if timer.phase == .idle {
                Image(systemName: "timer")
            } else {
                Text(timer.menuBarTitle)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
