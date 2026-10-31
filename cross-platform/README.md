# 耳憩 HushNest · Web / Android / macOS / Windows

独立的多端应用，开发分支为 `codex/web-android-windows`。桌面客户端 0.3.1 使用 [MyGo 0.7.3](https://github.com/egoist/mygo) 的原生 `ui` 包：Go 界面、Go 后台和系统音频组件。桌面窗口没有 WebView，不加载 React、HTML 或 JavaScript，也不要求安装 WebView2。Web / Android 保留现有前端，原生 iOS 工程及官网保持原样。

0.3.0 重做桌面视觉：侧边导航、原生绘制的圆环计时、紧凑的耳机/时长/声音面板、自然声音卡片及足迹统计。窄窗口自动改为顶部导航和纵向布局，较矮的窗口缩小计时圆环，保留首屏开始按钮。沿用四种主题、深浅外观、六种语言和原有本机数据。

## 功能

秒级倒计时（1 秒至 12 小时）、本地指定时间、可保存预设、暂停恢复、稍后提醒、15 秒渐强闹铃、最多 3 分钟或持续响铃；复用原应用 8 种助眠音、14 种闹铃、图标与六种语言。支持本地媒体导入（每个 200 MB / 2 小时、最多 20 个）、最多 365 条记录、四主题、明暗外观、大字体及减少动态效果。全部功能免费，无账号、后端、麦克风、广告或分析服务。

## 桌面架构

MyGo `ui` 通过 GPU 绘制原生窗口，所有界面和事件均由 Go 实现；它使用自绘控件，与 SwiftUI / WinUI 的系统控件不同。Go 后台拥有计时、会话持久化、音量渐强和播放调度。窗口最小化或隐藏到托盘不会改变截止时间。后台服务以绝对时间计时，暂停和中断不计入休息记录；进程关闭后手动恢复。休息期间通过 MyGo Power 保持电脑唤醒，关闭窗口收至托盘，退出需确认。

- Windows：MyGo 原生界面；沿用自包含 .NET 8 / NAudio 的 WASAPI 音频组件，将声音固定到具体耳机端点。设备断开或默认输出变化会停止声音，不回退到系统默认扬声器。
- macOS 12+：MyGo 原生界面；Swift 音频组件通过 CoreAudio 获取输出，通过 AudioQueue 固定设备 UID，以 AVAssetReader 流式解码。支持系统暴露插孔状态的有线耳机；无法自动确定类型的当前输出可经二次确认放行。内置扬声器、AirPlay、聚合和未知输出不会自动获准。
- 原生音频组件仅通过 stdin/stdout 与 Go 主程序通信，不提供网络端口。界面直接调用 Go 服务，没有网页或 JavaScript IPC。文件通过系统选择器交给 Go，流式复制到私有 UUID 文件；原生解码器检查音轨和时长，失败会清理文件，闹铃最多循环自定义音轨的前 60 秒。主题、语言、预设和媒体目录使用本机 JSON 保存。
- 沿用先前桌面包的计时、记录及媒体缓存；旧缓存没有原生媒体目录时会重新检查音轨，以通用名称显示，原文件不变。原 WebView/IndexedDB 中独有的外观设置不会迁移。

桌面 0.3.1：自动检测未识别到耳机，但系统有可用输出时，点击开始、恢复或试听会弹出确认框，展示输出设备名称。选择“我已确认连接耳机，继续”后使用该输出；取消则不播放。也可先在耳机面板手动确认。Go 服务和音频组件均校验确认时的设备标识，确认过程中发生切换不会放行。手动确认只在当前进程、当前输出有效，切换、设备消失或重启后重新确认。若系统根本没有输出设备则不能放行。声卡把 3.5mm 插孔始终报告为同一“扬声器”端点时，软件可能无法察觉物理插拔，因此用户需确认实际声音确实来自耳机。

## 各平台边界

| 能力 | Web / PWA | Android 9+ | macOS / Windows MyGo |
| --- | --- | --- | --- |
| 耳机 | 不判断、不要求确认，声音跟随系统当前输出 | 原生耳机路由校验；蓝牙需确认是耳机 | 原生输出检测和固定设备播放；未识别时可二次确认当前输出后放行 |
| 设备变化 | 不据此中断计时，可能转到扬声器 | 停止声音、保留截止时间 | 原生音频组件停止，Go 会话进入中断状态 |
| 后台 | 需页面打开、设备唤醒；锁屏和后台提醒不可靠 | 原生前台服务、静默常驻通知与 wake lock | Go 计时与原生播放，无 WebView |
| 媒体 | IndexedDB 本机保存并播放音轨 | 私有目录，提取支持的视频音轨 | 系统文件选择器，Go 私有目录，原生解码与时长检查 |
| 离线 | 缓存界面及已用过的内置音频 | 内置音频随包分发 | 内置音频随包分发 |
| 震动 | 取决于浏览器支持 | 支持 | 不提供 |

Web 无耳机判断，不保证阻止外放。原生端仍需实体耳机验证锁屏、蓝牙、来电、驱动及电池限制；不要将它作为重要事项的唯一提醒。AirPods 切换、StoreKit 赞助和相册专用选择器保留在原 iOS 应用，本目录使用系统文件选择器，无付费功能。

## 运行及构建

需要 Node.js 24；桌面构建另需 Go 1.27.3。依赖由 `package-lock.json`、`go.mod` 和 `go.sum` 固定。从本目录执行：

```sh
npm ci
npm run dev
npm run build
npm run preview
```

Web 开发地址 `http://127.0.0.1:5173/`，静态产物为 `dist/`，可部署到 HTTPS 子路径。通过 HTTP / HTTPS 访问，不要双击 index.html。服务工作线程只为 Web 注册，桌面及安卓不使用它。

Windows 构建需要 Windows x64 和 .NET 8 SDK；不需要 WebView2 Runtime：

```sh
npm run windows:build
npm run windows:dev
```

输出 `release/mygo-native/windows-amd64/HushNest.exe`、原生音频组件与资源目录，以及 `hushnest-setup-0.3.1-amd64.exe` 安装器。便携使用时保留整个目录；主程序不是包含所有录音与音频组件的单文件应用。未配置代码签名。桌面构建不执行 Vite / React 构建，不打包 `dist/`。

安装器默认为当前用户安装，目录为 `%LOCALAPPDATA%\Programs\HushNest`，不自动申请管理员权限。选择 `C:\Program Files`、`D:\Program Files` 等受保护目录时，普通权限可能出现 `Error opening file for writing`，即使报错指向许可证文件。此时中止安装，重新运行并保留默认目录，或选择自己有写入权限的目录；确实需要安装到受保护目录时，可手动以管理员身份运行安装器。不要用“忽略”跳过安装文件。

macOS 构建需要 macOS 与 Xcode Command Line Tools：

```sh
npm run macos:build
npm run macos:dev
```

输出 `release/mygo-native/darwin-universal/` 中的通用 `.app` / `.dmg`，同时支持 Apple Silicon 与 Intel。当前为 ad hoc 签名测试包，尚未使用 Developer ID 签名或公证。Windows 可交叉编译检查 Go 主程序，但 Swift 音频组件、应用签名和磁盘映像在 macOS CI 中验证。

可选环境变量 `HUSHNEST_GO` / `HUSHNEST_DOTNET` 指定 go / dotnet 的完整路径。脚本不需要 Bun；运行时不需要 Node.js、Go SDK 或 .NET SDK。

Android 需要 JDK 21 与 Android SDK 36，设置 `JAVA_HOME`、`ANDROID_HOME`：

```sh
npm run android:build
```

输出 `android/app/build/outputs/apk/debug/app-debug.apk`，为调试签名包。Google Play 上架需要自己的签名，并申报审核 `specialUse` 前台服务。Android 禁用自动备份和设备数据迁移，不请求麦克风或后台精确闹钟权限。

## 验证

```sh
npm test
npx playwright install chromium
npm run test:web
npm run test:desktop
go vet ./desktop/...
node tests/offline-smoke.mjs
node tests/desktop-smoke.mjs
```

Go 测试覆盖独立于界面的计时状态机，以及原生界面的开始、暂停、恢复、稍后提醒、断连保护、设备确认、设置、文件导入/删除、大小限制和失败回滚。原生视图在常规 / 最小窗口尺寸及深色外观下运行。浏览器测试继续覆盖 Web 无耳机门槛等现有行为。桌面 smoke 实际运行 MyGo 原生窗口，要求 `window.Page() == nil`，截图四个页面，检查安装包没有 HTML/JS/CSS 资源，并用真实解码器无声导入、验证和删除音轨。截图和报告在 `release/mygo-native/qa/`；自动化不播放声音。

CI 分别构建 Web、Android、Windows MyGo 和 macOS MyGo 并上传产物，不自动上架或发布网站。原 iOS 工作流不变。实体安卓 / Mac / Windows 耳机的热插拔、音量、来电和厂商策略仍需硬件验证。

Windows CI 还会运行 `node tests/windows-installer.mjs`：在隔离 runner 上实际安装并覆盖安装到含空格和中文的可写目录，核对程序、许可证及音频资源，最后运行安装后的原生应用测试。此检查会写入当前用户的应用注册信息及开始菜单，因此仅在隔离 CI 中执行。

许可证及录音署名见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
