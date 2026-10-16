import SwiftUI
import ServiceManagement

/// 主弹窗。复刻原版 iRelax 1.6 的布局与配色（颜色均为原版截图像素采样值）：
/// 绿/黄大按钮（居中 190 宽）、运行进度条、时间设置区、2x2 开关项。
/// 原版行为：
/// - 点"开始工作"/"开始休息"后弹窗自动关闭（由 onPhaseStarted 回调实现）；
/// - 工作中绿按钮变为"取消工作"，休息中黄按钮变为"取消休息"；
/// - 计时中也可以直接按另一个按钮切换阶段。
struct ContentView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var audio: NoiseEngine
    @State private var launchAtLogin = false
    /// 开始工作/开始休息（进入计时）后调用，AppDelegate 用它关闭弹窗
    var onPhaseStarted: () -> Void = {}

    // 原版配色（截图像素采样）
    private let workGreen = Color(red: 0, green: 204 / 255, blue: 16 / 255)        // #00CC10
    private let restYellow = Color(red: 209 / 255, green: 193 / 255, blue: 1 / 255) // #D1C101
    private let popBg = Color(red: 0xED / 255.0, green: 0xED / 255.0, blue: 0xEC / 255.0) // #EDEDEC 弹窗底色
    private let titleGray = Color(red: 0x79 / 255.0, green: 0x74 / 255.0, blue: 0x6F / 255.0) // #79746F 标题
    private let bodyGray = Color(red: 0x3F / 255.0, green: 0x3F / 255.0, blue: 0x3F / 255.0)  // #3F3F3F 正文
    private let labelGray = Color(red: 0x70 / 255.0, green: 0x70 / 255.0, blue: 0x6F / 255.0) // #70706F 复选框/链接

    private var isWorking: Bool { timer.phase == .work }
    private var isResting: Bool { timer.phase == .rest }
    private var isRunning: Bool { timer.phase != .idle }

    var body: some View {
        VStack(spacing: 0) {
            Text("iRelaxEx 1.0")
                .font(.headline)
                .foregroundStyle(titleGray)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // 开始按钮：工作中绿按钮变为"取消工作"；休息中黄按钮禁用
            // （遮罩盖住菜单栏，弹窗打不开，取消休息走主屏对话框的"跳过"）
            VStack(spacing: 10) {
                Button(action: {
                    if isWorking {
                        timer.reset()
                    } else {
                        timer.startWork()
                        onPhaseStarted()
                    }
                }) {
                    Text(isWorking ? "取消工作" : "开始工作")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 190, height: 32)
                        .background(workGreen)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // 黄按钮：工作中可直接按切换到休息；休息中禁用——
                // 休息时遮罩盖住所有屏幕（含菜单栏），弹窗打不开；
                // 要提前结束休息请点主屏对话框上的"跳过"。
                Button(action: {
                    timer.startRest()
                    onPhaseStarted()
                }) {
                    Text("开始休息")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 190, height: 32)
                        .background(restYellow)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isResting)
                .opacity(isResting ? 0.45 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            // 计时中在按钮下方显示细进度条（原版布局）
            if isRunning {
                ProgressView(value: timer.progress)
                    .padding(.horizontal, 45)
                    .padding(.bottom, 8)
            }

            Divider()
                .padding(.vertical, 8)

            // 时间设置：原版工作/休息在同一行；上下箭头 stepper（原版旋钮不好用，按要求换掉）。
            // 原版分钟数下方有绿色下划线，保留这个细节。
            VStack(alignment: .leading, spacing: 8) {
                Text("时间设置")
                    .font(.headline)
                    .foregroundStyle(bodyGray)
                HStack(spacing: 6) {
                    Text("工作")
                        .foregroundStyle(bodyGray)
                    Text("\(timer.workMinutes) 分钟")
                        .foregroundStyle(bodyGray)
                        .underline(color: workGreen)
                    Stepper("", value: $timer.workMinutes, in: 1...120, step: 1)
                        .labelsHidden()
                    Spacer()
                    Text("休息")
                        .foregroundStyle(bodyGray)
                    Text("\(timer.restMinutes) 分钟")
                        .foregroundStyle(bodyGray)
                        .underline(color: workGreen)
                    Stepper("", value: $timer.restMinutes, in: 1...60, step: 1)
                        .labelsHidden()
                }
            }
            .padding(.horizontal)
            .disabled(isRunning)

            Divider()
                .padding(.vertical, 8)

            // 2x2 开关项（复刻原版；原版此处为灰色文字，撰写评论/退出程序前有小图标）
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading),
                          GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                Toggle("不可跳过", isOn: $timer.restUnskippable)
                    .foregroundStyle(labelGray)
                Button(action: { openReview() }) {
                    Label("撰写评论", systemImage: "eye")
                        .foregroundStyle(labelGray)
                }
                .buttonStyle(.plain)
                Toggle("开机启动", isOn: $launchAtLogin)
                    .foregroundStyle(labelGray)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Label("退出程序", systemImage: "asterisk")
                        .foregroundStyle(labelGray)
                }
                .buttonStyle(.plain)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
        .background(popBg)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
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
