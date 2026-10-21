import SwiftUI
import AudioToolbox

@main
struct HushNestApp: App {
    @StateObject private var library: MediaLibrary
    @StateObject private var store: RestStore
    @StateObject private var support: SupportStore
    @Environment(\.scenePhase) private var phase

    /// 生产构建只使用真实耳机；Debug UI 自动化使用完全无声的音频替身。
    init() {
        _library = StateObject(wrappedValue: Self.makeLibrary())
        _support = StateObject(wrappedValue: SupportStore())
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let defaults = UserDefaults(suiteName: "HushNest.UITests")!
            if !ProcessInfo.processInfo.arguments.contains("-keep-data") {
                defaults.removePersistentDomain(forName: "HushNest.UITests")
            }
            let audio = PreviewAudio()
            if ProcessInfo.processInfo.arguments.contains("-no-headphones") { audio.isHeadphoneConnected = false }
            _store = StateObject(wrappedValue: RestStore(audio: audio, defaults: defaults, notificationsEnabled: false))
            return
        }
        #endif
        _store = StateObject(wrappedValue: RestStore(audio: HeadphoneAudio(), vibrate: { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }))
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(support).environmentObject(library)
                .environment(\.nestTheme, store.theme)
                .tint(store.theme.accent)
                .preferredColorScheme(testAppearance)
                .onChange(of: phase) { _, newValue in
                    if newValue == .active { store.becameActive() }
                    if newValue == .background { store.enteredBackground() }
                }
        }
    }

    /// UI 测试使用隔离媒体库，可导入真实样本但始终不播放。
    private static func makeLibrary() -> MediaLibrary {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            let directory = URL.applicationSupportDirectory.appendingPathComponent("TestSounds")
            if !arguments.contains("-keep-data") { try? FileManager.default.removeItem(at: directory) }
            let library = MediaLibrary(directory: directory)
            if arguments.contains("-seed-media"), library.sounds.isEmpty {
                Task { _ = try? await library.importFile(Bundle.main.url(forResource: "bell", withExtension: "wav")!, name: "My test sound") }
            }
            return library
        }
        #endif
        return MediaLibrary()
    }

    private var testAppearance: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dark-appearance") { return .dark }
        #endif
        return nil
    }
}
