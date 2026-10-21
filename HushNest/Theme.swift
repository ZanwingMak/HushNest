import SwiftUI

enum Palette {
    static let accent = Color("AccentColor")
    static let background = Color("LaunchBackground")
    static let card = Color("CardBackground")
    static let onAccent = Color("OnAccent")
    static let ink = Color.primary
}

struct NestCard<Content: View>: View {
    let content: Content
    /// 以统一的间距和材质包裹卡片内容。
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct NestButtonStyle: ButtonStyle {
    var secondary = false
    /// 保留系统按钮语义，同时为按下状态提供清晰的视觉反馈。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).frame(minHeight: 54)
            .foregroundStyle(secondary ? Palette.accent : Palette.onAccent)
            .background(secondary ? Palette.accent.opacity(0.1) : Palette.accent, in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct SectionCaption: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
