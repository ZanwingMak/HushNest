import SwiftUI
import AVKit

struct RoutePicker: UIViewRepresentable {
    /// 使用系统输出选择器，用户自行选择 AirPods；不尝试强制配对设备。
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .label
        return view
    }
    /// 路由由系统管理，无需在视图刷新时重新创建。
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
