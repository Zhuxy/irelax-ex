import AVFoundation

/// 程序化环境音引擎。clean-room 重实现。
///
/// 原版用 6 个 mp3 循环播放（`audio_rain` / `audio_bird` / `audio_sea` /
/// `audio_mou` / `audio_pre10s` / `audio_startWork`），那些是有版权的录音，
/// 这里不用。这里用 AVAudioEngine + AVAudioSourceNode 实时合成噪声，
/// 不需要任何音频文件，CPU 占用也极低（渲染在音频线程按块进行）。
final class NoiseEngine: ObservableObject {
    enum Sound: String, CaseIterable, Identifiable {
        case rain, sea, wind, white, pink, brown

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rain:  return "雨声"
            case .sea:   return "海浪"
            case .wind:  return "风声"
            case .white: return "白噪音"
            case .pink:  return "粉噪音"
            case .brown: return "棕噪音"
            }
        }

        var subtitle: String {
            switch self {
            case .rain:  return "过滤白噪音 + 雨滴起伏"
            case .sea:   return "低频涌动，约 8 秒一个浪"
            case .wind:  return "缓慢呼吸感的气流"
            case .white: return "全频段均匀噪声"
            case .pink:  return "低频稍强的自然噪声"
            case .brown: return "深沉的低频轰鸣"
            }
        }
    }

    @Published private(set) var activeSound: Sound?
    @Published var volume: Float = 0.5 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    // 提示音（chime）状态。播放用 AVAudioSourceNode 拉取渲染，
    // 刻意不用 AVAudioPlayerNode——player 在睡眠/唤醒边界（音频 IO
    // 周期中断或尚未恢复）会抛 "player did not see an IO cycle"
    // ObjC 异常直接 SIGABRT 杀掉进程，Swift catch 不了 ObjC 异常，
    // 这正是"合盖一夜之后程序消失"的原因。
    private var chimeNode: AVAudioSourceNode?
    private var chimeData: [Float] = [] // 预合成波形，首次 chime 时生成，之后只读
    private var chimePos = 0 // 渲染线程推进，主线程复位，chimeLock 保护
    private let chimeLock = NSLock()
    private var kind: Sound = .rain

    // 伪随机数（xorshift64*，比 Float.random 快一个数量级，音频线程用）
    private var rng: UInt64 = 0x9E3779B97F4A7C15
    // 粉噪音滤波器状态（Paul Kellet 算法）
    private var pink = [Double](repeating: 0, count: 7)
    private var brownLast = 0.0
    private var lowpass = 0.0
    private var time = 0.0
    private let sampleRate = 44100.0

    @inline(__always)
    private func nextWhite() -> Double {
        rng ^= rng >> 12
        rng ^= rng << 25
        rng ^= rng >> 27
        // [0, 1) → [-1, 1)
        return Double(rng &* 0x2545F4914F6CDD1D >> 11)
            * (1.0 / 9007199254740992.0) * 2.0 - 1.0
    }

    @inline(__always)
    private func renderSample() -> Double {
        let w = nextWhite()
        time += 1.0 / sampleRate
        switch kind {
        case .white:
            return w * 0.5

        case .pink:
            // Paul Kellet pink noise
            pink[0] = 0.99886 * pink[0] + w * 0.0555179
            pink[1] = 0.99332 * pink[1] + w * 0.0750759
            pink[2] = 0.96900 * pink[2] + w * 0.1538520
            pink[3] = 0.86650 * pink[3] + w * 0.3104856
            pink[4] = 0.55000 * pink[4] + w * 0.5329522
            pink[5] = -0.7616 * pink[5] - w * 0.0168980
            let out = pink[0] + pink[1] + pink[2] + pink[3] + pink[4] + pink[5] + pink[6] + w * 0.5362
            pink[6] = w * 0.115926
            return out * 0.11

        case .brown:
            brownLast = (brownLast + 0.02 * w) / 1.02
            return brownLast * 3.5

        case .rain:
            // 白噪音过一阶低通，叠加雨滴感的慢速幅度起伏
            lowpass += 0.28 * (w - lowpass)
            let flutter = 0.72
                + 0.20 * sin(2 * .pi * 0.6 * time)
                + 0.08 * sin(2 * .pi * 2.7 * time + 1.3)
            return lowpass * 2.4 * flutter

        case .sea:
            // 棕噪音 + 约 0.12Hz 的涌浪包络
            brownLast = (brownLast + 0.02 * w) / 1.02
            let swell = 0.55 + 0.45 * sin(2 * .pi * 0.12 * time)
            return brownLast * 3.5 * swell * 1.4

        case .wind:
            // 粉噪音 + 呼吸感包络
            pink[0] = 0.99886 * pink[0] + w * 0.0555179
            pink[1] = 0.99332 * pink[1] + w * 0.0750759
            pink[2] = 0.96900 * pink[2] + w * 0.1538520
            pink[3] = 0.86650 * pink[3] + w * 0.3104856
            pink[4] = 0.55000 * pink[4] + w * 0.5329522
            pink[5] = -0.7616 * pink[5] - w * 0.0168980
            let out = pink[0] + pink[1] + pink[2] + pink[3] + pink[4] + pink[5] + pink[6] + w * 0.5362
            pink[6] = w * 0.115926
            let breath = 0.45 + 0.55 * (0.5 + 0.5 * sin(2 * .pi * 0.09 * time + 0.7))
            return out * 0.11 * breath * 1.6
        }
    }

    private func resetState() {
        pink = [Double](repeating: 0, count: 7)
        brownLast = 0
        lowpass = 0
        time = 0
        rng = 0x9E3779B97F4A7C15
    }

    // MARK: - 控制

    /// 播放指定环境音；重复点当前音则保持不变
    func play(_ sound: Sound) {
        guard activeSound != sound else { return }
        stopEngine()
        kind = sound
        resetState()
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false)!
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                for i in 0 ..< Int(frameCount) {
                    ptr[i] = Float(self.renderSample())
                }
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        do {
            try engine.start()
            activeSound = sound
        } catch {
            stopEngine()
        }
    }

    func toggle(_ sound: Sound) {
        if activeSound == sound { stop() } else { play(sound) }
    }

    func stop() {
        stopEngine()
        activeSound = nil
    }

    private func stopEngine() {
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
    }

    /// 系统即将睡眠：干净停掉引擎（保留节点连接），
    /// 避免 IO 周期中断后残留的播放状态在唤醒时出问题。
    func prepareForSleep() {
        if engine.isRunning { engine.stop() }
    }

    /// 系统唤醒后恢复被睡眠打断的环境音。
    func resumeAfterWake() {
        guard sourceNode != nil, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            // 音频设备暂不可用：清掉状态，等用户手动再选
            stopEngine()
            activeSound = nil
        }
    }

    /// 预合成两声正弦"叮咚"波形，不依赖任何音频文件
    private static func synthesizeChime(sampleRate: Double) -> [Float] {
        let length = Int(sampleRate * 0.8)
        var data = [Float](repeating: 0, count: length)
        for i in 0 ..< length {
            let t = Double(i) / sampleRate
            let freq = t < 0.35 ? 880.0 : 659.0
            let env = exp(-3.0 * (t.truncatingRemainder(dividingBy: 0.4)) / 0.4)
            data[i] = Float(sin(2 * .pi * freq * t) * 0.35 * env)
        }
        return data
    }

    /// 阶段结束提示音：两声正弦"叮咚"，不依赖任何音频文件
    func chime() {
        // 用 AVAudioSourceNode 拉取渲染（与环境音同一条安全路径）。
        // 若引擎起不来（如睡眠切换中音频设备不可用）就不播，宁可丢提示音也不硬来。
        if chimeData.isEmpty { chimeData = Self.synthesizeChime(sampleRate: sampleRate) }
        chimeLock.lock()
        chimePos = 0
        chimeLock.unlock()

        if chimeNode == nil {
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
            let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
                guard let self else { return noErr }
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                self.chimeLock.lock()
                defer { self.chimeLock.unlock() }
                for buffer in buffers {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    for i in 0 ..< Int(frameCount) {
                        if self.chimePos < self.chimeData.count {
                            ptr[i] = self.chimeData[self.chimePos]
                            self.chimePos += 1
                        } else {
                            ptr[i] = 0
                        }
                    }
                }
                return noErr
            }
            chimeNode = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        // 播完后若没有环境音在跑，把引擎停掉，不常驻耗电
        let duration = TimeInterval(chimeData.count) / sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) { [weak self] in
            guard let self else { return }
            self.chimeLock.lock()
            let finished = self.chimePos >= self.chimeData.count
            self.chimeLock.unlock()
            if finished && self.sourceNode == nil && self.engine.isRunning {
                self.engine.stop()
            }
        }
    }
}
