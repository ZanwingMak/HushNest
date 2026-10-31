# 下载、安装与发行维护

更新日期：2026-11-01。所有功能免费，当前多平台预览与原生 iOS 分别维护版本。

## 官方入口

[官网选择平台](https://zanwingmak.github.io/HushNest/#downloads) · [Web 在线版](https://zanwingmak.github.io/HushNest/app/) · [多平台预览 Release](https://github.com/ZanwingMak/HushNest/releases/tag/multiplatform-v0.4.0) · [iOS 1.6.0](https://github.com/ZanwingMak/HushNest/releases/tag/v1.6.0)

| 平台 | 下载文件 | 版本与条件 |
| --- | --- | --- |
| Windows | [安装器](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.4.0-windows-x64-setup.exe) · [完整便携包](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.4.0-windows-x64-portable.zip) | 0.4.0 / x64 / 未签名测试包 |
| macOS | [通用 DMG](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.4.0-macos-universal.dmg) | 0.4.0 / macOS 12+ / Apple Silicon、Intel / 未公证测试包 |
| Android | [测试 APK](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.1.0-android-debug.apk) | 0.1.0 / Android 9+ / 调试签名 |
| Web | [在线使用](https://zanwingmak.github.io/HushNest/app/) · [静态包](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-0.1.0-web.zip) | 0.1.0 / 现代浏览器；HTTP / HTTPS 部署 |
| iPhone | [TestFlight](https://testflight.apple.com/join/cmFcXrjy) · [自行签名 IPA](https://github.com/ZanwingMak/HushNest/releases/download/v1.6.0/HushNest-1.6.0-unsigned.ipa) | iOS 1.6.0 / iOS 17+；TestFlight 名额由 Apple 管理，IPA 需自行签名 |

多平台附件由固定的[主分支四平台构建](https://github.com/ZanwingMak/HushNest/actions/runs/41225418108)组装，源码提交为 `a1d2673bb861aa9158ca6f230583b5f49427f733`。固定版本的 Release 下载链接公开可用，无需依赖 Actions 登录或附件保留期限。多平台预览不会替换现有 iOS 发行附件，也不会变成 iOS 的“Latest”版本。

## Windows

运行安装器，建议保留默认目录 `%LOCALAPPDATA%\Programs\HushNest`，普通用户即可安装。手动选择受保护目录可能出现写入失败，应选择自己可写的目录。覆盖升级保留原有本机设置与休息记录；先结束正在进行的休息。

便携版解压后，从 `HushNest-windows-x64/HushNest.exe` 启动。请保留 `audio/`、`audio-guard/`、语言、图标和许可证等全部资源；只复制主程序无法独立运行。当前测试包未做代码签名，系统可能显示发布者确认提示。

## macOS

打开 DMG，把 HushNest 拖入“应用程序”。一个通用包同时包含 Apple Silicon 与 Intel 版本。当前使用 ad hoc 签名，尚未做 Developer ID 公证，系统可能要求在“隐私与安全性”中确认打开；下载前可核对发行校验文件。

## Android

下载 APK，并按系统提示允许当前下载来源安装。此包使用调试签名，用于体验，不是商店正式包。不同签名的已有版本可能无法覆盖安装；卸载会删除其本机数据，请先自行保留需要的内容。系统电池管理可能影响后台运行，首次请短计时验证。

## Web

直接打开[在线版](https://zanwingmak.github.io/HushNest/app/)，支持时可添加到主屏幕。Web 不检查耳机，音频会跟随系统输出，可能外放；需要保持浏览器页面打开、设备唤醒。首次使用某条音频时联网缓存，之后可离线播放已缓存的声音。

静态 ZIP 完整解压后，以 HTTP / HTTPS 静态服务器提供 `HushNest-web/`；不要直接双击 `index.html`。例如在该目录执行 `python -m http.server 8080`，再访问 `http://localhost:8080/`。PWA / 离线缓存要求 HTTPS 或 localhost，资源路径支持部署在子目录。

清除网站数据会删除当前浏览器的配置、导入音频、休息记录及缓存。仅删除主屏幕图标不一定清除浏览器数据。

## iPhone

TestFlight 的外部开放、构建有效期与名额由 Apple 管理。Release 中的 `unsigned.ipa` 未附分发签名，不能直接点击安装；需要自己的签名方式及适用的 Apple 配置。iOS 源码、音包与发行说明仍独立保留在 [v1.6.0](https://github.com/ZanwingMak/HushNest/releases/tag/v1.6.0)。

## 校验文件

[SHA256SUMS.txt](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/SHA256SUMS.txt) 列出五个多平台附件的 SHA256；[HushNest-release-manifest.json](https://github.com/ZanwingMak/HushNest/releases/download/multiplatform-v0.4.0/HushNest-release-manifest.json) 记录来源提交、构建 ID、文件大小及摘要。iOS IPA 的摘要以其独立 Release 说明为准。

Windows 可运行 `Get-FileHash -Algorithm SHA256 <文件>`；macOS 可运行 `shasum -a 256 <文件>`，与对应清单核对。

## 发布下一版

1. 更新应用版本并运行 `.github/workflows/multiplatform.yml`，确认 `main` 的 Web、Android、macOS、Windows 四个任务全部成功。
2. 更新 [website/downloads.json](../website/downloads.json) 中的版本化文件名、来源构建 ID 和源码 SHA，并同步 README、官网链接与本文；每个发行标签固定对应一笔已验证的源码提交。
3. 手动运行 `Prepare or publish multiplatform downloads`，保持 `publish=false`。工作流只使用指定构建的最终产物，核验桌面 QA、APK 完整性及实际长音轨摘要，生成完整便携包、静态 Web 包、发行说明与校验文件，再上传为草稿。
4. 检查草稿及本地官网预览后，用 `publish=true` 再运行工作流。服务器上的逐文件摘要全部一致才会发布；已经发布的版本不会被此脚本覆盖。要更换二进制，请使用新的发行标签。
5. 将官网下载入口合并至 `main`。Pages 工作流同时部署介绍页面和 `app/` Web 应用，随后检查公开下载、首页、隐私与条款、Web 子路径及离线缓存。

下载与发布脚本不改动原 iOS 二进制，不持有签名证书。Actions 中短期保存的构建附件用于验证及组装，用户长期下载入口为 GitHub Release。
