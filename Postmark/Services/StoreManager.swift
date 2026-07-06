import Foundation
import StoreKit
import Observation

/// StoreKit 2 manager: loads the two Postmark Pro subscriptions, handles
/// purchases, keeps the entitlement flag fresh, and gates the free tier
/// (3 lifetime free scans tracked in UserDefaults).
@Observable
final class StoreManager {

    static let monthlyProductID = "postmark_pro_monthly"
    static let yearlyProductID = "postmark_pro_yearly"
    static let productIDs: Set<String> = [monthlyProductID, yearlyProductID]

    static let freeScanLimit = 3
    private static let freeScansUsedKey = "postmark.freeScansUsed"

    private(set) var products: [Product] = []
    /// "Pro" = either subscription currently entitled.
    private(set) var isPro = false
    private(set) var isLoadingProducts = false
    private(set) var lastErrorMessage: String?

    private(set) var freeScansUsed: Int {
        didSet { UserDefaults.standard.set(freeScansUsed, forKey: Self.freeScansUsedKey) }
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        freeScansUsed = UserDefaults.standard.integer(forKey: Self.freeScansUsedKey)

        // Listen for transactions that arrive outside a purchase flow
        // (renewals, Ask to Buy approvals, purchases on other devices).
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }

        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: Free-tier gate

    var freeScansRemaining: Int { max(0, Self.freeScanLimit - freeScansUsed) }

    var canScan: Bool { isPro || freeScansRemaining > 0 }

    /// Call once per successful scan RESULT. No-op for Pro users.
    func recordScan() {
        guard !isPro else { return }
        freeScansUsed += 1
    }

    // MARK: Products

    @MainActor
    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Monthly first, yearly second.
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            lastErrorMessage = "Could not load products: \(error.localizedDescription)"
        }
    }

    // MARK: Purchase

    @MainActor
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlements()
                return isPro
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }

    // MARK: Entitlements

    @MainActor
    func refreshEntitlements() async {
        var pro = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                pro = true
            }
        }
        isPro = pro
    }
}
