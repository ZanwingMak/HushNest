import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MediaSheet: View {
    @EnvironmentObject private var library: MediaLibrary
    @EnvironmentObject private var store: RestStore
    @State private var showImporter = false
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var deleting: PersonalSound?

    var body: some View {
        List {
            Section {
                Button(L("从文件导入音频或视频")) { showImporter = true }.accessibilityIdentifier("media.import")
                PhotosPicker(selection: $photo, matching: .videos) { Label(L("从相册选择视频"), systemImage: "photo.on.rectangle") }
                    .accessibilityIdentifier("media.photos")
            } footer: {
                Text(L("仅提取音轨并保存到本机，不上传。支持常见音频和视频；不支持受保护媒体。每个文件最多 200 MB、2 小时，最多 20 个。"))
            }.disabled(importing)
            if importing {
                Section {
                    ProgressView(L("正在提取音轨…"))
                    Button(L("取消导入"), role: .cancel) { task?.cancel() }
                }
            }
            Section {
                if library.sounds.isEmpty { Text(L("导入喜欢的音乐、录音或视频声音。")) .foregroundStyle(.secondary) }
                ForEach(library.sounds) { sound in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sound.name).font(.headline).lineLimit(2)
                        Text(Duration.seconds(sound.duration).formatted(.time(pattern: .hourMinuteSecond))).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button { select(sound, alarm: false) } label: {
                                Label(L("助眠音"), systemImage: store.preferences.sleepSound == .custom && store.preferences.customSleepID == sound.id ? "checkmark.circle.fill" : "moon")
                            }.frame(minHeight: 44).accessibilityIdentifier("media.sleep.\(sound.id)")
                            Button { select(sound, alarm: true) } label: {
                                Label(L("唤醒铃声"), systemImage: store.preferences.alarmSound == .custom && store.preferences.customAlarmID == sound.id ? "checkmark.circle.fill" : "alarm")
                            }.frame(minHeight: 44).accessibilityIdentifier("media.alarm.\(sound.id)")
                            Spacer()
                            Button(role: .destructive) { deleting = sound } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                                .accessibilityLabel(LF("删除 %@", sound.name))
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 8)
                }
            } header: { Text(L("我的声音")) } footer: { Text(L("助眠音循环播放；自定义铃声使用前 60 秒。开启持续响铃后会重复到手动停止，关闭时最多提醒 3 分钟。首次请先用短计时测试。")) }
        }
        .navigationTitle(L("我的声音")).navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .movie]) { result in
            switch result {
            case .success(let url): startImport(url)
            case .failure(let failure): if (failure as NSError).code != NSUserCancelledError { error = failure.localizedDescription }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            importing = true
            task = Task {
                defer { importing = false; photo = nil }
                do {
                    guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else { throw MediaFailure.invalid }
                    defer { try? FileManager.default.removeItem(at: movie.url) }
                    _ = try await library.importFile(movie.url, name: L("相册视频"))
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
        }
        .alert(L("导入失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("知道了"), role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog(L("删除这个声音？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let sound = deleting {
                Button(L("删除声音"), role: .destructive) { remove(sound); deleting = nil }
            }
            Button(L("取消"), role: .cancel) { deleting = nil }
        } message: { Text(L("使用这个声音的配置将恢复为内置声音。")) }
        .onDisappear { task?.cancel() }
    }

    /// 使用媒体库中的声音，切换时停止已有试听。
    private func select(_ sound: PersonalSound, alarm: Bool) {
        store.stopPreview()
        if alarm { store.preferences.customAlarmID = sound.id; store.preferences.alarmSound = .custom }
        else { store.preferences.customSleepID = sound.id; store.preferences.sleepSound = .custom }
    }

    /// 发起可取消的导入，错误保留在当前页面。
    private func startImport(_ url: URL) {
        importing = true
        task = Task {
            defer { importing = false }
            do { _ = try await library.importFile(url) }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }

    /// 删除成功后重置引用该文件的选择，避免留下无法播放的配置。
    private func remove(_ sound: PersonalSound) {
        do {
            store.stopPreview()
            try library.remove(sound)
            if store.preferences.customSleepID == sound.id { store.preferences.sleepSound = .rain; store.preferences.customSleepID = nil }
            if store.preferences.customAlarmID == sound.id { store.preferences.alarmSound = .dawn; store.preferences.customAlarmID = nil }
        } catch { self.error = error.localizedDescription }
    }
}
