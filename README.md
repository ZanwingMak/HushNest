# 耳憩 HushNest

免费开源的休息计时器，支持 iPhone、Android、Windows、macOS 和 Web。给自己片刻安静，让自然音陪你放松，再渐渐醒来。

[官网与下载](https://zanwingmak.github.io/HushNest/#downloads) · [直接打开网页版](https://zanwingmak.github.io/HushNest/app/) · [多平台预览 Release](https://github.com/ZanwingMak/HushNest/releases/tag/multiplatform-v0.4.0) · [安装说明](docs/DOWNLOADS.md)

## 下载

| 平台 | 当前版本 | 下载 / 使用 | 条件 |
| --- | --- | --- | --- |
| Windows x64 | 0.4.0 预览 | [安装包](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.4.0-windows-x64-setup.exe) · [完整便携包](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.4.0-windows-x64-portable.zip) | MyGo 原生桌面；未签名测试包；默认当前用户安装。 |
| macOS 12+ | 0.4.0 预览 | [通用 DMG](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.4.0-macos-universal.dmg) | Apple Silicon / Intel；当前未公证。 |
| Android 9+ | 0.1.0 测试 | [APK](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.1.0-android-debug.apk) | 调试签名；非商店正式包。 |
| iPhone · iOS 17+ | 1.6.0 | [TestFlight](https://testflight.apple.com/join/cmFcXrjy) · [自行签名 IPA](https://github.com/ZanwingMak/HushNest/releases/download/v1.6.0/HushNest-1.6.0-unsigned.ipa) | TestFlight 外部开放与名额由 Apple 管理；IPA 需要自行签名。 |
| Web / PWA | 0.1.0 | [在线使用](https://zanwingmak.github.io/HushNest/app/) · [静态包](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.1.0-web.zip) | 不检测耳机；需保持浏览器打开及设备唤醒。 |

多平台预览与原生 iOS 分别维护版本。[SHA256SUMS.txt](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/SHA256SUMS.txt) 提供多平台附件摘要；[发行清单](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-release-manifest.json) 记录来源构建、源码提交和逐文件校验。长音轨随包提供，安装包体积较大。GitHub 自动生成的源码压缩包用于开发，不是安装器。

## 多平台功能与使用边界

各平台提供秒级倒计时、指定时间、长助眠音、14 种唤醒铃声、本机媒体导入、主题、六种语言和休息记录。配置和导入媒体留在设备或当前浏览器中，无账号、广告或分析 SDK。桌面试听可再次点击停止；长音轨在应用内显示时长。

| 平台 | 耳机与后台 |
| --- | --- |
| iOS | 核验真实耳机输出；可听助眠音支持后台音频，无助眠音时可能被系统挂起。 |
| Android | 原生路由校验，蓝牙需确认类型；前台服务计时，仍受系统电池管理及进程关闭影响。 |
| Windows / macOS | MyGo 原生 Go UI；固定系统音频端点，识别不准时二次确认。休息期间保持电脑唤醒，最小化或收至托盘可继续计时。 |
| Web | 不检测耳机，可能外放；保持页面打开及设备唤醒，锁屏与后台提醒不可靠。 |

有线耳机能否自动识别取决于声卡与驱动；某些 3.5 mm 插孔始终显示为“扬声器”，桌面可由用户确认实际已连接耳机后放行。没有输出设备时不能放行。首次请用短计时验证自己的设备。

[多端开发与构建说明](cross-platform/README.md) · [跨平台需求与交付记录](docs/requirements/2026-11-01-multiplatform.md) · [多平台分发需求](docs/requirements/2026-11-01-downloads.md) · [下载、安装与发行维护](docs/DOWNLOADS.md)

## iPhone 功能

- 秒级倒计时、指定时间，默认 15 / 30 / 45 / 60 分钟预设，自定义时长可保存。
- 6 种真实录制的自然音景、棕噪音和粉红噪音，以及 14 种唤醒铃声，耳机内试听及实时音量调整。助眠音最低 1%，也可选择无助眠音。
- 可开启持续响铃，重复直到手动结束或稍后提醒；关闭时最多提醒 3 分钟。支持可选震动。
- 从文件导入音频或视频，或从相册选择视频，在本机提取音轨。每个文件最多 200 MB、2 小时，最多保存 20 个；自定义铃声使用前 60 秒。
- 检查真实耳机媒体输出。可确认后尝试将 AirPods 切至 iPhone，最多检测 12 秒，成功后在耳机中播放两秒轻柔提示音。
- 四套主题，支持大字体、深色模式和减少动态效果。
- 简体中文、繁体中文、英语、日语、韩语、西班牙语。四档赞助商品均配置六语言名称与说明。
- 配置、导入音轨与最多 365 条休息记录仅保存在本机。无广告、无分析 SDK、无需账号或麦克风。

所有平台功能免费。iPhone 内的茶、咖啡、甜点、小花园是四个可重复购买的一次性赞助金额，没有订阅或功能等级。实际价格以当地 App Store 和 Apple 支付确认页为准。赞助由 StoreKit 处理。

## iPhone 使用须知

开始前连接耳机，并先用短计时确认实际表现。扬声器、AirPlay、车载及混合输出不会用于开始提醒。耳机断开会停止声音；响铃期间重连后尝试续响，限时模式只在三分钟窗口内续响，持续模式继续等待手动停止。

播放可听助眠音时支持后台音频及与其他应用混音。暂时音频中断会保留截止时间和无声通知；系统允许后重新验证耳机并自动恢复，已到点则立即补响。音频暂未就绪时有限重试，耳机重连或返回前台时也会重新检查；系统未建议恢复时需要手动继续。无助眠音会先提示锁屏风险：iOS 可能挂起应用，因此不能保证后台响铃或震动。可选本地通知只有文字、不携带铃声。来电、其他音频、强制关闭、重启或耳机没电仍可能使提醒不可用，不能将它作为重要事项的唯一提醒。

AirPods 设备切换由 iOS 决定，主动尝试可能暂停其他媒体，也可能失败；可使用系统输出选择器手动切换。当前没有适用的公开接口让第三方应用自动切换 AirPods 降噪或通透模式。

## 构建与测试

Web、Android、Windows、macOS 需要 Node.js 24；桌面另需 Go 1.27.3，Windows 音频组件需 .NET 8 SDK；Android 需 JDK 21 和 Android SDK 36。具体命令与平台依赖见 [多端开发说明](cross-platform/README.md)。

```sh
cd cross-platform
npm ci
npm run dev
npm test
npm run build
```

以下命令在仓库根目录构建和测试原生 iOS：

需要 macOS、Xcode、XcodeGen；支持 iOS 17 及以上版本。

```sh
xcodegen generate
open HushNest.xcodeproj
```

自行安装时在 Xcode 中选择自己的签名团队。仓库不包含发布密钥或签名证书。

```sh
bash scripts/test.sh
bash scripts/package.sh
```

测试覆盖倒计时、持久化、路由保护、断连续响、音频中断恢复与到期补响、持续响铃、媒体导入、StoreKit 沙盒及 UI 交互。UI 自动化使用完全无声的音频替身，真实播放器测试只准备或解码资源，不输出声音。真机后台及跨设备 AirPods 行为仍需要设备验证。

## 发布与许可

[iOS 1.6.0](https://github.com/ZanwingMak/HushNest/releases/tag/v1.6.0) 提供长音轨、循环优化和实际时长显示，继续通过 TestFlight 和自行签名 IPA 分发。[多平台预览](https://github.com/ZanwingMak/HushNest/releases/tag/multiplatform-v0.4.0) 提供原生 MyGo 桌面、Web / Android、桌面设备二次确认、试听停止及独立长音包；具体版本与安装条件见上方下载表。

应用代码、原创图标和合成音频使用 [MIT 许可证](LICENSE)。自然录音按各自来源的 CC0 / 公有领域许可分发，见 [iOS 音源清单](HushNest/Resources/FieldRecordings.json)和[跨平台第三方说明](cross-platform/THIRD_PARTY_NOTICES.md)。用户自行导入的媒体不包含在项目许可证内。

[隐私政策](https://zanwingmak.github.io/HushNest/privacy.html) · [服务条款](https://zanwingmak.github.io/HushNest/terms.html) · [联系与反馈](https://github.com/ZanwingMak/HushNest/issues)

Copyright (c) 2026 ZHENYING MAI
