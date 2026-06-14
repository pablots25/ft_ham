//
//  PremiumManagerTests.swift
//  ft8_hamTests
//
//  Tests for PremiumManager business logic, PremiumError, PaywallSource, and
//  the new PremiumFeature paywall properties added in the premium improvements refactor.
//

import XCTest
import Combine
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

    func test_countIsSevenFeatures() {
        XCTAssertEqual(PremiumFeature.allCases.count, 7)
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

    func test_fetchPremiumProduct_isIdempotent() async {
        // First call loads (or attempts to load) the product.
        // Subsequent calls must return early without flipping isLoading.
        let manager = PremiumManager.shared

        await manager.fetchPremiumProduct()
        let loadingAfterFirst = manager.isLoading

        // Snapshot isLoading transitions during a second call
        var loadingTransitions: [Bool] = []
        let cancellable = manager.$isLoading
            .dropFirst()
            .sink { loadingTransitions.append($0) }

        await manager.fetchPremiumProduct()

        XCTAssertFalse(loadingAfterFirst, "isLoading must be false after fetchPremiumProduct() completes")
        XCTAssertTrue(
            loadingTransitions.isEmpty,
            "Second fetchPremiumProduct() call must not toggle isLoading — product already cached"
        )
        cancellable.cancel()
    }
}
