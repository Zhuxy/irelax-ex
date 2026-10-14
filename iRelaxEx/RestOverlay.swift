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
        hide()
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
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
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
            Color.black.opacity(0.55)
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
