//
//  PremiumManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 02/04/26.
//

import StoreKit
import SwiftUI
import Security
import FirebaseAnalytics

/// Manages Premium one-time purchase and feature unlocking
@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    private let logger = AppLogger(category: "PREMIUM")

    // MARK: - Product IDs
    static let premiumProductID = "premium_ftham"

    // Beta access granted via promo offer code FTHAMBETAUSER
    static let betaProductID = "beta_users"

    // Donation (consumable) tip product IDs. Tips are optional and never unlock premium,
    // except tips bought before `legacyDonationCutoff` (see `isLegacyDonation`).
    static let donationProductIDs: Set<String> = ["coffe_small", "coffe_medium", "coffee_large"]

    /// Tips bought before this moment came from 1.2.x, where the tip sheet was the only
    /// way to support the app, so those donors get premium. 1.3.0 went live on 4 Nov 2026
    /// with a 7-day phased release, so the cutoff is the end of that rollout.
    static let legacyDonationCutoff: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 11
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    /// Where loading the premium product stands, so the paywall can offer a retry
    /// instead of spinning forever when the App Store does not answer.
    enum ProductLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    // MARK: - Published State
    @Published private(set) var isPremiumUnlocked: Bool = false
    @Published private(set) var premiumProduct: Product?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var productLoadState: ProductLoadState = .idle

    private let fetcher: ProductFetching

    /// Tips bought before this unlock premium. `legacyDonationCutoff` unless a test injects one.
    private let donationCutoff: Date

    /// Whether the user redeemed a beta access offer code.
    @Published private(set) var isBetaUser: Bool = false

    /// Whether premium comes from a tip bought before `legacyDonationCutoff`.
    @Published private(set) var isLegacyDonor: Bool = false

    #if DEBUG
    /// Debug-only override: when true, premium is treated as unlocked regardless of purchases.
    @Published private(set) var debugPremiumEnabled: Bool = UserDefaults.standard.bool(forKey: "debug_premium_enabled")
    #endif

    // MARK: - Keychain
    /// Written by 1.3.0 beta builds, when tips unlocked premium. Only ever deleted now.
    private static let legacyDonationKeychainKey = "com.ea4iql.ftham.donation.granted"

    // MARK: - Transaction Listener
    private var transactionListener: Task<Void, Never>?

    /// - Parameters:
    ///   - fetcher: Loads the premium product. Tests inject a stub.
    ///   - observesTransactions: When false, skips the transaction listener, the
    ///     legacy Keychain cleanup and the entitlement check, so tests stay deterministic.
    ///   - donationCutoff: Tips bought before this unlock premium. Tests move it to
    ///     cover tips bought in a StoreKit test session, which are always dated now.
    init(
        fetcher: ProductFetching = StoreKitProductFetcher(),
        observesTransactions: Bool = true,
        donationCutoff: Date = PremiumManager.legacyDonationCutoff
    ) {
        self.fetcher = fetcher
        self.donationCutoff = donationCutoff
        guard observesTransactions else { return }

        // Start listening for transactions on init
        transactionListener = listenForTransactions()
        Self.removeLegacyDonationKeychainFlag()

        Task {
            await loadPremiumStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Premium Status

    /// Grants premium if the user owns the premium product or redeemed beta access,
    /// both checked via `Transaction.currentEntitlements`, or tipped before
    /// `legacyDonationCutoff`, checked via `Transaction.all`.
    func loadPremiumStatus() async {
        logger.info("Loading premium status...")

        #if DEBUG
        if debugPremiumEnabled {
            logger.info("Debug override active - premium enabled")
            isPremiumUnlocked = true
            return
        }
        logger.info("Debug override inactive - checking real purchases")
        #endif

        let previouslyUnlocked = isPremiumUnlocked

        // Non-consumable products via entitlements
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result {
                if transaction.productID == Self.premiumProductID {
                    logger.info("Premium unlocked via premium product: \(transaction.id)")
                    isPremiumUnlocked = true
                    return
                }
                if transaction.productID == Self.betaProductID {
                    logger.info("Premium unlocked via beta access: \(transaction.id)")
                    isBetaUser = true
                    isPremiumUnlocked = true
                    return
                }
            }
        }

        // Finished consumables only show up in `Transaction.all` on iOS 18+, and only
        // with SKIncludeConsumableInAppPurchaseHistory in Info.plist. Earlier systems
        // see nothing here, and those donors ask for an offer code instead.
        for await result in Transaction.all {
            if case let .verified(transaction) = result,
               Self.isLegacyDonation(
                   productID: transaction.productID,
                   purchaseDate: transaction.purchaseDate,
                   revocationDate: transaction.revocationDate,
                   cutoff: donationCutoff
               ) {
                logger.info("Premium unlocked via legacy donation: \(transaction.id)")
                isLegacyDonor = true
                isPremiumUnlocked = true
                return
            }
        }

        logger.info("No qualifying purchase found — premium not unlocked")
        isPremiumUnlocked = false
        isBetaUser = false
        isLegacyDonor = false

        // Notify owning models to clean up premium-gated settings only on actual revocation
        if previouslyUnlocked {
            NotificationCenter.default.post(name: .premiumRevoked, object: nil)
        }
    }

    /// Whether owning `productID` unlocks premium. Only the premium product and
    /// beta access do. Tips (`donationProductIDs`) are optional and unlock nothing.
    static func grantsPremium(productID: String) -> Bool {
        productID == premiumProductID || productID == betaProductID
    }

    /// Whether a transaction is a tip from before `legacyDonationCutoff` that was
    /// not refunded. Those donors keep premium. Later tips unlock nothing.
    static func isLegacyDonation(
        productID: String,
        purchaseDate: Date,
        revocationDate: Date?,
        cutoff: Date = legacyDonationCutoff
    ) -> Bool {
        donationProductIDs.contains(productID) && revocationDate == nil && purchaseDate < cutoff
    }

    // MARK: - Fetch Product

    /// Load the premium product from App Store
    func fetchPremiumProduct() async {
        guard premiumProduct == nil else {
            productLoadState = .loaded
            return
        }
        isLoading = true
        productLoadState = .loading
        defer { isLoading = false }

        do {
            let products = try await fetcher.fetchProducts(for: [Self.premiumProductID])

            if let product = products.first {
                premiumProduct = product
                productLoadState = .loaded
                logger.info("Premium product loaded: \(product.displayName) - \(product.displayPrice)")
            } else {
                productLoadState = .failed
                logger.error("Premium product not found in App Store Connect")
            }
        } catch {
            productLoadState = .failed
            logger.error("Failed to fetch premium product: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    /// Purchase premium (one-time payment)
    func purchasePremium() async throws {
        guard let product = premiumProduct else {
            logger.error("Cannot purchase: product not loaded")
            throw PremiumError.productNotLoaded
        }

        logger.info("Initiating purchase for: \(product.id)")

        let result = try await product.purchase()

        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)

            // Grant premium access
            isPremiumUnlocked = true

            // Finish the transaction
            await transaction.finish()

            logger.info("Purchase successful! Premium unlocked.")
            AnalyticsManager.shared.logPurchaseCompleted(
                productID: product.id,
                value: NSDecimalNumber(decimal: product.price).doubleValue,
                currency: product.priceFormatStyle.currencyCode
            )

        case .userCancelled:
            logger.info("Purchase cancelled by user")
            throw PremiumError.userCancelled

        case .pending:
            logger.info("Purchase pending (awaiting authorization)")
            throw PremiumError.pending

        @unknown default:
            logger.error("Unknown purchase result")
            throw PremiumError.unknown
        }
    }

    // MARK: - Restore Purchases

    /// Restore premium purchase (for new devices or reinstalls)
    func restorePurchases() async throws {
        logger.info("Restoring purchases...")

        try await AppStore.sync()
        await loadPremiumStatus()

        if isPremiumUnlocked {
            logger.info("Premium restored successfully")
            AnalyticsManager.shared.logPremiumRestore()
        } else {
            logger.info("No premium purchase found to restore")
            throw PremiumError.noPurchaseToRestore
        }
    }

    // MARK: - Transaction Listener

    /// Listen for transaction updates (purchases made outside the app, or deferred purchases completing)
    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { @MainActor in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    let isPremiumTx = transaction.productID == Self.premiumProductID
                    let isBetaTx = transaction.productID == Self.betaProductID
                    let isDonationTx = Self.donationProductIDs.contains(transaction.productID)

                    // Tips completing outside purchase() (Ask to Buy, interrupted purchases)
                    // are logged and finished. Only a refund can change premium state, for
                    // a donor whose premium came from that tip.
                    if isDonationTx {
                        if transaction.revocationDate == nil {
                            logExternalPurchase(transaction)
                        }
                        await transaction.finish()
                        if transaction.revocationDate != nil && isLegacyDonor {
                            await loadPremiumStatus()
                        }
                        continue
                    }

                    if Self.grantsPremium(productID: transaction.productID) {
                        // Check for refund / subscription expiry
                        if transaction.revocationDate != nil {
                            logger.info("Revoked transaction detected: \(transaction.productID)")
                            await transaction.finish()
                            await loadPremiumStatus()
                            continue
                        }

                        logger.info("Transaction update received: \(transaction.productID)")
                        if isBetaTx {
                            isBetaUser = true
                        }
                        isPremiumUnlocked = true

                        // Log revenue for purchases completing outside the direct purchase() call
                        // (Ask to Buy approval, family sharing, cross-device sync). Excludes beta
                        // access, which is a promotional grant rather than a paid transaction.
                        if isPremiumTx {
                            logExternalPurchase(transaction)
                        }

                        await transaction.finish()
                    }
                }
            }
        }
    }

    /// Logs purchase revenue for a transaction we didn't originate via a direct purchase() call.
    /// `Transaction.price`/`currency` reflect what was actually paid (unlike `Product.price`,
    /// which is the catalog price and would misreport promo/offer-code discounts).
    private func logExternalPurchase(_ transaction: StoreKit.Transaction) {
        if #available(iOS 17.0, *) {
            AnalyticsManager.shared.logPurchaseCompleted(
                productID: transaction.productID,
                value: transaction.price.map { NSDecimalNumber(decimal: $0).doubleValue },
                currency: transaction.currency?.identifier
            )
        } else {
            AnalyticsManager.shared.logPurchaseCompleted(productID: transaction.productID)
        }
    }

    // MARK: - Verification Helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            logger.error("Transaction verification failed: \(error.localizedDescription)")
            throw PremiumError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Keychain Helpers

    /// Deletes the donation grant that 1.3.0 beta builds stored (locally and in
    /// iCloud Keychain). Harmless when the item does not exist.
    private static func removeLegacyDonationKeychainFlag() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: legacyDonationKeychainKey,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Debug Helpers

    #if DEBUG
    /// Toggle premium on/off for debugging. Persists across launches.
    func setDebugPremium(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "debug_premium_enabled")
        debugPremiumEnabled = enabled
        Task { await loadPremiumStatus() }
    }
    #endif
}

// MARK: - Notification Names

extension Notification.Name {
    static let premiumRevoked = Notification.Name("com.ea4iql.ftham.premiumRevoked")
}

// MARK: - Premium Errors

enum PremiumError: LocalizedError {
    case productNotLoaded
    case userCancelled
    case pending
    case verificationFailed
    case noPurchaseToRestore
    case unknown

    var errorDescription: String? {
        switch self {
        case .productNotLoaded:
            return String(localized: "Premium product is not loaded. Please try again.")
        case .userCancelled:
            return String(localized: "Purchase was cancelled.")
        case .pending:
            return String(localized: "Purchase is pending approval.")
        case .verificationFailed:
            return String(localized: "Purchase verification failed. Please contact support.")
        case .noPurchaseToRestore:
            return String(localized: "No previous purchase found to restore.")
        case .unknown:
            return String(localized: "An unknown error occurred.")
        }
    }
}

// MARK: - Analytics Extension

extension AnalyticsManager {
    func logPremiumRestore() {
        logEvent("premium_restored")
    }

    func logPremiumPaywallShown(source: String) {
        logEvent("premium_paywall_shown", parameters: ["source": source])
    }
}
