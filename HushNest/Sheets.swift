import SwiftUI

struct DurationSheet: View {
    @Environment(\.nestTheme) private var theme
    @EnvironmentObject private var store: RestStore
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 30
    @State private var seconds = 0
    @State private var savePreset = true
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker(L("小时"), selection: Binding(get: { minutes / 60 }, set: { minutes = min(720, $0 * 60 + minutes % 60) })) {
                            ForEach(0...12, id: \.self) { Text(LF("%@ 小时", String(describing: $0))).tag($0) }
                        }.pickerStyle(.wheel).frame(maxWidth: .infinity).clipped().accessibilityIdentifier("duration.hours")
                        Picker(L("分钟"), selection: Binding(get: { minutes % 60 }, set: { minutes = min(720, minutes / 60 * 60 + $0) })) {
                            ForEach(0...59, id: \.self) { Text(LF("%@ 分", String(describing: $0))).tag($0) }
                        }.pickerStyle(.wheel).frame(maxWidth: .infinity).clipped().accessibilityIdentifier("duration.minutes")
                        Picker(L("秒"), selection: $seconds) {
                            ForEach(0...59, id: \.self) { Text(LF("%@ 秒", String(describing: $0))).tag($0) }
                        }.pickerStyle(.wheel).frame(maxWidth: .infinity).clipped().disabled(minutes == 720).accessibilityIdentifier("duration.seconds")
                    }.frame(height: 150)
                    Stepper(LF("%@ 分钟", String(describing: minutes)), value: $minutes, in: 0...720).accessibilityIdentifier("duration.stepper")
                    Toggle(L("保存到常用预设"), isOn: $savePreset).accessibilityIdentifier("duration.savePreset")
                } footer: { Text(L("支持 1 秒至 12 小时。长时间使用请留意耳机电量。")) }
            }.navigationTitle(L("留一点时间给自己")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("取消")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("完成")) {
                            store.preferences.minutes = minutes
                            store.preferences.seconds = minutes == 720 ? 0 : seconds
                            if savePreset { store.addDurationPreset(Int(store.preferences.durationSeconds)) }
                            dismiss()
                        }.accessibilityIdentifier("duration.done").disabled(minutes == 0 && seconds == 0)
                    }
                }.onAppear { minutes = store.preferences.minutes; seconds = store.preferences.seconds }
        }
    }
}

