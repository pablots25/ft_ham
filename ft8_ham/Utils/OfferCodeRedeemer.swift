//
//  OfferCodeRedeemer.swift
//  ft_ham
//

import StoreKit
import UIKit

/// Opens Apple's sheet for redeeming an App Store offer code inside the app,
/// so a past donor does not have to go through the App Store to use the code
/// we send them. A redeemed code arrives through `Transaction.updates`, which
/// `PremiumManager` already listens to, so premium unlocks without a restore.
enum OfferCodeRedeemer {

    enum RedeemError: LocalizedError {
        case noActiveScene

        var errorDescription: String? {
            String(localized: "Couldn't open the code screen. Try again.")
        }
    }

    @MainActor
    static func present() async throws {
        guard let scene = activeScene() else { throw RedeemError.noActiveScene }
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }

    @MainActor
    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
