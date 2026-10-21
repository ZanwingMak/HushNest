import SwiftUI

@main
struct HushNestApp: App {
    @StateObject private var store: RestStore
    @Environment(\.scenePhase) private var phase

    /// 生产构建只使用真实耳机；Debug UI 自动化使用完全无声的音频替身。
    init() {
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
        _store = StateObject(wrappedValue: RestStore(audio: HeadphoneAudio()))
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Palette.accent)
                .preferredColorScheme(testAppearance)
                .onChange(of: phase) { _, newValue in
                    if newValue == .active { store.becameActive() }
                }
        }
    }

    private var testAppearance: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dark-appearance") { return .dark }
        #endif
        return nil
    }
}
