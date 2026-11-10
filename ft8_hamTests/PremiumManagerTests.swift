//
//  PremiumManagerTests.swift
//  ft8_hamTests
//
//  Tests for PremiumManager business logic, PremiumError, PaywallSource, and
//  the new PremiumFeature paywall properties added in the premium improvements refactor.
//

import XCTest
import Combine
import StoreKit
import StoreKitTest
@testable import ft8_ham

// MARK: - PremiumError

final class PremiumErrorTests: XCTestCase {

    func test_productNotLoaded_hasDescription() {
        XCTAssertNotNil(PremiumError.productNotLoaded.errorDescription)
        XCTAssertFalse(PremiumError.productNotLoaded.errorDescription!.isEmpty)
    }

    func test_userCancelled_hasDescription() {
        XCTAssertNotNil(PremiumError.userCancelled.errorDescription)
        XCTAssertFalse(PremiumError.userCancelled.errorDescription!.isEmpty)
    }

    func test_pending_hasDescription() {
        XCTAssertNotNil(PremiumError.pending.errorDescription)
        XCTAssertFalse(PremiumError.pending.errorDescription!.isEmpty)
    }

    func test_verificationFailed_hasDescription() {
        XCTAssertNotNil(PremiumError.verificationFailed.errorDescription)
        XCTAssertFalse(PremiumError.verificationFailed.errorDescription!.isEmpty)
    }

    func test_noPurchaseToRestore_hasDescription() {
        XCTAssertNotNil(PremiumError.noPurchaseToRestore.errorDescription)
        XCTAssertFalse(PremiumError.noPurchaseToRestore.errorDescription!.isEmpty)
    }

    func test_unknown_hasDescription() {
        XCTAssertNotNil(PremiumError.unknown.errorDescription)
        XCTAssertFalse(PremiumError.unknown.errorDescription!.isEmpty)
    }

    func test_allCasesHaveUniqueDescriptions() {
        let descriptions = [
            PremiumError.productNotLoaded.errorDescription,
            PremiumError.userCancelled.errorDescription,
            PremiumError.pending.errorDescription,
            PremiumError.verificationFailed.errorDescription,
            PremiumError.noPurchaseToRestore.errorDescription,
            PremiumError.unknown.errorDescription
        ]
        let unique = Set(descriptions.compactMap { $0 })
        XCTAssertEqual(unique.count, 6, "Each PremiumError case must have a unique description")
    }
}

// MARK: - PaywallSource

final class PaywallSourceTests: XCTestCase {

    func test_featureSource_returnsFeatureRawValue() {
        let source = PaywallSource.feature(.statistics)
        XCTAssertEqual(source.analyticsValue, "statistics")
    }

    func test_featureSource_catControl() {
        XCTAssertEqual(PaywallSource.feature(.catControl).analyticsValue, "cat_control")
    }

    func test_featureSource_pskReporter() {
        XCTAssertEqual(PaywallSource.feature(.pskReporter).analyticsValue, "psk_reporter")
    }

    func test_screenSource_returnsLiteralString() {
        let source = PaywallSource.screen("configuration")
        XCTAssertEqual(source.analyticsValue, "configuration")
    }

    func test_screenSource_emptyString() {
        let source = PaywallSource.screen("")
        XCTAssertEqual(source.analyticsValue, "")
    }

    func test_allFeaturesHaveValidAnalyticsValues() {
        for feature in PremiumFeature.allCases {
            let value = PaywallSource.feature(feature).analyticsValue
            XCTAssertEqual(value, feature.rawValue, "PaywallSource.feature(\(feature)) must return feature.rawValue")
        }
    }
}

// MARK: - PremiumFeature paywall properties

final class PremiumFeaturePaywallPropertiesTests: XCTestCase {

    func test_allCasesHaveNonEmptyPaywallDescription() {
        for feature in PremiumFeature.allCases {
            XCTAssertFalse(
                feature.paywallDescription.isEmpty,
                "\(feature) must have a non-empty paywallDescription"
            )
        }
    }

    func test_allCasesHaveNonEmptyDisplayName() {
        for feature in PremiumFeature.allCases {
            XCTAssertFalse(
                feature.displayName.isEmpty,
                "\(feature) must have a non-empty displayName"
            )
        }
    }

    func test_allCasesHaveNonEmptyIcon() {
        for feature in PremiumFeature.allCases {
            XCTAssertFalse(
                feature.icon.isEmpty,
                "\(feature) must have a non-empty SF Symbol name"
            )
        }
    }

