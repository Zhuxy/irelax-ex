import SwiftUI

/// iRelaxEx 入口：纯菜单栏应用（LSUIElement），无 Dock 图标。
@main
struct iRelaxExApp: App {
    @StateObject private var timer = FocusTimer()
    @StateObject private var audio = NoiseEngine()

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
