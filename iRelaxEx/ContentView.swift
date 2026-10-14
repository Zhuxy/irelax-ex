import SwiftUI
import ServiceManagement

/// 主弹窗。复刻原版 iRelax 1.6 的布局与配色（颜色均为原版截图像素采样值）：
/// 绿"开始工作" / 黄"开始休息"大按钮、时间设置区、2x2 开关项。
/// 与原版一致：计时中也可以直接按另一个按钮切换阶段。
struct ContentView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var audio: NoiseEngine
    @State private var launchAtLogin = false

    // 原版配色（截图像素采样）
    private let workGreen = Color(red: 0, green: 204 / 255, blue: 16 / 255)        // #00CC10
    private let restYellow = Color(red: 209 / 255, green: 193 / 255, blue: 1 / 255) // #D1C101

    var body: some View {
        VStack(spacing: 0) {
            Text("iRelaxEx 1.0")
                .font(.headline)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if timer.phase != .idle {
                runningSection
                Divider()
            }

            // 开始按钮：原版行为——计时中直接按另一个按钮即切换阶段
            VStack(spacing: 10) {
                Button("开始工作") { timer.startWork() }
                    .buttonStyle(.borderedProminent)
                    .tint(workGreen)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("开始休息") { timer.startRest() }
                    .buttonStyle(.borderedProminent)
                    .tint(restYellow)
                    .foregroundStyle(.black)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
                .padding(.vertical, 8)

            // 时间设置：上下箭头 stepper（原版旋钮不好用，按要求换掉）
            VStack(alignment: .leading, spacing: 8) {
                Text("时间设置")
                    .font(.headline)
                HStack {
                    Text("工作")
                    Spacer()
                    Text("\(timer.workMinutes) 分钟")
                        .foregroundStyle(.secondary)
                    Stepper("", value: $timer.workMinutes, in: 5...120, step: 5)
                        .labelsHidden()
                }
                HStack {
                    Text("休息")
                    Spacer()
                    Text("\(timer.restMinutes) 分钟")
                        .foregroundStyle(.secondary)
                    Stepper("", value: $timer.restMinutes, in: 1...60, step: 1)
                        .labelsHidden()
                }
            }
            .padding(.horizontal)
            .disabled(timer.phase != .idle)

            Divider()
                .padding(.vertical, 8)

            // 环境音（紧凑横排）
            VStack(alignment: .leading, spacing: 6) {
                Text("环境音")
                    .font(.headline)
                HStack(spacing: 8) {
                    ForEach(NoiseEngine.Sound.allCases) { sound in
                        Button { audio.toggle(sound) } label: {
                            Image(systemName: sound.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(sound.tint.opacity(audio.activeSound == sound ? 1 : 0.35))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help(sound.title)
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").font(.caption)
                    Slider(value: $audio.volume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").font(.caption)
                }
            }
            .padding(.horizontal)

            Divider()
                .padding(.vertical, 8)

            // 2x2 开关项（复刻原版）
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading),
                          GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                Toggle("不可跳过", isOn: $timer.restUnskippable)
                Button("撰写评论") { openReview() }
                    .buttonStyle(.link)
                Toggle("开机启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                Button("退出程序") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            // timer 与 audio 都是 App 持有的 StateObject，timer → chimeHandler → audio
            // 是单向引用，不存在循环引用，强捕获即可
            timer.chimeHandler = { audio.chime() }
        }
    }

    // MARK: - 运行中状态

    private var runningSection: some View {
        VStack(spacing: 8) {
            Text(timer.phase == .work ? "工作中" : "休息中")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(timer.formatted)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .monospacedDigit()
            ProgressView(value: timer.progress)
                .padding(.horizontal)
            HStack(spacing: 24) {
                Button(timer.paused ? "继续" : "暂停") {
                    timer.paused ? timer.resume() : timer.pause()
                }
                Button("结束") { timer.reset() }
            }
            .buttonStyle(.link)
            .padding(.bottom, 2)
        }
        .padding(.horizontal)
    }

    // MARK: - 动作

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

    private func openReview() {
        // 原版此处跳转 App Store 写评论；重实现指向本仓库
        if let url = URL(string: "https://github.com/Zhuxy/irelax-ex") {
            NSWorkspace.shared.open(url)
        }
    }
}
