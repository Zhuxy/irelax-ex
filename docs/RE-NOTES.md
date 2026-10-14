# iRelax 逆向笔记（静态分析）

分析对象：`iRelax_1_ymtq.zip`（用户自购的 Mac App Store 版本）
分析日期：2026-10-14　分析环境：Linux VM（无法运行 macOS 二进制，仅静态分析）

## 文件指纹

| 项 | 值 |
|---|---|
| zip SHA-256 | `cdb6b89bee02e06f0139451f5f3031d57c220e22e9fae3e78c62368192556f8d` |
| 主二进制 SHA-256 | `a19585f660d6ce470c2eba2a91d79a5c4771cbba8c99620fdb283ab84255b278` |
| Bundle ID | `com.devlook.iRelax` |
| 版本 | 1.6 (build 16)，© 2017 devlook |
| 架构 | Universal：x86_64 + arm64，主二进制约 571 KB |
| 构建链 | Xcode 13.3，macOS 12.3 SDK，最低支持 10.12，构建于 2022-04 |
| 分发 | 含 `_MASReceipt/receipt`，为 App Store 正式包 |

## 这是个什么应用

- `LSUIElement = true`：纯菜单栏应用，无 Dock 图标。
- 类别 `public.app-category.healthcare-fitness`。
- 从符号与资源看，这是一个**番茄钟 + 白噪音**应用：
  - 视图类：`TimerView`、`AudioView`、`MainView`、`MenuViewController`、
    `MenuHeaderView`、`RemindView`、`SystemView`、`TimeSettingView`、`VersionView`
    （源码路径残留：`/Users/zq/Code/Health/Health/View/*.swift`）。
  - 本地化字符串键：`Work` / `Relax` / `Min` / `Mins` / `Startup`(Launch at login) /
    `NotSkip`(Not skip) / `WriteReview` / `exit`(Quit)。
  - 音频资源：`audio_rain.mp3`、`audio_bird.mp3`、`audio_sea.mp3`、
    `audio_mou.mp3`、`audio_pre10s.mp3`、`audio_startWork.mp3`。
  - 界面：`NSStatusItem` + `NSPopover`；主界面含一个 244×59 的大按钮
    （标题"开始工作"）、一个 recessed 按钮、一个 `NSSwitch`、一个 `NSSlider`、
    若干 `NSTextField`、一个带滚动条的 `NSTextView`。
  - 持久化：`NSUserDefaults`（`boolForKey` / `integerForKey` / `setInteger:forKey:` 等）。
  - 开机启动：内嵌 `iRelaxHelper.app`（`com.devlook.iRelaxHelper`，
    `LSBackgroundOnly`），是旧式 SMLoginItem 启动桩。

## 第三方库

`SwiftTimer`（重复定时器）、`SnapKit`（Auto Layout）、`Hue`（颜色），
另附 Swift 标准库 dylib。

## CPU 占用高的可能根因（假设，需在 Mac 上验证）

1. **SwiftTimer 高频重复 timer**：符号表显示计时器用的是
   `SwiftTimer.repeaticTimer(interval:leeway:queue:handler:)`。
   若 UI 刷新 timer 设得很密（例如每 0.05–0.1s 刷新倒计时/进度），
   在新系统上会被更积极地调度，菜单栏常驻即常烧 CPU。
2. 2022 年构建的老二进制 + 新 macOS 的 timer 合并（timer coalescing）
   / RunLoop 行为变化，可能让原本"恰好能用"的忙等式刷新变成持续唤醒。
3. 音频用 `NSSound`/`AVAudioPlayer` 循环播放 mp3 本身不该高 CPU，
   除非播放 completion 回调里又起了高频 timer。

验证方法（在 Mac 上，1 分钟即可定位）：
`活动监视器 → iRelax → 取样进程`，或
`sudo spindump -target <pid> -out /tmp/irelax.spindump -timeout 10`，
看最热的栈是不是落在 timer 回调 / UI 刷新路径。

## rea 工具链的使用情况

- `rea decode-interface-builder`（rea 6.4.0，经 npx 运行）：**成功**，
  静态解出 storyboard/nib 的视图层级、控件类型与本地化字符串，
  上面的 UI 结构结论即出自这份证据。
- `rea analyze`（原生反编译）：**不可用**——本 VM 没有 Ghidra / Hopper / IDA
  provider（`rea doctor` 可复现）。如需逐函数反编译 TimerView 的 timer
  间隔常量，需在有 Ghidra 的机器上跑
  `rea analyze --provider ghidra <thinned-arm64-slice>`。

## 重实现口径（clean-room）

- 只复刻**行为与功能**（菜单栏番茄钟 + 环境音 + 开机启动 + 休息提醒），
  代码全部重写，不复制原二进制、不复制原音频资源。
- 原版 6 个 mp3 环境音**未提取、未使用**（版权归原作者）。
  重实现用 `AVAudioEngine` 程序化合成白/粉/棕噪音与雨/海/风近似音，
  无需任何音频文件；用户也可自行指定音频目录播放自己的文件。
- 本仓库所有代码为 MIT 许可的原创实现，仅供个人学习与自用。
