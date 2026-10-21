import Foundation

/// 本地化动态文案；SwiftUI 字面量继续使用同一 Localizable 资源。
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// 用占位符格式化动态文案，允许不同语言调整词序。
func LF(_ key: String, _ values: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: values)
}
