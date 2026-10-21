import SwiftUI

struct SettingsView: View {
    @Environment(\.nestTheme) private var theme
    @EnvironmentObject private var store: RestStore
    @EnvironmentObject private var support: SupportStore
    @Environment(\.openURL) private var openURL
    @State private var showSupport = false
    @State private var showSound = false
    @State private var showDuration = false
    @State private var showGuide = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "moon.zzz").font(.largeTitle.weight(.light)).foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("耳憩 HushNest")).font(.headline)
                            Text(L("片刻安静，自在醒来。")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
                Section {
                    Button(L("声音与唤醒")) { showSound = true }.accessibilityIdentifier("settings.sound")
                    Button(L("添加常用时长")) { showDuration = true }.accessibilityIdentifier("settings.preset")
                    ForEach(store.preferences.presetDurations, id: \.self) { seconds in
                        HStack {
                            Text(seconds % 60 == 0 ? LF("%@ 分钟", String(describing: seconds / 60)) : LF("%@ 分 %@ 秒", String(describing: seconds / 60), String(describing: seconds % 60)))
                            Spacer()
                            Button(role: .destructive) { store.removeDurationPreset(seconds) } label: { Image(systemName: "minus.circle") .frame(width: 44, height: 44) }
                                .accessibilityLabel(LF("删除 %@ 分 %@ 秒预设", String(describing: seconds / 60), String(describing: seconds % 60)))
                        }
                    }
                } header: { Text(L("按你的节奏")) } footer: {
                    Text(store.session == nil ? L("预设数量不限，全部功能永久免费。") : L("休息进行中，结束后可修改配置。"))
                }.disabled(store.session != nil)
                Section(L("心情与色彩")) {
                    Picker(L("主题"), selection: $store.theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("settings.theme")
                }
                Section {
                    Button { store.requestNotifications() } label: {
                        LabeledContent(L("到点静默通知"), value: store.notificationStatus)
                    }.accessibilityIdentifier("settings.notifications")
                    Button(L("打开系统设置")) { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                } header: { Text(L("不打扰的提醒")) } footer: {
                    Text(L("可选的文字通知不携带铃声。耳机提醒无需通知权限；请留意系统专注模式可能隐藏通知。"))
                }
                Section {
                    LabeledContent(L("语言"), value: L("跟随系统"))
                    Button(L("更改应用语言")) { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                } footer: { Text(L("支持简体中文、繁體中文、English、日本語、한국어、Español。可在 iPhone 设置中选择应用语言。")) }
                Section {
                    Button(L("使用指南与系统限制")) { showGuide = true }.accessibilityIdentifier("settings.guide")
                    Button(L("赞助开发 · 自愿支持")) { showSupport = true }.accessibilityIdentifier("settings.support")
                    Link(L("官网"), destination: URL(string: "https://zanwingmak.github.io/HushNest/")!)
                    Link(L("隐私政策"), destination: URL(string: "https://zanwingmak.github.io/HushNest/privacy.html")!)
                    Link(L("服务条款"), destination: URL(string: "https://zanwingmak.github.io/HushNest/terms.html")!)
                    Link(L("查看开源代码"), destination: URL(string: "https://github.com/ZanwingMak/HushNest")!)
                    Link(L("反馈问题与建议"), destination: URL(string: "https://github.com/ZanwingMak/HushNest/issues")!)
                    LabeledContent(L("版本"), value: "1.2.0 (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                } header: { Text(L("自由，也透明")) } footer: {
                    Text(L("MIT 开源 · 无广告 · 无订阅 · 可自愿一次性赞助。\n不收集个人数据，不使用麦克风。仅赞助时通过 Apple StoreKit 联网处理交易。配置和最多 365 条休息记录仅保存在本机，卸载后删除。访问 GitHub 链接时适用 GitHub 的隐私政策。"))
                }
                #if DEBUG
                if store.isTesting {
                    Section(L("自动化测试 · 无声模拟")) {
                        Button(L("模拟断开耳机")) { (store.audio as? PreviewAudio)?.disconnect() }.accessibilityIdentifier("test.disconnect")
                        Button(L("模拟重新连接")) { (store.audio as? PreviewAudio)?.reconnect() }.accessibilityIdentifier("test.reconnect")
                        Button(L("模拟系统中断")) { store.block(L("模拟来电中断，请手动继续。")) }.accessibilityIdentifier("test.interrupt")
                    }
                }
                #endif
            }.scrollContentBackground(.hidden).background(theme.background).navigationTitle(L("我的耳憩"))
                .sheet(isPresented: $showSupport) { SupportSheet(support: support) }
                .sheet(isPresented: $showSound) { SoundSheet() }
                .sheet(isPresented: $showDuration) { DurationSheet().presentationDetents([.large]) }
                .sheet(isPresented: $showGuide) { GuideSheet() }
        }
    }
}