    func test_allCasesHaveUniquePaywallDescriptions() {
        let descriptions = PremiumFeature.allCases.map(\.paywallDescription)
        let unique = Set(descriptions)
        XCTAssertEqual(unique.count, PremiumFeature.allCases.count, "Each feature must have a unique paywall description")
    }

    func test_countIsTenFeatures() {
        XCTAssertEqual(PremiumFeature.allCases.count, 10)
    }

    func test_featureFlag_mapsRemotelyGatedFeatures() {
        XCTAssertEqual(PremiumFeature.iPadDashboard.featureFlag, .enableIpadDashboard)
        XCTAssertEqual(PremiumFeature.bandHopping.featureFlag, .enableBandHopping)
        XCTAssertEqual(PremiumFeature.iCloudSync.featureFlag, .enableICloudSync)
        XCTAssertEqual(PremiumFeature.presence.featureFlag, .enablePresence)
    }

    func test_featureFlag_isNilForAlwaysAvailableFeatures() {
        for feature in [PremiumFeature.pskReporter, .catControl, .qrzLogbook, .lotwSync, .eqslSync, .statistics] {
            XCTAssertNil(feature.featureFlag, "\(feature) is not behind a remote flag")
        }
    }
}

// MARK: - Which products unlock premium

@MainActor
final class PremiumGrantTests: XCTestCase {

    func test_premiumProduct_grantsPremium() {
        XCTAssertTrue(PremiumManager.grantsPremium(productID: PremiumManager.premiumProductID))
    }

    func test_betaAccess_grantsPremium() {
        XCTAssertTrue(PremiumManager.grantsPremium(productID: PremiumManager.betaProductID))
    }

    func test_tips_doNotGrantPremium() {
        for id in PremiumManager.donationProductIDs {
            XCTAssertFalse(PremiumManager.grantsPremium(productID: id), "Tip \(id) must not unlock premium")
        }
    }

    func test_unknownProduct_doesNotGrantPremium() {
        XCTAssertFalse(PremiumManager.grantsPremium(productID: "something_else"))
    }
}

// MARK: - Tips from before 1.3.0 unlock premium

@MainActor
final class LegacyDonationTests: XCTestCase {

    private let cutoff = Date(timeIntervalSince1970: 1_800_000_000)

    func test_tipBeforeCutoff_isLegacyDonation() {
        for id in PremiumManager.donationProductIDs {
            XCTAssertTrue(
                PremiumManager.isLegacyDonation(
                    productID: id,
                    purchaseDate: cutoff.addingTimeInterval(-86_400),
                    revocationDate: nil,
                    cutoff: cutoff
                ),
                id
            )
        }
    }

    func test_tipAtOrAfterCutoff_isNotLegacyDonation() {
        for date in [cutoff, cutoff.addingTimeInterval(1)] {
            XCTAssertFalse(
                PremiumManager.isLegacyDonation(
                    productID: "coffee_large",
                    purchaseDate: date,
                    revocationDate: nil,
                    cutoff: cutoff
                )
            )
        }
    }

    func test_refundedTip_isNotLegacyDonation() {
        XCTAssertFalse(
            PremiumManager.isLegacyDonation(
                productID: "coffe_small",
                purchaseDate: cutoff.addingTimeInterval(-86_400),
                revocationDate: cutoff.addingTimeInterval(-3_600),
                cutoff: cutoff
            )
        )
    }

    func test_otherProducts_areNotLegacyDonations() {
        for id in [PremiumManager.premiumProductID, PremiumManager.betaProductID, "something_else"] {
            XCTAssertFalse(
                PremiumManager.isLegacyDonation(
                    productID: id,
                    purchaseDate: cutoff.addingTimeInterval(-86_400),
                    revocationDate: nil,
                    cutoff: cutoff
                ),
                id
            )
        }
    }

    /// 1.3.0 went live on 4 Nov 2026 with a 7-day phased release.
    func test_defaultCutoff_isTheEndOfThe130PhasedRelease() {
        let components = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(identifier: "UTC")!, from: PremiumManager.legacyDonationCutoff)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 11)
        XCTAssertEqual(components.hour, 0)
    }

    func test_newManager_isNotLegacyDonor() {
        let sut = PremiumManager(fetcher: EmptyPremiumFetcher(), observesTransactions: false)
        XCTAssertFalse(sut.isLegacyDonor)
    }

    /// Without this key iOS hides finished tips from `Transaction.all`.
    func test_infoPlist_includesConsumableHistory() {
        let value = Bundle.main.object(forInfoDictionaryKey: "SKIncludeConsumableInAppPurchaseHistory") as? Bool
        XCTAssertEqual(value, true)
    }
}

