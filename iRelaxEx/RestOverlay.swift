import SwiftUI
import Combine
import AppKit

// MARK: - 声音图标映射（UI 层，不污染 NoiseEngine）

extension NoiseEngine.Sound {
    var icon: String {
        switch self {
        case .rain:  return "cloud.rain.fill"
        case .sea:   return "sailboat.fill"
        case .wind:  return "wind"
        case .white: return "speaker.wave.2.fill"
        case .pink:  return "speaker.wave.3.fill"
        case .brown: return "speaker.fill"
        }
    }

    var tint: Color {
        // 原版截图像素采样
        switch self {
        case .rain:  return Color(red: 59 / 255, green: 163 / 255, blue: 205 / 255)  // #3BA3CD
        case .sea:   return Color(red: 46 / 255, green: 146 / 255, blue: 209 / 255)  // #2E92D1
        case .wind:  return Color(red: 84 / 255, green: 172 / 255, blue: 59 / 255)    // #54AC3B
        case .white: return Color(red: 212 / 255, green: 160 / 255, blue: 38 / 255)   // #D4A026
        case .pink:  return .pink
        case .brown: return .brown
        }
    }
}

// MARK: - 休息遮罩管理器

/// 复刻原版行为：进入休息阶段时弹出全屏半透明遮罩，强制休息；
/// 休息结束或跳过后自动关闭。
///
/// 实现：每个显示器一张无边框全屏窗口（screenSaver 层级，阻挡鼠标），
/// 内容为 SwiftUI 卡片（倒计时 + 声音图标 + 跳过）。
final class RestOverlayManager {
    private var windows: [NSWindow] = []
    private var cancellables = Set<AnyCancellable>()

    func bind(timer: FocusTimer, audio: NoiseEngine) {
        timer.$phase
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                if phase == .rest {
                    self?.show(timer: timer, audio: audio)
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)
    }

    private func show(timer: FocusTimer, audio: NoiseEngine) {
        // 立即清理旧窗口（不渐出，避免与新窗口重叠）
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        // 原版行为：所有显示器都盖遮罩，但只有主显示器有中央对话框
        // （倒计时/声音/跳过），副屏只有遮罩、不可交互。
        // 主显示器用 CGMainDisplayID 定位，不能用 NSScreen.main——
        // 后者会跟着当前 key window 走，导致定位到副屏上。
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let mainID = CGMainDisplayID()
        let main = screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == mainID
        } ?? screens[0]
        for screen in screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let view = RestOverlayView(showDialog: screen === main)
                .environmentObject(timer)
                .environmentObject(audio)
            window.contentView = NSHostingView(rootView: view)
            // 原版：遮罩不是蹦出来的，有约半秒的渐入动画
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            for w in windows { w.animator().alphaValue = 1 }
        }
    }

    private func hide() {
        let ws = windows
        windows.removeAll()
        guard !ws.isEmpty else { return }
        // 原版：休息结束时遮罩渐出（约半秒），而不是直接消失
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            for w in ws { w.animator().alphaValue = 0 }
        }, completionHandler: {
            for w in ws { w.orderOut(nil) }
        })
    }
}

// MARK: - 遮罩卡片 UI（复刻原版截图）

