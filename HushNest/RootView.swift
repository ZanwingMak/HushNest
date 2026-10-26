import SwiftUI

struct RootView: View {
    @Environment(\.nestTheme) private var theme
    @EnvironmentObject private var store: RestStore
    var body: some View {
        TabView {
            RestView().tabItem { Label(L("休息"), systemImage: "moon.zzz") }.accessibilityIdentifier("tab.rest")
            HistoryView().tabItem { Label(L("足迹"), systemImage: "leaf") }.accessibilityIdentifier("tab.history")
            SettingsView().tabItem { Label(L("设置"), systemImage: "slider.horizontal.3") }.accessibilityIdentifier("tab.settings")
        }
        .onAppear { store.reconnectHeadphones() }
        .alert(L("暂时无法开始"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(L("知道了"), role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct RestView: View {
    @EnvironmentObject private var library: MediaLibrary
    @Environment(\.nestTheme) private var theme
    @EnvironmentObject private var store: RestStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmConnection = false
    @State private var confirmSilent = false
    @State private var showDuration = false
    @State private var showSound = false
    @State private var showGuide = false
    @State private var cancelConfirmation = false
    @State private var targetTime = Date().addingTimeInterval(1800)
    @State private var clockMode = false

    private var selectedDuration: TimeInterval {
        if clockMode {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: targetTime)
            return Schedule.nextOccurrence(hour: parts.hour ?? 0, minute: parts.minute ?? 0, after: Date()).timeIntervalSinceNow
        }
        return store.preferences.durationSeconds
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    routeCard
                    #if DEBUG
                    if store.isTesting && store.session == nil {
                        Button(L("3 秒无声测试")) { store.start(duration: 3) }
                            .frame(minHeight: 44).accessibilityIdentifier("test.quickStart")
                    }
                    #endif
                    if let session = store.session { activeTimer(session) } else { idleTimer }
                    if store.session == nil { configuration }
                    if let session = store.session, session.phase == .blocked {
                        Label(session.reason ?? L("请检查耳机后手动恢复。"), systemImage: "pause.circle")
                            .accessibilityIdentifier("session.interruption")
                            .font(.subheadline).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
            }
            .background(theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDuration) { DurationSheet().presentationDetents([.large]) }
            .sheet(isPresented: $showSound) { SoundSheet() }
            .sheet(isPresented: $showGuide) { GuideSheet() }
            .alert(L("尝试将耳机切到 iPhone？"), isPresented: $confirmConnection) {
                Button(L("我已戴上耳机，尝试播放音频触发连接")) { store.attemptHeadphoneConnection() }
                    .accessibilityIdentifier("connection.confirm")
                Button(L("取消"), role: .cancel) {}
            } message: {
                Text(L("如果 AirPods 仍在 Mac 上播放，可尝试唤起 iPhone 音频。这可能暂停其他媒体；确认实际耳机路由前保持无声，成功后仅在耳机内播放两秒轻柔音乐。最多等待 12 秒，可随时取消。iOS 决定是否切换，无法保证成功。"))
            }
            .confirmationDialog(L("无助眠音：锁屏提醒无法保证"), isPresented: $confirmSilent, titleVisibility: .visible) {
                Button(L("了解风险，仍然开始")) { store.start(duration: selectedDuration) }.accessibilityIdentifier("silent.confirm")
                Button(L("返回选择助眠音")) { showSound = true }
                Button(L("取消"), role: .cancel) {}
            } message: {
                Text(L("没有持续播放的助眠音，iOS 可能在锁屏或切换应用后挂起耳憩。我们会保留耳机铃声预约和可选无声通知，但无法保证响铃或震动。重要提醒请选助眠音并先进行短时测试。"))
            }
            .confirmationDialog(L("结束这次休息？"), isPresented: $cancelConfirmation, titleVisibility: .visible) {
                Button(L("结束休息"), role: .destructive) { store.finish(completed: false) }.accessibilityIdentifier("session.confirmEnd")
                Button(L("继续休息"), role: .cancel) {}
            } message: { Text(L("计时和耳机内的声音都会停止。")) }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("HUSHNEST").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(theme.accent)
                Text(store.session == nil ? L("给自己，片刻安静。") : L("安心休息，慢慢来。"))
                    .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { showGuide = true } label: {
                Image(systemName: "questionmark.circle").font(.title3).frame(width: 44, height: 44)
            }.accessibilityLabel(L("使用指南")).accessibilityIdentifier("guide.open")
        }
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Button {
                    store.reconnectHeadphones()
                    if !store.hasHeadphones && store.session == nil && !store.isConnecting { confirmConnection = true }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: store.hasHeadphones ? "headphones" : "headphones.slash")
                            .font(.title3).foregroundStyle(theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.hasHeadphones ? L("耳机已就绪") : L("尚未连接耳机")).font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(store.hasHeadphones ? store.routeName : L("连接耳机，再安心休息"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("route.status")
                if !store.hasHeadphones && store.session == nil && !store.isConnecting {
                    Button { confirmConnection = true } label: {
                        Image(systemName: "link").frame(width: 44, height: 44)
                    }.accessibilityLabel(L("已戴上耳机？尝试连接")).accessibilityIdentifier("connection.open")
                }
                RoutePicker().frame(width: 44, height: 44).accessibilityLabel(L("选择耳机输出"))
            }
            if let message = store.connectionMessage, !store.hasHeadphones {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("connection.message")
            }
            if store.isConnecting {
                HStack {
                    ProgressView().accessibilityLabel(L("正在尝试连接耳机…"))
                    Spacer()
                    Button(L("取消连接")) { store.cancelConnectionAttempt() }
                        .frame(minHeight: 44).accessibilityIdentifier("connection.cancel")
                }
            }
        }.padding(12).background(theme.card, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("route.card")
    }

    private var idleTimer: some View {
        VStack(spacing: 14) {
            Text(clockMode ? L("在这个时间轻轻醒来") : L("这一刻，只属于你"))
                .font(.subheadline).foregroundStyle(.secondary)
            if clockMode {
                        DatePicker(L("唤醒时间"), selection: $targetTime, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.wheel).frame(maxHeight: 150).accessibilityIdentifier("clock.picker")
            } else {
                Button { showDuration = true } label: {
                    VStack(spacing: 6) {
                        Text(store.preferences.seconds == 0 ? "\(store.preferences.minutes)" : String(format: "%02d:%02d", store.preferences.minutes, store.preferences.seconds))
                            .font(.system(size: 88, weight: .light, design: .rounded)).minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.preferences.durationSeconds)
                            .foregroundStyle(Palette.ink)
                        HStack(spacing: 5) {
                            Text(store.preferences.seconds == 0 ? L("分钟") : L("分 : 秒")).font(.subheadline)
                            Image(systemName: "pencil").font(.caption)
                        }.foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.plain).accessibilityIdentifier("duration.edit")
            }
            Picker(L("提醒方式"), selection: $clockMode) {
                Text(L("倒计时")).tag(false)
                Text(L("指定时间")).tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("schedule.mode")
            if clockMode {
                Text(LF("下一次 %@ · %@ 分钟后", String(describing: targetTime.formatted(date: .omitted, time: .shortened)), String(describing: Int(ceil(selectedDuration / 60)))))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.preferences.presetDurations, id: \.self) { seconds in
                            Button { store.preferences.minutes = seconds / 60; store.preferences.seconds = seconds % 60 } label: {
                                Text(seconds % 60 == 0 ? LF("%@ 分", String(describing: seconds / 60)) : LF("%@分%@秒", String(describing: seconds / 60), String(describing: seconds % 60))).font(.subheadline.weight(.medium)).padding(.horizontal, 18).frame(minHeight: 44)
                                    .foregroundStyle(Int(store.preferences.durationSeconds) == seconds ? Palette.onAccent : theme.accent)
                                    .background(Int(store.preferences.durationSeconds) == seconds ? theme.accent : theme.accent.opacity(0.08), in: Capsule())
                            }.accessibilityIdentifier(seconds % 60 == 0 ? "preset.\(seconds / 60)" : "preset.seconds.\(seconds)")
                        }
                        Button { showDuration = true } label: {
                            Image(systemName: "plus").frame(width: 44, height: 44)
                                .background(theme.accent.opacity(0.08), in: Circle())
                        }.accessibilityLabel(L("自定义时长和预设"))
                    }
                }
            }
        }.padding(.vertical, 8)
    }

    /// 按会话状态展示进度、截止时间和可访问的剩余时间。
    private func activeTimer(_ session: RestSession) -> some View {
        VStack(spacing: 20) {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 16) {
                    Text(phaseTitle(session.phase)).font(.headline).accessibilityIdentifier("session.phase")
                    Text(session.phase == .ringing ? L("时间到了") : formattedRemaining)
                        .font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.5).lineLimit(1).accessibilityIdentifier("session.remaining")
                    Text(LF("%@ 轻轻唤醒", String(describing: session.deadline.formatted(date: .omitted, time: .shortened))))
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ZStack {
                Circle().stroke(theme.accent.opacity(0.08), lineWidth: 3)
                Circle().trim(from: 0, to: max(0, min(1, store.remaining / session.duration)))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 14) {
                    BreathingMark(symbol: session.phase == .ringing ? "sunrise" : "moon.zzz")
                    Text(phaseTitle(session.phase)).font(.headline).accessibilityIdentifier("session.phase")
                    Text(session.phase == .ringing ? L("时间到了") : formattedRemaining)
                        .font(.system(size: session.phase == .ringing ? 36 : 52, weight: .light, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                        .accessibilityIdentifier("session.remaining")
                    Text(session.phase == .ringing ? L("慢慢睁眼，带走这份轻松") : LF("%@ 轻轻唤醒", String(describing: session.deadline.formatted(date: .omitted, time: .shortened))))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(30)
                }.frame(maxWidth: 310).aspectRatio(1, contentMode: .fit).padding(.horizontal, 12)
            }
            if session.snoozeCount > 0 { Text(LF("已稍后提醒 %@ 次", String(describing: session.snoozeCount))).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 8)
    }

    private var formattedRemaining: String {
        let total = Int(ceil(store.remaining))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var configuration: some View {
        Button { showSound = true } label: {
            NestCard {
                HStack(spacing: 16) {
                    Image(systemName: store.preferences.sleepSound.symbol).font(.title2).foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(sleepTitle) → \(alarmTitle)").font(.headline)
                        Text(L("助眠声音 · 渐强唤醒")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("sound.open")
    }

    private var sleepTitle: String { store.preferences.sleepSound == .custom ? library.sounds.first { $0.id == store.preferences.customSleepID }?.name ?? L("自定义声音") : store.preferences.sleepSound.title }
    private var alarmTitle: String { store.preferences.alarmSound == .custom ? library.sounds.first { $0.id == store.preferences.customAlarmID }?.name ?? L("自定义声音") : store.preferences.alarmSound.title }

    private var reassurance: some View {
        Label(store.preferences.sleepSound == .none ? L("无助眠音：锁屏提醒无法保证") : L("手机不外放，断连即停止"),
              systemImage: store.preferences.sleepSound == .none ? "exclamationmark.circle" : "speaker.slash")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("rest.safety")
    }

    private var controls: some View {
        VStack(spacing: 8) {
            reassurance
            if let session = store.session {
                if session.phase == .ringing {
                    Button(L("我醒了，结束休息")) { store.finish(completed: true) }
                        .buttonStyle(NestButtonStyle()).accessibilityIdentifier("session.finish")
                    Button(LF("再休息 %@ 分钟", String(describing: store.preferences.snoozeMinutes))) { store.snooze() }
                        .buttonStyle(NestButtonStyle(secondary: true)).accessibilityIdentifier("session.snooze")
                } else {
                    Button {
                        if session.phase == .resting { store.pause() } else { store.resume() }
                    } label: {
                        Label(session.phase == .resting ? L("暂停一下") : (typeSize.isAccessibilitySize ? L("继续休息") : L("确认耳机，继续休息")), systemImage: session.phase == .resting ? "pause.fill" : "play.fill")
                    }.buttonStyle(NestButtonStyle()).accessibilityIdentifier("session.toggle")
                    Button(L("结束这次休息")) { cancelConfirmation = true }
                        .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("session.cancel")
                }
            } else {
                Button {
                    if store.preferences.sleepSound == .none { confirmSilent = true }
                    else { store.start(duration: selectedDuration) }
                } label: {
                    Label(typeSize.isAccessibilitySize ? L("开始休息") : L("开始我的片刻安静"), systemImage: "play.fill")
                }.buttonStyle(NestButtonStyle()).accessibilityIdentifier("session.start")
                Text(L("免费 · 无广告 · 无订阅 · 数据仅在本机")).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8).background(theme.background)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }

    /// 为各状态提供明确的界面文案，不把中断误标为运行中。
    private func phaseTitle(_ phase: SessionPhase) -> String {
        switch phase { case .resting: L("好好休息"); case .paused: L("休息已暂停"); case .ringing: L("轻轻唤醒"); case .blocked: L("提醒已中断") }
    }
}