// MARK: - Notification.Name.premiumRevoked

final class PremiumRevokedNotificationTests: XCTestCase {

    func test_notificationNameIsDefined() {
        XCTAssertEqual(
            Notification.Name.premiumRevoked,
            Notification.Name("com.ea4iql.ftham.premiumRevoked")
        )
    }

    func test_notificationIsDeliveredToObserver() {
        let expectation = expectation(description: "premiumRevoked notification received")
        var cancellable: AnyCancellable?

        cancellable = NotificationCenter.default
            .publisher(for: .premiumRevoked)
            .sink { _ in
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: .premiumRevoked, object: nil)

        wait(for: [expectation], timeout: 1.0)
        cancellable?.cancel()
    }
}

// MARK: - PremiumManager (DEBUG-only paths)

@MainActor
final class PremiumManagerDebugTests: XCTestCase {

    #if DEBUG
    func test_setDebugPremium_true_unlocksImmediately() async {
        let manager = PremiumManager.shared
        let original = manager.debugPremiumEnabled

        manager.setDebugPremium(enabled: true)
        // loadPremiumStatus() runs asynchronously inside setDebugPremium; yield
        await Task.yield()
        XCTAssertTrue(manager.isPremiumUnlocked, "Debug override must unlock premium immediately")

        // Restore original state
        manager.setDebugPremium(enabled: original)
        await Task.yield()
    }

    func test_setDebugPremium_persists_acrossCallToLoad() async {
        let manager = PremiumManager.shared
        let original = manager.debugPremiumEnabled

        manager.setDebugPremium(enabled: true)
        await manager.loadPremiumStatus()
        XCTAssertTrue(manager.isPremiumUnlocked, "Debug override must survive explicit loadPremiumStatus()")

        manager.setDebugPremium(enabled: original)
        await Task.yield()
    }
    #endif

}

// MARK: - Product cache

/// `Product` cannot be built synthetically, so the cached case needs a StoreKit
/// test session that really serves the premium product.
@MainActor
final class PremiumManagerProductCacheTests: XCTestCase {

    private var session: SKTestSession!
    private var configURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PremiumProduct-\(UUID().uuidString).storekit")
        try Self.configuration.write(to: configURL, atomically: true, encoding: .utf8)
        session = try SKTestSession(contentsOf: configURL)
        session.disableDialogs = true
    }

    override func tearDown() async throws {
        session = nil
        if let configURL { try? FileManager.default.removeItem(at: configURL) }
        try await super.tearDown()
    }

    func test_fetchPremiumProduct_isIdempotentOnceTheProductIsCached() async throws {
        let sut = PremiumManager(fetcher: StoreKitProductFetcher(), observesTransactions: false)

        await sut.fetchPremiumProduct()
        XCTAssertNotNil(sut.premiumProduct, "The test session must serve the premium product")
        XCTAssertFalse(sut.isLoading, "isLoading must be false after fetchPremiumProduct() completes")

        var loadingTransitions: [Bool] = []
        let cancellable = sut.$isLoading
            .dropFirst()
            .sink { loadingTransitions.append($0) }
        defer { cancellable.cancel() }

        await sut.fetchPremiumProduct()

        XCTAssertTrue(loadingTransitions.isEmpty, "A cached product must not toggle isLoading")
        XCTAssertEqual(sut.productLoadState, .loaded)
    }

    /// Without a cached product the paywall has to be able to try again.
    func test_fetchPremiumProduct_fetchesAgainWhenNoProductWasFound() async {
        let fetcher = CountingPremiumFetcher()
        let sut = PremiumManager(fetcher: fetcher, observesTransactions: false)

        await sut.fetchPremiumProduct()
        await sut.fetchPremiumProduct()

        XCTAssertEqual(fetcher.calls, 2)
        XCTAssertEqual(sut.productLoadState, .failed)
    }

    private static let configuration = """
    {
      "identifier" : "PremiumManagerProductCacheTests",
      "nonRenewingSubscriptions" : [],
      "products" : [
        {
          "displayPrice" : "9.99",
          "familyShareable" : false,
          "internalID" : "9100000",
          "localizations" : [
            { "description" : "Premium", "displayName" : "Premium", "locale" : "en_US" }
          ],
          "productID" : "\(PremiumManager.premiumProductID)",
          "referenceName" : "Premium",
          "type" : "NonConsumable"
        }
      ],
      "settings" : {},
      "subscriptionGroups" : [],
      "version" : { "major" : 3, "minor" : 0 }
    }
    """
}

