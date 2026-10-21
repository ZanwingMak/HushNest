import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: RestStore
    var body: some View {
        TabView {
            RestView().tabItem { Label("休息", systemImage: "moon.zzz") }.accessibilityIdentifier("tab.rest")
            HistoryView().tabItem { Label("足迹", systemImage: "leaf") }.accessibilityIdentifier("tab.history")
            SettingsView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("tab.settings")
        }
        .alert("暂时无法开始", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct RestView: View {
    @EnvironmentObject private var store: RestStore
    @Environment(\.dynamicTypeSize) private var typeSize
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
        return TimeInterval(store.preferences.minutes * 60)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    routeCard
                    #if DEBUG
                    if store.isTesting && store.session == nil {
                        Button("3 秒无声测试") { store.start(duration: 3) }
                            .frame(minHeight: 44).accessibilityIdentifier("test.quickStart")
                    }
                    #endif
                    if let session = store.session { activeTimer(session) } else { idleTimer }
                    if store.session == nil { configuration }
                    if let session = store.session, session.phase == .blocked {
                        Label(session.reason ?? "请检查耳机后手动恢复。", systemImage: "pause.circle")
                            .font(.subheadline).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    }
                    reassurance
                }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
            }
            .background(Palette.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDuration) { DurationSheet().presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showSound) { SoundSheet() }
            .sheet(isPresented: $showGuide) { GuideSheet() }
            .confirmationDialog("结束这次休息？", isPresented: $cancelConfirmation, titleVisibility: .visible) {
                Button("结束休息", role: .destructive) { store.finish(completed: false) }
                Button("继续休息", role: .cancel) {}
            } message: { Text("计时和耳机内的声音都会停止。") }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("HUSHNEST").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(Palette.accent)
                Text(store.session == nil ? "给自己，片刻安静。" : "安心休息，慢慢来。")
                    .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { showGuide = true } label: {
                Image(systemName: "questionmark.circle").font(.title3).frame(width: 44, height: 44)
            }.accessibilityLabel("使用指南").accessibilityIdentifier("guide.open")
        }
    }

    private var routeCard: some View {
        Button { showGuide = true } label: {
            HStack(spacing: 14) {
                Image(systemName: store.hasHeadphones ? "headphones" : "headphones.slash")
                    .font(.title2).foregroundStyle(Palette.accent).frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.hasHeadphones ? "耳机已就绪" : "连接耳机，再安心休息").font(.subheadline.weight(.semibold))
                    Text(store.routeName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("route.status")
    }

    private var idleTimer: some View {
        VStack(spacing: 14) {
            Text(clockMode ? "在这个时间轻轻醒来" : "这一刻，只属于你")
                .font(.subheadline).foregroundStyle(.secondary)
            if clockMode {
                        DatePicker("唤醒时间", selection: $targetTime, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.wheel).frame(maxHeight: 150).accessibilityIdentifier("clock.picker")
            } else {
                Button { showDuration = true } label: {
                    VStack(spacing: 6) {
                        Text("\(store.preferences.minutes)")
                            .font(.system(size: 88, weight: .light, design: .rounded)).minimumScaleFactor(0.5)
                            .foregroundStyle(Palette.ink)
                        HStack(spacing: 5) {
                            Text("分钟").font(.subheadline)
                            Image(systemName: "pencil").font(.caption)
                        }.foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.plain).accessibilityIdentifier("duration.edit")
            }
            Picker("提醒方式", selection: $clockMode) {
                Text("倒计时").tag(false)
                Text("指定时间").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("schedule.mode")
            if clockMode {
                Text("下一次 \(targetTime.formatted(date: .omitted, time: .shortened)) · \(Int(ceil(selectedDuration / 60))) 分钟后")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.preferences.presets, id: \.self) { minutes in
                            Button { store.preferences.minutes = minutes } label: {
                                Text("\(minutes) 分").font(.subheadline.weight(.medium)).padding(.horizontal, 18).frame(minHeight: 44)
                                    .foregroundStyle(store.preferences.minutes == minutes ? Palette.onAccent : Palette.accent)
                                    .background(store.preferences.minutes == minutes ? Palette.accent : Palette.accent.opacity(0.08), in: Capsule())
                            }.accessibilityIdentifier("preset.\(minutes)")
                        }
                        Button { showDuration = true } label: {
                            Image(systemName: "plus").frame(width: 44, height: 44)
                                .background(Palette.accent.opacity(0.08), in: Circle())
                        }.accessibilityLabel("自定义时长和预设")
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
                    Text(session.phase == .ringing ? "时间到了" : formattedRemaining)
                        .font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.5).lineLimit(1).accessibilityIdentifier("session.remaining")
                    Text("\(session.deadline.formatted(date: .omitted, time: .shortened)) 轻轻唤醒")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ZStack {
                Circle().stroke(Palette.accent.opacity(0.08), lineWidth: 3)
                Circle().trim(from: 0, to: max(0, min(1, store.remaining / session.duration)))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 14) {
                    Image(systemName: session.phase == .ringing ? "sunrise" : "moon.zzz")
                        .font(.system(size: 36, weight: .light)).foregroundStyle(Palette.accent)
                    Text(phaseTitle(session.phase)).font(.headline).accessibilityIdentifier("session.phase")
                    Text(session.phase == .ringing ? "时间到了" : formattedRemaining)
                        .font(.system(size: session.phase == .ringing ? 36 : 52, weight: .light, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                        .accessibilityIdentifier("session.remaining")
                    Text(session.phase == .ringing ? "慢慢睁眼，带走这份轻松" : "\(session.deadline.formatted(date: .omitted, time: .shortened)) 轻轻唤醒")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(30)
                }.frame(maxWidth: 310).aspectRatio(1, contentMode: .fit).padding(.horizontal, 12)
            }
            if session.snoozeCount > 0 { Text("已稍后提醒 \(session.snoozeCount) 次").font(.caption).foregroundStyle(.secondary) }
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
                    Image(systemName: store.preferences.sleepSound.symbol).font(.title2).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(store.preferences.sleepSound.title) → \(store.preferences.alarmSound.title)").font(.headline)
                        Text("助眠声音 · 渐强唤醒").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("sound.open")
    }

    private var reassurance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("手机不外放，断连即停止", systemImage: "speaker.slash").font(.subheadline.weight(.medium))
            Text("锁屏期间会持续播放你选择的助眠声音。请保持耳机连接，不要强制关闭应用；来电或系统中断后需手动继续。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if let session = store.session {
                if session.phase == .ringing {
                    Button("我醒了，结束休息") { store.finish(completed: true) }
                        .buttonStyle(NestButtonStyle()).accessibilityIdentifier("session.finish")
                    Button("再休息 \(store.preferences.snoozeMinutes) 分钟") { store.snooze() }
                        .buttonStyle(NestButtonStyle(secondary: true)).accessibilityIdentifier("session.snooze")
                } else {
                    Button {
                        if session.phase == .resting { store.pause() } else { store.resume() }
                    } label: {
                        Label(session.phase == .resting ? "暂停一下" : (typeSize.isAccessibilitySize ? "继续休息" : "确认耳机，继续休息"), systemImage: session.phase == .resting ? "pause.fill" : "play.fill")
                    }.buttonStyle(NestButtonStyle()).accessibilityIdentifier("session.toggle")
                    Button("结束这次休息") { cancelConfirmation = true }
                        .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("session.cancel")
                }
            } else {
                Button { store.start(duration: selectedDuration) } label: {
                    Label(typeSize.isAccessibilitySize ? "开始休息" : "开始我的片刻安静", systemImage: "play.fill")
                }.buttonStyle(NestButtonStyle()).accessibilityIdentifier("session.start")
                Text("免费 · 无广告 · 无订阅 · 数据仅在本机").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12).background(Palette.background)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }

    /// 为各状态提供明确的界面文案，不把中断误标为运行中。
    private func phaseTitle(_ phase: SessionPhase) -> String {
        switch phase { case .resting: "好好休息"; case .paused: "休息已暂停"; case .ringing: "轻轻唤醒"; case .blocked: "提醒已中断" }
    }
}
