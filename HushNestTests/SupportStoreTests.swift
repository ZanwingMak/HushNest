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
        XCTAssertTrue(store.message?.contains("谢谢") == true)
        await store.purchase(product)
        XCTAssertTrue(store.message?.contains("谢谢") == true)
        XCTAssertFalse(store.busy)
        XCTAssertEqual(session.allTransactions().count, 2)
    }

    /// 验证 Apple 待批准购买与用户取消均不会被显示为赞助成功。
    func testPendingAndCancelledPurchase() async throws {
        let store = SupportStore()
        await store.load()
        let product = try XCTUnwrap(store.products.first)
        session.askToBuyEnabled = true
        await store.purchase(product)
        XCTAssertTrue(store.message?.contains("等待批准") == true)
        let pending = try XCTUnwrap(session.allTransactions().last(where: \.pendingAskToBuyConfirmation))
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        for _ in 0..<30 where store.message?.contains("谢谢") != true { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(store.message?.contains("谢谢") == true)
        session.askToBuyEnabled = false
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        await store.purchase(product)
        XCTAssertTrue(store.message?.contains("取消") == true)
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
        XCTAssertEqual(store.products.count, 1)
    }
    /// 在真实应用窗口渲染本地沙盒商品，保留审核截图且不执行实际支付。
    func testSupportSheetRendersStoreKitProduct() async throws {
        let store = SupportStore()
        await store.load()
        XCTAssertEqual(store.products.count, 1)
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
