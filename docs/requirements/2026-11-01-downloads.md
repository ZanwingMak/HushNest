# 多平台下载与发布需求记录

日期：2026-11-01（Asia/Shanghai）。本轮是在[跨平台开发及主分支集成](2026-11-01-multiplatform.md)之后，按用户要求调整 README、Release、官网及相关说明，提供各平台下载。

## 交付范围

- 根 README 改为多平台入口，明确 Windows / macOS 0.4.0、Android / Web 0.1.0、iOS 1.6.0 的独立版本及安装条件。
- 官网沿用现有视觉，提供 Windows 安装器和完整便携包、macOS 通用 DMG、Android 测试 APK、iPhone TestFlight / 自行签名 IPA、Web 在线使用及静态 ZIP。
- 官网 `app/` 部署可实际使用的 Web 版；介绍页不自动播放音频。
- 多平台预览使用独立的 GitHub Release 标签 `multiplatform-v0.4.0`。所有新附件来自主分支提交 `a1d2673bb861aa9158ca6f230583b5f49427f733` 的四平台构建 `41225418108`，不混用开发机或旧构建的文件。
- 先生成并校验完整发行草稿，再发布；提供 SHA256 和来源清单。用户下载链接不依赖会过期的 Actions 附件。
- 原 iOS Release 和二进制保留，仅在发行说明中补充其他平台的入口；不变更 Apple 分发、审核或签名状态。
- 官网说明按平台区分耳机、后台、测试签名、媒体导入及本机数据。Web 不检测耳机，不能宣传为只在耳机内提醒。
- 更新[安装与发行维护说明](../DOWNLOADS.md)、隐私政策和服务条款的适用平台与实际行为。

## 验收条件

| 项目 | 通过条件 |
| --- | --- |
| 下载入口 | README、官网、Release 的版本、文件名及目标一致，五个平台都有可用入口。 |
| 发行来源 | 来源构建已完成且四个任务成功，源码 SHA 与配置一致；桌面 QA 验证原生界面及解码。 |
| 包完整性 | Windows 便携包包含全部资源；macOS 为通用 DMG；APK ZIP 完整且 8 段音频摘要正确；Web ZIP 可通过 HTTP / HTTPS 部署。 |
| 校验与发布 | 每个附件具备 SHA256；服务器上传摘要与发行清单一致后才允许发布。已发布版本不原地更换文件。 |
| 官网体验 | 手机及桌面无横向溢出，按钮可键盘访问，原主题及时长示意可用，不自动播放音频。 |
| Web 部署 | `app/` 页面、资源、PWA scope 均使用子路径；已缓存音频可离线读取，官网不会被应用 service worker 接管。 |
| 平台边界 | 明示桌面未签名 / 未公证、Android 调试签名、iOS IPA 自行签名及 TestFlight 条件、Web 输出及后台限制。 |
| 原生 iOS | 本轮不修改 iOS 工程、音包、功能和既有发行附件。 |

配置与维护入口见 [website/downloads.json](../../website/downloads.json)、[发行工作流](../../.github/workflows/multiplatform-release.yml)及[Pages 工作流](../../.github/workflows/pages.yml)。