struct RestOverlayView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var audio: NoiseEngine
    /// 是否显示中央对话框。原版行为：所有显示器都盖遮罩，
    /// 但只有主显示器有中间对话框（倒计时/声音/跳过），副屏只有遮罩。
    var showDialog: Bool = true

    var body: some View {
        ZStack {
            // 原版遮罩接近纯黑（采样 [4,4,4]），用 0.85 不透明度
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {} // 吞掉点击，防止穿透

            if showDialog {
                dialog
            }
        }
    }

    private var dialog: some View {
        VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                    Text("iRelaxEx")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                // 黄色倒计时牌（复刻原版 #FFF704）
                Text(timer.formatted)
                    .font(.system(size: 54, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background(Color(red: 1, green: 247 / 255, blue: 4 / 255))
                    .cornerRadius(14)

                // 声音图标（复刻原版横排小方块）
                HStack(spacing: 10) {
                    ForEach(NoiseEngine.Sound.allCases) { sound in
                        Button { audio.toggle(sound) } label: {
                            Image(systemName: sound.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(sound.tint.opacity(audio.activeSound == sound ? 1 : 0.55))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .help(sound.title)
                    }
                }

                // 跳过（"不可跳过"打开时隐藏）
                if !timer.restUnskippable {
                    Button("跳过") { timer.skipRest() }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.22))
                        .cornerRadius(20)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .background(Color(red: 168 / 255, green: 168 / 255, blue: 168 / 255).opacity(0.94)) // 原版卡片灰 #A8A8A8
            .cornerRadius(26)
    }
}

// MARK: - 10 秒预警横幅（复刻原版）

/// 原版行为：工作倒计时剩 10 秒时，从主屏幕上方掉下一条提醒横幅，
/// 存在 10 秒（到休息开始），点一下缩上去。
final class WarningBannerManager {
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var showing = false
    /// 用户已手动收起：本轮工作不再重弹；进入新阶段时重置
    private var dismissed = false
    private var lastPhase: FocusTimer.Phase?

    func bind(timer: FocusTimer) {
        timer.$phase
            .combineLatest(timer.$remaining)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase, remaining in
                guard let self else { return }
                if phase != self.lastPhase {
                    self.lastPhase = phase
                    self.dismissed = false
                }
                if phase == .work && remaining <= 10 && remaining > 0 {
                    if !self.showing && !self.dismissed { self.show(timer: timer) }
                } else {
                    // 休息开始（遮罩接管）/取消/结束时收起
                    self.hide()
                }
            }
            .store(in: &cancellables)
    }

    private func mainScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let mainID = CGMainDisplayID()
        return screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == mainID
        } ?? screens.first
    }

    private func show(timer: FocusTimer) {
        guard let screen = mainScreen() else { return }
        showing = true
        // 徽章 82（110 的 3/4）+ 悬线 38 + 内边距（左右 6、下 8）
        let w: CGFloat = 94, h: CGFloat = 128
        let finalFrame = NSRect(
            x: screen.frame.minX + (screen.frame.width - w) / 2,
            y: screen.visibleFrame.maxY - h,
            width: w, height: h
        )
        // 从屏幕上方外开始，掉下来
        let startFrame = NSRect(x: finalFrame.minX, y: screen.frame.maxY + 8, width: w, height: h)
        let window = NSWindow(
            contentRect: startFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hidesOnDeactivate = false
        let view = WarningBannerView(onTap: { [weak self] in
            self?.dismissed = true
            self?.hide()
        })
            .environmentObject(timer)
        window.contentView = NSHostingView(rootView: view)
        // borderless 窗口默认不可 key，不会抢焦点
        window.orderFrontRegardless()
        self.window = window
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            window.animator().setFrame(finalFrame, display: true)
        }
    }

    private func hide() {
        guard showing else { return }
        showing = false
        guard let window else { return }
        self.window = nil
        // 缩上去后关闭
        var f = window.frame
        f.origin.y = (window.screen?.frame.maxY ?? f.maxY) + 8
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().setFrame(f, display: true)
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}

/// 预警徽章 UI（复刻原版）：绿色圆形徽章，用细线悬挂在屏幕上方，
/// 显示 iRelax 和剩余秒数，点一下缩上去。
/// 原版：圆形有上下渐变、整体 90% 透明度。
struct WarningBannerView: View {
    @EnvironmentObject var timer: FocusTimer
    var onTap: () -> Void = {}

    // 渐变以截图像素采样底色 #76FE73 为中值：上浅下深
    private let circleTop = Color(red: 150 / 255, green: 255 / 255, blue: 148 / 255)
    private let circleBottom = Color(red: 105 / 255, green: 242 / 255, blue: 104 / 255)
    private let lineGreen = Color(red: 202 / 255, green: 249 / 255, blue: 189 / 255)   // #CAF9BD
    private let textGreen = Color(red: 57 / 255, green: 121 / 255, blue: 57 / 255)     // #397939

    var body: some View {
        VStack(spacing: 0) {
            // 悬挂的细线
            Rectangle()
                .fill(lineGreen)
                .frame(width: 2, height: 38)
            // 圆形徽标：四周留内边距，避免抗锯齿边缘被窗口裁掉发毛；
            // 加一点柔光阴影让边缘过渡更自然
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [circleTop, circleBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 1)
                VStack(spacing: 2) {
                    Text("iRelax")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(textGreen)
                    Text("\(timer.remaining)")
                        .font(.system(size: 33, weight: .bold, design: .rounded))
                        .foregroundStyle(textGreen)
                        .monospacedDigit()
                }
            }
            .frame(width: 82, height: 82)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
        .opacity(0.9)
        .onTapGesture { onTap() }
    }
}
