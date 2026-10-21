import SwiftUI

enum Palette {
    static let accent = Color("AccentColor")
    static let background = Color("LaunchBackground")
    static let card = Color("CardBackground")
    static let onAccent = Color("OnAccent")
    static let ink = Color.primary
}

struct NestCard<Content: View>: View {
    @Environment(\.nestTheme) private var theme
    let content: Content
    /// 以统一的间距和材质包裹卡片内容。
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct NestButtonStyle: ButtonStyle {
    @Environment(\.nestTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var secondary = false
    /// 保留系统按钮语义，同时为按下状态提供清晰的视觉反馈。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(secondary ? theme.accent : Palette.onAccent)
            .background(secondary ? theme.accent.opacity(0.1) : theme.accent, in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct SectionCaption: View {
    @Environment(\.nestTheme) private var theme
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct NestThemeKey: EnvironmentKey { static let defaultValue = AppTheme.forest }
extension EnvironmentValues {
    var nestTheme: AppTheme {
        get { self[NestThemeKey.self] }
        set { self[NestThemeKey.self] = newValue }
    }
}

extension AppTheme {
    var accent: Color {
        switch self {
        case .forest: Palette.accent
        case .ocean: adaptive(light: 0x235B78, dark: 0x9DCFE8)
        case .dusk: adaptive(light: 0x69507E, dark: 0xD6B9EB)
        case .rose: adaptive(light: 0x8B455B, dark: 0xF0B8C8)
        }
    }
    var background: Color {
        switch self {
        case .forest: Palette.background
        case .ocean: adaptive(light: 0xF1F6F8, dark: 0x101C24)
        case .dusk: adaptive(light: 0xF6F2F8, dark: 0x1D1726)
        case .rose: adaptive(light: 0xFAF2F3, dark: 0x25181D)
        }
    }
    var card: Color { self == .forest ? Palette.card : adaptive(light: 0xFFFFFF, dark: 0x2B2D34) }

    /// 依系统明暗外观提供主题颜色，保持前景文字可读。
    private func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct BreathingMark: View {
    @Environment(\.nestTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 36, weight: .light))
            .foregroundStyle(theme.accent)
            .scaleEffect(expanded && !reduceMotion ? 1.12 : 1)
            .opacity(expanded && !reduceMotion ? 0.75 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: expanded)
            .onAppear { expanded = true }
            .accessibilityHidden(true)
    }
}
