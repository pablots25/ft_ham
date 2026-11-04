//
//  PremiumMomentTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 04/11/26.
//

import XCTest
@testable import ft8_ham

/// Usage-milestone prompts: Premium offers in place of tips, and the
/// rating request after the first logged QSOs.
final class PremiumMomentTests: XCTestCase {

    // MARK: - Flags

    func test_flags_areOffByDefault() {
        XCTAssertFalse(FeatureFlag.premiumMoments.defaultValue)
        XCTAssertFalse(FeatureFlag.rateAfterQSO.defaultValue)
    }

    func test_flags_useTheirRemoteConfigKeys() {
        XCTAssertEqual(FeatureFlag.premiumMoments.rawValue, "premiumMoments")
        XCTAssertEqual(FeatureFlag.rateAfterQSO.rawValue, "rateAfterQSO")
    }

    // MARK: - Moments

    func test_eachMoment_pointsAtTheFeatureThatAnswersIt() {
        XCTAssertEqual(PremiumMoment.qsoLogged.feature, .lotwSync)
        XCTAssertEqual(PremiumMoment.adifExport.feature, .qrzLogbook)
        XCTAssertEqual(PremiumMoment.txStarted.feature, .pskReporter)
    }

    func test_paywallSource_isAttributedToTheMoment() {
        XCTAssertEqual(PremiumMoment.qsoLogged.paywallSource.analyticsValue, "moment_qso")
        XCTAssertEqual(PremiumMoment.adifExport.paywallSource.analyticsValue, "moment_adif")
        XCTAssertEqual(PremiumMoment.txStarted.paywallSource.analyticsValue, "moment_tx")
    }

    func test_paywallSource_doesNotCollideWithFeatureSources() {
        let featureSources = Set(PremiumFeature.allCases.map(\.analyticsSource))
        for moment in PremiumMoment.allCases {
            XCTAssertFalse(featureSources.contains(moment.paywallSource.analyticsValue))
        }
    }

    func test_copy_isPresentAndFollowsHouseStyle() {
        for moment in PremiumMoment.allCases {
            for text in [moment.title, moment.message] {
                XCTAssertFalse(text.isEmpty, "\(moment) has empty copy")
                XCTAssertFalse(text.contains("\u{2014}"), "\(moment) uses an em dash")
                XCTAssertFalse(text.contains(";"), "\(moment) uses a semicolon")
            }
        }
    }

    func test_moments_haveUniqueIdentifiers() {
        let ids = PremiumMoment.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Premium offer

    func test_offersPremium_onlyToFreeUsersWithTheFlagOn() {
        XCTAssertTrue(PromptMomentPolicy.offersPremium(flagEnabled: true, isPremium: false))
        XCTAssertFalse(PromptMomentPolicy.offersPremium(flagEnabled: true, isPremium: true))
        XCTAssertFalse(PromptMomentPolicy.offersPremium(flagEnabled: false, isPremium: false))
        XCTAssertFalse(PromptMomentPolicy.offersPremium(flagEnabled: false, isPremium: true))
    }

    // MARK: - Rate after QSO

    private func shouldRequest(
        flag: Bool = true,
        rateEnabled: Bool = true,
        alreadyRequested: Bool = false,
        presentedThisSession: Bool = false,
        qsoCount: Int
    ) -> Bool {
        PromptMomentPolicy.shouldRequestReviewAfterQSO(
            flagEnabled: flag,
            ratePromptEnabled: rateEnabled,
            alreadyRequested: alreadyRequested,
            presentedThisSession: presentedThisSession,
            qsoCount: qsoCount,
            threshold: 3
        )
    }

    func test_review_waitsForTheThreshold() {
        XCTAssertFalse(shouldRequest(qsoCount: 1))
        XCTAssertFalse(shouldRequest(qsoCount: 2))
        XCTAssertTrue(shouldRequest(qsoCount: 3))
    }

    func test_review_stillFiresAfterTheThresholdWhenItWasMissed() {
        // Another prompt took the session on QSO 3, so QSO 4 asks instead.
        XCTAssertFalse(shouldRequest(presentedThisSession: true, qsoCount: 3))
        XCTAssertTrue(shouldRequest(qsoCount: 4))
    }

    func test_review_neverRepeatsOnceRequested() {
        XCTAssertFalse(shouldRequest(alreadyRequested: true, qsoCount: 3))
        XCTAssertFalse(shouldRequest(alreadyRequested: true, qsoCount: 50))
    }

    func test_review_respectsTheFlagAndTheRemoteRateSwitch() {
        XCTAssertFalse(shouldRequest(flag: false, qsoCount: 3))
        XCTAssertFalse(shouldRequest(rateEnabled: false, qsoCount: 3))
    }

    func test_review_defaultThresholdIsLow() {
        XCTAssertEqual(PromptMomentPolicy.reviewQSOThreshold, 3)
    }
}
