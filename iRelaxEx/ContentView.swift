import SwiftUI
import ServiceManagement

/// 主弹窗。复刻原版 iRelax 1.6 的布局与配色（颜色均为原版截图像素采样值）：
/// 绿"开始工作" / 黄"开始休息"大按钮（居中 190 宽）、时间设置区、2x2 开关项。
/// 与原版一致：计时中也可以直接按另一个按钮切换阶段。
struct ContentView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var audio: NoiseEngine
    @State private var launchAtLogin = false

    // 原版配色（截图像素采样）
    private let workGreen = Color(red: 0, green: 204 / 255, blue: 16 / 255)        // #00CC10
    private let restYellow = Color(red: 209 / 255, green: 193 / 255, blue: 1 / 255) // #D1C101
    private let popBg = Color(red: 0xED / 255.0, green: 0xED / 255.0, blue: 0xEC / 255.0) // #EDEDEC 弹窗底色
    private let titleGray = Color(red: 0x79 / 255.0, green: 0x74 / 255.0, blue: 0x6F / 255.0) // #79746F 标题
    private let bodyGray = Color(red: 0x3F / 255.0, green: 0x3F / 255.0, blue: 0x3F / 255.0)  // #3F3F3F 正文
    private let labelGray = Color(red: 0x70 / 255.0, green: 0x70 / 255.0, blue: 0x6F / 255.0) // #70706F 复选框/链接
    private let btnWhite = Color(red: 0xED / 255.0, green: 0xEC / 255.0, blue: 0xEC / 255.0)  // #EDECEC 绿按钮字
    private let btnDark = Color(red: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x22 / 255.0)   // #222222 黄按钮字

    var body: some View {
        VStack(spacing: 0) {
            Text("iRelaxEx 1.0")
                .font(.headline)
                .foregroundStyle(titleGray)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if timer.phase != .idle {
                runningSection
                Divider()
            }

            // 开始按钮：原版行为——计时中直接按另一个按钮即切换阶段。
            // 原版按钮居中 190 宽（非通栏），白字/深字均为采样值。
            VStack(spacing: 10) {
                Button(action: { timer.startWork() }) {
                    Text("开始工作")
                        .font(.headline)
                        .foregroundStyle(btnWhite)
                        .frame(width: 190, height: 32)
                        .background(workGreen)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                Button(action: { timer.startRest() }) {
                    Text("开始休息")
                        .font(.headline)
                        .foregroundStyle(btnDark)
                        .frame(width: 190, height: 32)
                        .background(restYellow)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Divider()
                .padding(.vertical, 8)

            // 时间设置：上下箭头 stepper（原版旋钮不好用，按要求换掉）。
            // 原版分钟数下方有绿色下划线，保留这个细节。
            VStack(alignment: .leading, spacing: 8) {
                Text("时间设置")
                    .font(.headline)
                    .foregroundStyle(bodyGray)
                HStack {
                    Text("工作")
                        .foregroundStyle(bodyGray)
                    Spacer()
                    Text("\(timer.workMinutes) 分钟")
                        .foregroundStyle(bodyGray)
                        .underline(color: workGreen)
                    Stepper("", value: $timer.workMinutes, in: 5...120, step: 5)
                        .labelsHidden()
                }
                HStack {
                    Text("休息")
                        .foregroundStyle(bodyGray)
                    Spacer()
                    Text("\(timer.restMinutes) 分钟")
                        .foregroundStyle(bodyGray)
                        .underline(color: workGreen)
                    Stepper("", value: $timer.restMinutes, in: 1...60, step: 1)
                        .labelsHidden()
                }
            }
            .padding(.horizontal)
            .disabled(timer.phase != .idle)

            Divider()
                .padding(.vertical, 8)

            // 2x2 开关项（复刻原版；原版此处为灰色文字）
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading),
                          GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                Toggle("不可跳过", isOn: $timer.restUnskippable)
                    .foregroundStyle(labelGray)
                Button("撰写评论") { openReview() }
                    .buttonStyle(.plain)
                    .foregroundStyle(labelGray)
                Toggle("开机启动", isOn: $launchAtLogin)
                    .foregroundStyle(labelGray)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                Button("退出程序") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(labelGray)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
        .background(popBg)
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
                .foregroundStyle(labelGray)
            Text(timer.formatted)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(bodyGray)
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
