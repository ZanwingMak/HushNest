import StoreKit
import SwiftUI

@MainActor
final class SupportStore: ObservableObject {
    static let productIDs = ["com.zanwingmak.HushNest.tip.tea"]
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var updates: Task<Void, Never>?

    /// 持续完成已经由 Apple 验证的赞助交易，处理中断后补发的结果。
    init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.unfinished {
                await self?.complete(result)
            }
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.complete(result)
            }
        }
    }

    /// 完成已验证的赞助交易，包括购买中途关闭页面或重启后的补发结果。
    private func complete(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result,
              Self.productIDs.contains(transaction.productID) else { return }
        await transaction.finish()
        message = "谢谢你的支持，让片刻安静继续生长。"
    }

    /// 从 Apple 获取本地化价格，不展示虚构价格或未配置的商品。
    func load() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            if products.isEmpty { message = "赞助暂未开放或商店暂不可用。所有功能仍可免费使用，请稍后重试。" }
        } catch { message = "无法连接 App Store，请检查网络后重试。" }
    }

    /// 仅在用户选中真实商品后打开 Apple 支付确认，并分别处理待批准、取消和验证失败。
    func purchase(_ product: Product) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    message = "谢谢你的支持，让片刻安静继续生长。"
                case .unverified:
                    message = "交易暂未通过验证，请稍后查看 Apple 购买记录。"
                }
            case .pending: message = "购买正在等待批准，批准后会自动完成。"
            case .userCancelled: message = "已取消，本次未完成赞助。"
            @unknown default: message = "请稍后查看 Apple 购买记录确认交易状态。"
            }
        } catch { message = "购买未完成：\(error.localizedDescription)" }
    }

    deinit { updates?.cancel() }
}

struct SupportSheet: View {
    @StateObject private var support: SupportStore
    @Environment(\.dismiss) private var dismiss
    /// 注入商店状态，界面与本地 StoreKit 沙盒使用相同商品展示流程。
    init(support: SupportStore) { _support = StateObject(wrappedValue: support) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "heart").font(.largeTitle)
                        Text("让安静，继续生长。").font(.title2.weight(.semibold))
                        Text("如果耳憩帮到了你，可以请开发者喝杯茶。赞助完全自愿，每次都是一次性内购；没有订阅，也不会解锁额外功能。")
                    }.padding(.vertical, 12)
                }
                Section("自愿赞助") {
                    ForEach(support.products) { product in
                        Button {
                            Task { await support.purchase(product) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(product.displayName)
                                    Text(product.description).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice).fontWeight(.semibold)
                            }.frame(minHeight: 48)
                        }.disabled(support.busy).accessibilityIdentifier("support.\(product.id)")
                    }
                    if support.busy { ProgressView("正在连接 App Store…") }
                    if let message = support.message { Text(message).font(.subheadline).accessibilityIdentifier("support.message") }
                    if support.products.isEmpty && !support.busy {
                        Button("重新加载") { Task { await support.load() } }.accessibilityIdentifier("support.reload")
                    }
                }
                Section {
                    Text("赞助为可重复购买的消耗型内购，没有需恢复的功能或权益。交易由 Apple 处理；我们不接收你的支付信息。退款请通过 Apple 的“报告问题”申请。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Apple 购买与退款", destination: URL(string: "https://reportaproblem.apple.com/")!)
                }
            }.navigationTitle("支持耳憩").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.accessibilityIdentifier("support.done") } }
                .task { await support.load() }
        }
    }
}
