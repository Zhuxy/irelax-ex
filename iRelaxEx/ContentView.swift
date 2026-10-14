import SwiftUI
import ServiceManagement

/// 菜单栏弹出窗口。对标原版主界面（大按钮 + 时长设置 + 声音 + 开关项），
/// 用 SwiftUI 重写。
struct ContentView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var audio: NoiseEngine
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: 计时区
            VStack(spacing: 8) {
                Text(timer.phaseName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(timer.phase == .rest ? .green : .orange,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: timer.progress)
                    Text(timer.formatted)
                        .font(.system(size: 40, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
                .frame(width: 150, height: 150)
                .padding(.vertical, 4)

                controlButtons
            }
            .padding()

            Divider()

            // MARK: 时长设置
            VStack(spacing: 6) {
                Stepper("工作 \(timer.workMinutes) 分钟",
                        value: $timer.workMinutes, in: 1...120)
                Stepper("休息 \(timer.restMinutes) 分钟",
                        value: $timer.restMinutes, in: 1...60)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .disabled(timer.phase != .idle)

            Divider()

            // MARK: 环境音
            VStack(alignment: .leading, spacing: 4) {
                Text("环境音")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)
                ForEach(NoiseEngine.Sound.allCases) { sound in
                    Button {
                        audio.toggle(sound)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sound.title)
                                Text(sound.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if audio.activeSound == sound {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.blue)
                            } else {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 3)
                }
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $audio.volume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // MARK: 设置
            VStack(spacing: 6) {
                Toggle("开机启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, perform: setLaunchAtLogin)
                Toggle("阶段结束时通知", isOn: $timer.notifyOnPhaseEnd)
                Toggle("休息不可跳过", isOn: $timer.restUnskippable)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Button("退出 iRelaxEx") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            // timer 与 audio 都是 App 持有的 StateObject，timer → chimeHandler → audio
            // 是单向引用，不存在循环引用，这里用强捕获即可（weak 反而触发编译器警告）
            timer.chimeHandler = { audio.chime() }
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        switch timer.phase {
        case .idle:
            Button("开始工作") { timer.startWork() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .work:
            HStack(spacing: 12) {
                if timer.paused {
                    Button("继续") { timer.resume() }
                } else {
                    Button("暂停") { timer.pause() }
                }
                Button("结束") { timer.reset() }
            }
            .controlSize(.large)
        case .rest:
            HStack(spacing: 12) {
                if timer.paused {
                    Button("继续") { timer.resume() }
                } else {
                    Button("暂停") { timer.pause() }
                }
                if !timer.restUnskippable {
                    Button("跳过休息") { timer.skipRest() }
                }
            }
            .controlSize(.large)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 注册失败时回滚开关状态
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
