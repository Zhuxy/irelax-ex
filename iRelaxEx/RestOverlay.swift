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
        switch self {
        case .rain:  return .blue
        case .sea:   return .teal
        case .wind:  return .green
        case .white: return .orange
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
        for screen in NSScreen.screens {
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
            let view = RestOverlayView()
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {} // 吞掉点击，防止穿透

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                    Text("iRelaxEx")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                // 黄色倒计时牌（复刻原版）
                Text(timer.formatted)
                    .font(.system(size: 54, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
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
            .background(Color(white: 0.28).opacity(0.92))
            .cornerRadius(26)
        }
    }
}
