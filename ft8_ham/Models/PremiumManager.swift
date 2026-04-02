//
//  PremiumManager.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 26/02/26.
//

import StoreKit
import SwiftUI
import FirebaseAnalytics

/// Manages Premium one-time purchase and feature unlocking
@MainActor
class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    private let logger = AppLogger(category: "PREMIUM")

    // MARK: - Product IDs
    static let premiumProductID = "ft_ham_premium"

    // Donation (consumable) product IDs — any verified donation also grants premium
    static let donationProductIDs: Set<String> = ["coffe_small", "coffe_medium", "coffee_large"]

    // MARK: - Published State
    @Published private(set) var isPremiumUnlocked: Bool = false
    @Published private(set) var premiumProduct: Product?
    @Published private(set) var isLoading: Bool = false

    // MARK: - Transaction Listener
    private var transactionListener: Task<Void, Never>?

    private init() {
        // Start listening for transactions on init
        transactionListener = listenForTransactions()

        Task {
            await loadPremiumStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Premium Status

    /// Grants premium if the user has purchased the premium product OR made any donation.
    /// - Premium product (non-consumable): checked via `Transaction.currentEntitlements`
    /// - Donations (consumable): checked via `Transaction.all` (consumables don't appear in entitlements)
    func loadPremiumStatus() async {
        logger.info("Loading premium status...")
        
        #if DEBUG
        logger.info("Debug build - enabling premium")
        isPremiumUnlocked = true
        #else
        // 1. Check non-consumable premium product via entitlements
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result,
               transaction.productID == Self.premiumProductID {
                logger.info("Premium unlocked via premium product: \(transaction.id)")
                isPremiumUnlocked = true
                return
            }
        }

        // 2. Check consumable donations — any verified donation also grants premium
        for await result in Transaction.all {
            if case let .verified(transaction) = result,
               Self.donationProductIDs.contains(transaction.productID) {
                logger.info("Premium unlocked via donation: \(transaction.productID)")
                isPremiumUnlocked = true
                return
            }
        }


        logger.info("No qualifying purchase found — premium not unlocked")
        isPremiumUnlocked = false
        #endif

    }

    // MARK: - Fetch Product

    /// Load the premium product from App Store
    func fetchPremiumProduct() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [Self.premiumProductID])

            if let product = products.first {
                premiumProduct = product
                logger.info("Premium product loaded: \(product.displayName) - \(product.displayPrice)")
            } else {
                logger.error("Premium product not found in App Store Connect")
            }
        } catch {
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
            AnalyticsManager.shared.logPremiumPurchase(price: product.price, currency: product.priceFormatStyle.currencyCode)

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
                    let isDonationTx = Self.donationProductIDs.contains(transaction.productID)

                    if isPremiumTx || isDonationTx {
                        logger.info("Transaction update received: \(transaction.productID)")
                        isPremiumUnlocked = true
                        await transaction.finish()
                    }
                }
            }
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
            return "Premium product is not loaded. Please try again."
        case .userCancelled:
            return "Purchase was cancelled."
        case .pending:
            return "Purchase is pending approval."
        case .verificationFailed:
            return "Purchase verification failed. Please contact support."
        case .noPurchaseToRestore:
            return "No previous purchase found to restore."
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

// MARK: - Analytics Extension

extension AnalyticsManager {
    func logPremiumPurchase(price: Decimal, currency: String?) {
        Analytics.logEvent("premium_purchased", parameters: [
            "price": NSDecimalNumber(decimal: price),
            "currency": currency ?? "USD"
        ])
    }

    func logPremiumRestore() {
        Analytics.logEvent("premium_restored", parameters: nil)
    }

    func logPremiumPaywallShown(source: String) {
        Analytics.logEvent("premium_paywall_shown", parameters: ["source": source])
    }
}
