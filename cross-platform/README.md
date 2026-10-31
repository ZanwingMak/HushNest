# 耳憩 HushNest · Web / Android / macOS / Windows

独立的多端应用，开发分支为 `codex/web-android-windows`。桌面客户端使用 [MyGo 0.7.3](https://github.com/egoist/mygo)：Go 后台、macOS WKWebView / Windows WebView2 和现有 React 界面。原生 iOS 工程及官网保持原样。

## 功能

秒级倒计时（1 秒至 12 小时）、本地指定时间、可保存预设、暂停恢复、稍后提醒、15 秒渐强闹铃、最多 3 分钟或持续响铃；复用原应用 8 种助眠音、14 种闹铃、图标与六种语言。支持本地媒体导入（每个 200 MB / 2 小时、最多 20 个）、最多 365 条记录、四主题、明暗外观、大字体及减少动态效果。全部功能免费，无账号、后端、麦克风、广告或分析服务。

## 桌面架构

MyGo 的 Go 后台拥有计时、会话持久化、音量渐强和播放调度；WebView 仅显示状态和发送命令。窗口最小化、隐藏到托盘或页面重新加载不会改变原生截止时间。后台服务以绝对时间计时，暂停和中断不计入休息记录；进程关闭后手动恢复。休息期间通过 MyGo Power 保持电脑唤醒，关闭窗口收至托盘，退出需确认。

- Windows：MyGo + 系统 WebView2；沿用自包含 .NET 8 / NAudio 的原生 WASAPI 音频组件，将声音固定到具体耳机端点。设备断开或默认输出变化会停止声音，不回退到系统默认扬声器。
- macOS 12+：MyGo + 系统 WKWebView；Swift 原生音频组件通过 CoreAudio 获取输出，通过 AudioQueue 固定设备 UID，以 AVAssetReader 流式解码。支持系统暴露插孔状态的有线耳机；蓝牙或 USB 无法确定是否为耳机时需用户确认。内置扬声器、AirPlay、聚合和未知输出不会自动获准。
- 原生音频组件仅通过 stdin/stdout 与 Go 主程序通信，不提供网络端口。WebView 使用 MyGo 的类型化 Go ↔ TypeScript IPC，没有 Node.js 或任意文件/进程接口。导入媒体按 UUID 分块写入应用私有目录，校验总大小与偏移；闹铃最多循环自定义音轨的前 60 秒。

## 各平台边界

| 能力 | Web / PWA | Android 9+ | macOS / Windows MyGo |
| --- | --- | --- | --- |
| 耳机 | 不判断、不要求确认，声音跟随系统当前输出 | 原生耳机路由校验；蓝牙需确认是耳机 | 原生输出检测和固定设备播放；macOS 模糊类型需确认 |
| 设备变化 | 不据此中断计时，可能转到扬声器 | 停止声音、保留截止时间 | 原生音频组件停止，Go 会话进入中断状态 |
| 后台 | 需页面打开、设备唤醒；锁屏和后台提醒不可靠 | 原生前台服务、静默常驻通知与 wake lock | Go 计时与原生播放，独立于 WebView 的计时器 |
| 媒体 | IndexedDB 本机保存并播放音轨 | 私有目录，提取支持的视频音轨 | IndexedDB 保存原文件，分块缓存到私有目录供原生解码 |
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

Windows 构建需要 Windows x64、.NET 8 SDK 和 WebView2 Runtime：

```sh
npm run windows:build
npm run windows:dev
```

输出 `release/mygo/windows-amd64/HushNest.exe`、原生音频组件与资源目录，以及 `hushnest-setup-0.1.0-amd64.exe` 安装器。便携使用时保留整个目录；主程序不是包含所有录音与音频组件的单文件应用。未配置代码签名。

macOS 构建需要 macOS 与 Xcode Command Line Tools：

```sh
npm run macos:build
npm run macos:dev
```

输出 `release/mygo/darwin-universal/` 中的通用 `.app` / `.dmg`，同时支持 Apple Silicon 与 Intel。当前为 ad hoc 签名测试包，尚未使用 Developer ID 签名或公证。Windows 可交叉编译检查 Go 主程序，但 Swift 音频组件、应用签名和磁盘映像在 macOS CI 中验证。

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

Go 测试覆盖没有前端调用时的到点响铃、三分钟期限、持续响铃、断连、暂停累计、稍后提醒、进程恢复、记录上限、媒体分块及路径校验。浏览器测试覆盖 Web 无耳机门槛、原生端耳机保护、macOS 模糊设备确认、记录、媒体导入、主题语言和多窗口互斥。桌面 smoke 实际运行 MyGo / WebView，核验 IPC、资源、平台、拒绝非法输入和无 Node.js；自动化不播放声音。

CI 分别构建 Web、Android、Windows MyGo 和 macOS MyGo 并上传产物，不自动上架或发布网站。原 iOS 工作流不变。实体安卓 / Mac / Windows 耳机的热插拔、音量、来电和厂商策略仍需硬件验证。

许可证及录音署名见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。