private final class CountingPremiumFetcher: ProductFetching, @unchecked Sendable {
    private(set) var calls = 0

    func fetchProducts(for identifiers: [String]) async throws -> [Product] {
        calls += 1
        return []
    }
}

// MARK: - Product load state (paywall retry)

private struct EmptyPremiumFetcher: ProductFetching {
    /// StoreKit `Product` cannot be built synthetically, so an empty result
    /// stands in for "product not found in App Store Connect".
    func fetchProducts(for identifiers: [String]) async throws -> [Product] { [] }
}

private struct ThrowingPremiumFetcher: ProductFetching {
    func fetchProducts(for identifiers: [String]) async throws -> [Product] {
        throw URLError(.notConnectedToInternet)
    }
}

/// Fails the first call and suspends on later ones, so a retry can be
/// observed while it is still loading.
private final class FailThenHangFetcher: ProductFetching, @unchecked Sendable {
    private var calls = 0

    func fetchProducts(for identifiers: [String]) async throws -> [Product] {
        calls += 1
        if calls == 1 { throw URLError(.timedOut) }
        try await Task.sleep(nanoseconds: 10_000_000_000)
        return []
    }
}

private struct RecordingPremiumFetcher: ProductFetching {
    let onFetch: @Sendable ([String]) -> Void

    func fetchProducts(for identifiers: [String]) async throws -> [Product] {
        onFetch(identifiers)
        return []
    }
}

@MainActor
final class PremiumManagerLoadStateTests: XCTestCase {

    func test_initialState_isIdle() {
        let sut = PremiumManager(fetcher: EmptyPremiumFetcher(), observesTransactions: false)
        XCTAssertEqual(sut.productLoadState, .idle)
        XCTAssertNil(sut.premiumProduct)
    }

    func test_emptyResult_isFailed() async {
        let sut = PremiumManager(fetcher: EmptyPremiumFetcher(), observesTransactions: false)

        await sut.fetchPremiumProduct()

        XCTAssertEqual(sut.productLoadState, .failed)
        XCTAssertNil(sut.premiumProduct)
        XCTAssertFalse(sut.isLoading)
    }

    func test_thrownError_isFailed() async {
        let sut = PremiumManager(fetcher: ThrowingPremiumFetcher(), observesTransactions: false)

        await sut.fetchPremiumProduct()

        XCTAssertEqual(sut.productLoadState, .failed)
        XCTAssertNil(sut.premiumProduct)
        XCTAssertFalse(sut.isLoading)
    }

    func test_retryAfterFailure_goesBackToLoading() async {
        let sut = PremiumManager(fetcher: FailThenHangFetcher(), observesTransactions: false)
        await sut.fetchPremiumProduct()
        XCTAssertEqual(sut.productLoadState, .failed)

        let retry = Task { await sut.fetchPremiumProduct() }
        await Task.yield()

        XCTAssertEqual(sut.productLoadState, .loading, "Try Again must leave the failed state right away")
        XCTAssertTrue(sut.isLoading)
        retry.cancel()
    }

    func test_consecutiveFailures_stayFailed() async {
        let sut = PremiumManager(fetcher: ThrowingPremiumFetcher(), observesTransactions: false)

        await sut.fetchPremiumProduct()
        await sut.fetchPremiumProduct()

        XCTAssertEqual(sut.productLoadState, .failed)
    }

    func test_requestsOnlyThePremiumProduct() async {
        let expectation = expectation(description: "fetch called")
        let sut = PremiumManager(
            fetcher: RecordingPremiumFetcher { ids in
                XCTAssertEqual(ids, [PremiumManager.premiumProductID])
                expectation.fulfill()
            },
            observesTransactions: false
        )

        await sut.fetchPremiumProduct()

        await fulfillment(of: [expectation], timeout: 1)
    }

    func test_withoutObservingTransactions_premiumStaysLocked() {
        let sut = PremiumManager(fetcher: EmptyPremiumFetcher(), observesTransactions: false)
        XCTAssertFalse(sut.isPremiumUnlocked)
        XCTAssertFalse(sut.isBetaUser)
    }
}
