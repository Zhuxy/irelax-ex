# iRelaxEx

iRelax（Mac App Store 番茄钟 + 白噪音菜单栏应用，v1.6，2022 年构建）
的 clean-room 重实现。起因：原版在新 macOS（27）上 CPU 占用一直很高，
疑似其 `SwiftTimer` 高频重复 timer 在新系统调度行为变化所致
（分析见 [docs/RE-NOTES.md](docs/RE-NOTES.md)）。

本仓库所有代码为原创重写（MIT），**没有**复制原版二进制、界面资源或音频文件，
仅复刻行为与功能，供个人学习与自用。

## 功能

- 🍅 菜单栏番茄钟：工作 / 休息两阶段倒计时，菜单栏实时显示剩余时间
- 🖥️ 主弹窗复刻原版布局：绿"开始工作" / 黄"开始休息"大按钮、时间设置区、
  2x2 开关项（不可跳过 / 撰写评论 / 开机启动 / 退出程序）
- 🎚️ 时间设置：原版用旋钮，这里换成滑杆（工作 5–120 分钟、休息 1–60 分钟）
- ☕️ 休息全屏遮罩：进入休息自动弹出半透明遮罩（多显示器全覆盖），
  中央卡片含咖啡图标、黄色大倒计时、环境音快捷图标、"跳过"按钮；
  休息结束或跳过后自动关闭
- ⏸️ 暂停 / 继续 / 结束 / 跳过休息（可设"休息不可跳过"，对标原版 NotSkip）
- 🔊 程序化环境音：雨声 / 海浪 / 风声 / 白噪音 / 粉噪音 / 棕噪音，
  用 `AVAudioEngine` 实时合成，零音频文件，音量可调
- 🔔 阶段结束通知 + 提示音（正弦合成"叮咚"，无音频文件）
- 🚀 开机启动（`SMAppService`，替代原版内嵌的 iRelaxHelper 桩应用）
- 设置经 `UserDefaults` 持久化（对标原版）

## 与原版的关键差异（故意的）

| 原版 | iRelaxEx |
|---|---|
| `SwiftTimer` 高频重复 timer 刷 UI | 1Hz `Timer` + `.common` RunLoop mode，空闲零唤醒 |
| 6 个 mp3 录音循环播放 | 程序化合成，无版权音频文件 |
| 内嵌 `iRelaxHelper.app` 做开机启动 | `SMAppService.mainApp`（macOS 13+ 现代 API）|
| AppKit + Storyboard + SnapKit | SwiftUI `MenuBarExtra` |
| 最低支持 macOS 10.12 | 最低 macOS 13（Ventura），目标 macOS 27 |

## 构建

1. 在 Mac 上用 Xcode 15+ 打开 `iRelaxEx.xcodeproj`
2. 在 target 的 Signing & Capabilities 里选你自己的 Team，
   Signing Certificate 选 **Development**（长久自用，身份稳定）
   （Bundle ID 默认 `org.btinws.app.irelax-ex`，可改）
3. ⌘R 运行。应用只出现在菜单栏（无 Dock 图标），点 ⏱ 图标弹出主界面
4. 打包长期用：Product → Archive，把 `.app` 放到 `/Applications` 后再开"开机启动"

> 注意：本工程在这台 Linux VM 上无法编译验证，首次在 Mac 上构建时
> 如遇小问题（签名、API 拼写）直接贴报错给我修。

## 先验证 CPU 猜想（可选，1 分钟）

如果想先确认原版到底是不是 timer 问题再换：
在 Mac 上 `活动监视器 → iRelax → 取样进程`（或
`sudo spindump -target <pid> -timeout 10`），看最热的栈是否落在
timer 回调 / UI 刷新路径上。

## 逆向方法

- `rea decode-interface-builder`（rea 6.4.0）：静态解出 storyboard/nib 的
  视图层级与控件，确认了主界面结构（大"开始工作"按钮、开关、滑杆等）
- `strings` / 符号表 / `Info.plist` / 资源清单：确认第三方库、
  UserDefaults 键、本地化功能点
- `rea analyze` 原生反编译在本机不可用（无 Ghidra/Hopper/IDA provider），
  如需逐函数确认 timer 间隔常量，可在有 Ghidra 的机器上补跑
