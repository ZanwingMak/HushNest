import XCTest
import StoreKit
import StoreKitTest
import SwiftUI
import UIKit
@testable import HushNest

@MainActor
final class SupportStoreTests: XCTestCase {
    private var session: SKTestSession!

    /// 使用本地 StoreKit 沙盒，禁止真实扣款并重置所有测试交易。
    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "HushNestTips")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    /// 验证真实 StoreKit 商品加载、一次性赞助及重复购买均可完成。
    func testConsumablePurchaseAndRepeat() async throws {
        let store = SupportStore()
        await store.load()
        let product = try XCTUnwrap(store.products.first)
        XCTAssertEqual(product.type, .consumable)
        await store.purchase(product)
        XCTAssertTrue(store.message == L("谢谢你的支持，让片刻安静继续生长。"))
        await store.purchase(product)
        XCTAssertTrue(store.message == L("谢谢你的支持，让片刻安静继续生长。"))
        XCTAssertFalse(store.busy)
        XCTAssertEqual(session.allTransactions().count, 2)
    }

    /// 验证四档消耗型商品按真实价格排序，且每档均可在本地沙盒完成赞助。
    func testEveryTipTierCanBePurchased() async throws {
        let store = SupportStore()
        await store.load()
        XCTAssertEqual(Set(store.products.map(\.id)), Set(SupportStore.productIDs))
        XCTAssertEqual(store.products.map(\.price), [Decimal(string: "0.99")!, Decimal(string: "2.99")!, Decimal(string: "5.99")!, Decimal(string: "9.99")!])
        for product in store.products {
            XCTAssertEqual(product.type, .consumable)
            await store.purchase(product)
            XCTAssertEqual(store.message, L("谢谢你的支持，让片刻安静继续生长。"))
        }
        XCTAssertEqual(session.allTransactions().count, 4)
    }

    /// 切换六种商店语言，验证四档商品的名称和说明均由 StoreKit 正确本地化。
    func testEveryTipTierHasSixLocalizations() async throws {
        let cases: [(String, [String], String)] = [
            ("zh_CN", ["一杯茶，支持耳憩", "一杯咖啡，支持耳憩", "一份甜点，支持耳憩", "一座小花园，支持耳憩"], "自愿一次性赞助开发，所有功能免费，没有订阅。"),
            ("zh_TW", ["一杯茶，支持耳憩", "一杯咖啡，支持耳憩", "一份甜點，支持耳憩", "一座小花園，支持耳憩"], "自願一次性贊助開發，所有功能免費，沒有訂閱。"),
            ("en_US", ["A cup of tea", "A cup of coffee", "A little dessert", "A little garden"], "Optional tip. Free features, no subscription."),
            ("ja", ["お茶で応援", "コーヒーで応援", "スイーツで応援", "小さな庭で応援"], "任意の1回きりの支援です。全機能無料、サブスクなし。"),
            ("ko", ["차 한 잔으로 응원", "커피 한 잔으로 응원", "디저트로 응원", "작은 정원으로 응원"], "선택하는 일회성 후원입니다. 모든 기능 무료, 구독 없음."),
            ("es_ES", ["Una taza de té", "Una taza de café", "Un pequeño postre", "Un pequeño jardín"], "Apoyo opcional. Todo gratis, sin suscripción.")
        ]
        for (locale, names, description) in cases {
            session.locale = Locale(identifier: locale)
            let store = SupportStore()
            await store.load()
            XCTAssertEqual(store.products.map(\.displayName), names, locale)
            XCTAssertEqual(store.products.map(\.description), Array(repeating: description, count: 4), locale)
        }
    }

    /// 验证 Apple 待批准购买与用户取消均不会被显示为赞助成功。
    func testPendingAndCancelledPurchase() async throws {
        let store = SupportStore()
        await store.load()
        let product = try XCTUnwrap(store.products.first)
        session.askToBuyEnabled = true
        await store.purchase(product)
        XCTAssertTrue(store.message == L("购买正在等待批准，批准后会自动完成。"))
        let pending = try XCTUnwrap(session.allTransactions().last(where: \.pendingAskToBuyConfirmation))
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        for _ in 0..<30 where store.message != L("谢谢你的支持，让片刻安静继续生长。") { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(store.message == L("谢谢你的支持，让片刻安静继续生长。"))
        session.askToBuyEnabled = false
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        await store.purchase(product)
        XCTAssertTrue(store.message == L("已取消，本次未完成赞助。"))
        XCTAssertFalse(store.busy)
    }

    /// 验证商店网络失败可恢复，失败不锁定按钮或影响免费功能。
    func testLoadFailureAndRetry() async throws {
        let store = SupportStore()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await store.load()
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(store.busy)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.load()
        XCTAssertEqual(store.products.count, 4)
    }
    /// 在真实应用窗口渲染本地沙盒商品，保留审核截图且不执行实际支付。
    func testSupportSheetRendersStoreKitProduct() async throws {
        let store = SupportStore()
        await store.load()
        XCTAssertEqual(store.products.count, 4)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previous = window.rootViewController
        defer { window.rootViewController = previous }
        let controller = UIHostingController(rootView: SupportSheet(support: store))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(1))
        controller.view.layoutIfNeeded()
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "15-support-storekit"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