struct SoundSheet: View {
    @EnvironmentObject private var library: MediaLibrary
    @Environment(\.nestTheme) private var theme
    @EnvironmentObject private var store: RestStore
    @Environment(\.dismiss) private var dismiss
    @State private var previewError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SleepSound.allCases.filter { $0 != .custom }) { sound in
                        HStack(spacing: 12) {
                            Button { store.stopPreview(); store.preferences.sleepSound = sound } label: {
                                HStack(spacing: 12) {
                                Image(systemName: sound.symbol).font(.title3).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sound.title).foregroundStyle(.primary)
                                    Text(sound.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.preferences.sleepSound == sound { Image(systemName: "checkmark.circle.fill") }
                                }.frame(minHeight: 44)
                            }.buttonStyle(.borderless).accessibilityIdentifier("sound.\(sound.rawValue)")
                                .accessibilityAddTraits(store.preferences.sleepSound == sound ? .isSelected : [])
                            if sound != .none { Button { preview(sound.rawValue, volume: store.preferences.sleepVolume) } label: {
                                Image(systemName: store.previewing == sound.rawValue ? "stop.circle" : "play.circle")
                                    .font(.title2).frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel(store.previewing == sound.rawValue ? LF("停止试听%@", String(describing: sound.title)) : LF("试听%@", String(describing: sound.title)))
                                .accessibilityIdentifier("preview.\(sound.rawValue)") }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    if store.preferences.sleepSound == .custom {
                        Label(library.sounds.first { $0.id == store.preferences.customSleepID }?.name ?? L("自定义声音"), systemImage: "checkmark.circle.fill")
                        Button(store.previewing == customSleepName ? L("停止试听") : L("试听助眠音（仅耳机）")) { preview(customSleepName, volume: store.preferences.sleepVolume) }
                    }
                    NavigationLink { MediaSheet() } label: { Label(L("我的声音 · 导入音频或视频"), systemImage: "square.and.arrow.down") }.accessibilityIdentifier("media.open")
                    LabeledContent(L("助眠音量"), value: "\(Int(store.preferences.sleepVolume * 100))%")
                    Slider(value: $store.preferences.sleepVolume, in: 0.01...0.6).accessibilityLabel(L("助眠音量")).disabled(store.preferences.sleepSound == .none)
                } header: { Text(L("休息时，听见自然")) } footer: { Text(L("有助眠音：支持锁屏与混音。暂时中断后，系统允许且耳机可用时会自动恢复；已到点则补响。系统未允许恢复时需手动继续。无助眠音：仍无法保证锁屏响铃或震动，开始前需确认风险。")) }
                Section {
                    Picker(L("唤醒铃声"), selection: $store.preferences.alarmSound) {
                        ForEach(AlarmSound.allCases.filter { $0 != .custom || store.preferences.customAlarmID != nil }) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("alarm.sound")
                    if store.preferences.alarmSound == .custom { Text(library.sounds.first { $0.id == store.preferences.customAlarmID }?.name ?? L("自定义声音")).font(.caption) }
                    Button(store.previewing == alarmName ? L("停止试听") : L("试听铃声（仅耳机）")) {
                        preview(alarmName, volume: store.preferences.alarmVolume)
                    }.accessibilityIdentifier("preview.alarm")
                    LabeledContent(L("提醒音量"), value: "\(Int(store.preferences.alarmVolume * 100))%")
                    Slider(value: $store.preferences.alarmVolume, in: 0.05...1).accessibilityLabel(L("提醒音量")).accessibilityIdentifier("alarm.volume")
                    #if DEBUG
                    if store.isTesting, let audio = store.audio as? PreviewAudio, store.previewing != nil {
                        Text(String(format: "%.2f", audio.previewVolume)).accessibilityIdentifier("preview.gain")
                    }
                    #endif
                    Toggle(L("持续响铃，直到手动停止"), isOn: $store.preferences.repeatAlarm).accessibilityIdentifier("alarm.repeat")
                    Text(L("开启后铃声会一直重复，直到结束或稍后提醒。耳机断开或音频中断时停止；关闭时最多提醒 3 分钟。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(L("唤醒时震动"), isOn: $store.preferences.vibrationEnabled).accessibilityIdentifier("alarm.vibration")
                    Text(L("震动由 iPhone 提供，受系统触感设置影响；锁屏及无助眠音挂起时不能保证震动。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper(LF("稍后提醒 %@ 分钟", String(describing: store.preferences.snoozeMinutes)), value: $store.preferences.snoozeMinutes, in: 1...30)
                        .accessibilityIdentifier("snooze.stepper")
                } header: { Text(L("到点时，按你的方式醒来")) } footer: {
                    Text(L("内置铃声逐渐增强，经典与强力铃声更鲜明。可选择持续重复响铃。实际响度也受 iPhone 媒体音量影响；初次使用请先用短计时确认。"))
                }
            }.navigationTitle(L("声音与唤醒")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("完成")) { dismiss() }.accessibilityIdentifier("sound.done") } }
                .onChange(of: store.preferences.alarmSound) { _, _ in store.stopPreview() }
                .onDisappear { store.stopPreview() }
                .alert(L("无法试听"), isPresented: Binding(get: { previewError != nil }, set: { if !$0 { previewError = nil } })) {
                    Button(L("知道了"), role: .cancel) { previewError = nil }
                } message: { Text(previewError ?? "") }
        }
    }

    private var customSleepName: String { "custom-sleep.\(store.preferences.customSleepID?.uuidString ?? "")" }
    private var alarmName: String { store.preferences.alarmSound == .custom ? "custom-alarm.\(store.preferences.customAlarmID?.uuidString ?? "")" : store.preferences.alarmSound.rawValue }

    /// 将试听错误展示在当前配置页，避免提示被模态页面遮挡。
    private func preview(_ name: String, volume: Float) {
        do { try store.preview(name: name, volume: volume) }
        catch { previewError = error.localizedDescription }
    }
}

struct GuideSheet: View {
    @Environment(\.nestTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "headphones").font(.system(size: 52, weight: .light)).foregroundStyle(theme.accent)
                    Text(L("把安静留给周围，\n把提醒留给自己。"))
                        .font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    guideRow("01", L("连接你的耳机"), L("支持有线耳机和蓝牙耳机。请确认连接的是耳机，而不是蓝牙音箱或车载设备。开启降噪不影响耳机内的声音。"))
                    guideRow("02", L("选择时长，开始休息"), L("选择助眠音时支持锁屏并与其他音频混音；不播放助眠音时需先确认锁屏风险；保留尽力预约和无声通知，但挂起后不能保证响铃。首次使用请用 1 分钟计时验证实际表现。"))
                    guideRow("03", L("到点，轻轻唤醒"), L("铃声逐渐增强，只使用已连接的耳机路由。耳机断开后停止播放。若断连发生在响铃期间，重连后尝试自动续响；休息中断连则需手动继续。"))
                    guideRow("04", L("AirPods 聆听模式"), L("iOS 未提供应用可用的自动降噪／通透切换接口。休息结束时，可长按 AirPods 耳机柄，或在控制中心长按音量条切换。耳憩无法在锁屏后台自动切换模式。"))
                    NestCard {
                        Label(L("请了解系统限制"), systemImage: "info.circle").font(.headline)
                        Text(L("这不是系统闹钟。强制关闭应用、手机重启、耳机没电、来电或其他音频中断都可能使提醒停止。静默通知只是文字提示，不会外放铃声，也不能替代耳机提醒。"))
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                    }
                }.padding(24)
            }.background(theme.background).navigationTitle(L("使用指南")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("知道了")) { dismiss() }.accessibilityIdentifier("guide.done") } }
        }
    }

    /// 使用一致的编号说明每一步，同时允许大字体自然换行。
    private func guideRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.subheadline.monospaced().weight(.semibold)).foregroundStyle(theme.accent).padding(.top, 3)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
