import Foundation
import StoreKit

/// Floor Age Plus: one non-consumable in-app purchase that unlocks the extra features for good.
/// StoreKit 2 checks the signed transactions on the device, so there is no server of our own; the
/// purchase itself goes through Apple. The product is set up in App Store Connect under
/// `Store.plusID`, and `FloorAge.storekit` mirrors it for testing in Xcode without real money.
@MainActor
final class Store: ObservableObject {
    nonisolated static let plusID = "com.jeyaraj.floorage.plus"

    @Published private(set) var hasPlus: Bool
    @Published private(set) var product: Product?
    @Published private(set) var busy = false

    private var updates: Task<Void, Never>?
    private let isPreview: Bool

    /// `preview` fixes the state for screenshots and tests, without touching StoreKit.
    init(preview: Bool? = nil) {
        isPreview = preview != nil
        // Remembered so the app opens already unlocked; StoreKit confirms it a moment later.
        hasPlus = preview ?? UserDefaults.standard.bool(forKey: "hasPlus")
        guard preview == nil else { return }
        updates = Task { [weak self] in
            // Purchases made elsewhere: another device, Family Sharing, Ask to Buy approvals, refunds.
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await refreshEntitlement()
            await loadProduct()
        }
    }

    deinit { updates?.cancel() }

    /// The local price ("$4.99", "₹299"), once the App Store has answered.
    var price: String? {
        product?.displayPrice ?? (isPreview ? "$4.99" : nil)
    }

    func loadProduct() async {
        guard !isPreview, product == nil else { return }
        product = try? await Product.products(for: [Self.plusID]).first
    }

    /// Buys Plus. Returns a message to show the person, or nil when there's nothing to say
    /// (success is visible as `hasPlus`, and cancelling needs no comment).
    func purchase() async -> String? {
        guard let product, !busy else { return nil }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
                if case .unverified = result {
                    return String(localized: "The App Store couldn't confirm this purchase. Please try Restore Purchases.")
                }
                return nil
            case .pending:
                return String(localized: "Your purchase is waiting for approval. Plus unlocks as soon as it's approved.")
            case .userCancelled:
                return nil
            @unknown default:
                return nil
            }
        } catch {
            return String(localized: "The purchase didn't go through. Please try again.")
        }
    }

    /// Asks the App Store for this Apple Account's purchases again (App Review requires a
    /// Restore Purchases button). Returns a message to show the person.
    func restore() async -> String? {
        guard !isPreview, !busy else { return nil }
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
        } catch {
            return String(localized: "Couldn't reach the App Store. Check your connection and try again.")
        }
        await refreshEntitlement()
        return hasPlus
            ? String(localized: "Floor Age Plus is restored. Welcome back!")
            : String(localized: "No earlier purchase of Floor Age Plus was found for this Apple Account.")
    }

    func refreshEntitlement() async {
        guard !isPreview else { return }
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.unlocks(transaction.productID, revoked: transaction.revocationDate != nil) {
                owned = true
            }
        }
        setPlus(owned)
    }

    /// Whether a transaction for `productID` grants Plus. Refunded (revoked) purchases don't.
    nonisolated static func unlocks(_ productID: String, revoked: Bool) -> Bool {
        productID == plusID && !revoked
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        // Only transactions signed by the App Store count.
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.plusID {
            setPlus(Self.unlocks(transaction.productID, revoked: transaction.revocationDate != nil))
        }
        await transaction.finish()
    }

    private func setPlus(_ value: Bool) {
        hasPlus = value
        UserDefaults.standard.set(value, forKey: "hasPlus")
    }
}
