# 耳憩 HushNest · Web / Android / Windows

本目录是独立的多端应用，开发分支为 `codex/web-android-windows`。原生 iOS 工程、Swift 代码、音频源文件、官网及原有发布工作流保持原样；没有生成或替换 iOS 平台。

## 已实现

- 1 秒至 12 小时倒计时、下一次本地指定时间（需在 12 小时内）、15 / 30 / 45 / 60 分钟预设、秒级自定义预设及删除。
- 暂停、恢复、结束、1–30 分钟稍后提醒；以绝对截止时间计时，暂停及中断期间不累计休息时间。
- 原应用 8 种助眠音、无助眠音、14 种唤醒铃声；15 秒渐强唤醒、最多 3 分钟响铃或持续重复；2 秒低音量试听、实时音量调整。
- 本机音频/视频导入、选择为助眠音或闹铃、删除；每个文件不超过 200 MB / 2 小时，最多 20 个。自定义闹铃循环前 60 秒。
- 最多 365 条本机休息记录、统计和清空；设置与音轨本地持久化。无需账号、后端、麦克风或分析服务。
- 原应用六语言文案 + 六语言平台说明；四主题、浅/深/系统外观、大字体、键盘焦点、减少动态效果、移动端布局。

## 各平台的实现与边界

| 能力 | Web / PWA | Android 9+ | Windows 10/11 x64 |
| --- | --- | --- | --- |
| 界面 | React + TypeScript | 同一界面，Capacitor 原生壳 | 同一界面，Electron 桌面壳 |
| 音频 | 浏览器媒体播放 | 原生 MediaPlayer；确认实际路由后放开音量 | .NET + NAudio，绑定 WASAPI 具体端点 |
| 耳机 | 不判断、不要求确认；计时与试听可直接开始，声音跟随系统当前输出 | 有线/USB 耳机；蓝牙需确认设备是耳机。多个可选输出时拒绝猜测 | 默认多媒体输出必须被 Windows 标记为 Headphones / Headset；无法识别的 USB DAC / Speakers 端点会被拒绝 |
| 断连 | 不监听设备变化来中断计时或声音；耳机断开后可能转为扬声器播放 | noisy 广播、设备回调和实际播放路由校验；停止声音、保留截止时间 | 输出固定端点，无默认扬声器回退；每 100 ms 复查设备及默认输出 |
| 后台 | 需保持页面打开与设备唤醒；不能保证锁屏或后台闹铃 | 原生前台服务拥有会话、静默常驻通知和有时限的 wake lock | 禁止 Chromium 后台节流，休息时阻止自动睡眠；关闭窗口收至托盘，明确退出才结束程序 |
| 恢复 | 进程关闭后进入中断状态，人工确认恢复 | WebView 重载不影响服务；进程被杀后人工恢复。暂时音频焦点中断可在系统允许后恢复 | 进程关闭/系统睡眠后人工确认恢复 |
| 自定义媒体 | 原文件保存在 IndexedDB，播放其中音轨，不导出独立音频文件 | 应用私有目录；支持的视频提取音轨，依赖系统支持的编码 | 原文件保存在 IndexedDB，播放时缓存至应用私有目录，Media Foundation 解码音轨 |
| 离线 | 首次加载缓存界面；用过的内置音频缓存后可离线播放 | 所有内置音频随包分发 | 所有内置音频随包分发 |
| 震动 | 取决于浏览器是否支持 Vibration API | 支持，有耳机且响铃时触发 | 不提供 |

Web 需保持页面打开与设备唤醒，锁屏或后台限制可能使提醒失效。Web 不进行耳机判断，声音跟随系统当前输出，可能通过扬声器播放。原生端需真机确认耳机、来电、厂商电池策略与驱动行为；开始休息后切换设备会中断声音，需要检查后手动继续。不要作为重要事项的唯一提醒。

StoreKit 赞助、AirPods 切换和相册专用选择器为 iOS 功能；这些端没有移植 Apple 支付，也没有添加任何付费功能。导入使用系统文件选择器。

## 本地运行和构建

需要 Node.js 24。依赖由 `package-lock.json` 固定；从仓库根目录进入本目录：

```sh
npm ci
npm run dev
```

Web 开发地址为 `http://127.0.0.1:5173/`。静态产物：

```sh
npm run build
npm run preview
```

`dist/` 可部署到 HTTPS 静态托管或任意子路径。请通过 HTTP / HTTPS 访问，不要直接双击 index.html。服务工作线程不预下载全部音频；首次使用某个内置音频时会缓存完整文件。

Android 需要 JDK 21、Android SDK 36 和对应 build tools；设置 `JAVA_HOME`、`ANDROID_HOME`，然后：

```sh
npm run android:build
```

输出 `android/app/build/outputs/apk/debug/app-debug.apk`，为可侧载的调试签名 APK。Google Play 上架前需要自己的发布签名，并申报/审核 `specialUse` 前台服务用途；不要把调试 APK 当作已签名上架版本。应用禁用 Android 自动备份，且不申请麦克风、相册全量读取或后台精确闹钟权限。

Windows 需要 Windows x64 与 .NET 8 SDK（只在构建机需要）。可选设置 `HUSHNEST_DOTNET` 为 dotnet.exe 的完整路径：

```sh
npm run windows:dev
npm run windows:build
```

输出 `release/HushNest-0.1.0-Windows-x64.exe`，为便携应用；原生音频组件已自包含 .NET 运行时。未配置发布证书，程序没有代码签名，正式分发需开发者签名。

## 测试

```sh
npm test
npx playwright install chromium
npm run test:web
node tests/windows-smoke.mjs
node tests/offline-smoke.mjs
```

核心测试覆盖时钟漂移、暂停累计、断连截止时间、3 分钟响铃窗口、持续重复、稍后提醒、恢复校验、非法配置、跨午夜、记录上限及音频校验摘要。浏览器测试覆盖 Web 无耳机确认时直接计时及试听、秒级唤醒、稍后提醒、暂停恢复、刷新恢复、设备变化不中断 Web、原生端耳机保护、本机媒体导入/删除、移动布局、语言持久化和多窗口互斥。自动化浏览器使用无声播放替身；Windows smoke 仅查询设备并验证 IPC / 资源 / 沙箱，不播放声音。

`.github/workflows/multiplatform.yml` 分别构建 Web、调试 APK 和 Windows 便携程序并上传 Actions artifacts。它不发布网站或修改 App Store。现有 iOS 与官网 workflow 未修改。

仍需实体安卓设备及耳机测试锁屏到点、蓝牙断连/重连、来电和各厂商电池限制，以及 Windows 实际耳机热插拔和音量行为。编译通过和无声自动化不能替代这些硬件验证。

## 目录

`src/core/` 是共享计时和存储逻辑；`src/` 为响应式界面和 Web 控制器；`android/` 的原生服务拥有安卓会话；`desktop/` 为沙箱桌面进程及 WASAPI 子进程；`scripts/prepare-assets.mjs` 只读取原 iOS 音频和六语言资源，生成各端的构建资源。

所有外部依赖及录音许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
