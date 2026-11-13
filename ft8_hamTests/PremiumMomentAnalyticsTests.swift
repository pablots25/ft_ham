//
//  PremiumMomentAnalyticsTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 13/11/26.
//

import XCTest
@testable import ft8_ham

/// Analytics for the Premium Moments funnel (shown, confirmed, postponed,
/// skipped) and the trigger behind each rating request.
final class PremiumMomentAnalyticsTests: XCTestCase {

    private var logger: MockAnalyticsLogger!

    override func setUp() {
        super.setUp()
        logger = MockAnalyticsLogger()
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - Event names

    func test_eventNames_matchTheAgreedCatalog() {
        XCTAssertEqual(AnalyticsEventName.premiumMomentShown, "premium_moment_shown")
        XCTAssertEqual(AnalyticsEventName.premiumMomentConfirmed, "premium_moment_confirmed")
        XCTAssertEqual(AnalyticsEventName.premiumMomentPostponed, "premium_moment_postponed")
        XCTAssertEqual(AnalyticsEventName.premiumMomentSkipped, "premium_moment_skipped")
        XCTAssertEqual(AnalyticsEventName.ratePromptShown, "rate_prompt_shown")
    }

    func test_eventNames_fitFirebaseLimits() {
        let names = [
            AnalyticsEventName.premiumMomentShown,
            AnalyticsEventName.premiumMomentConfirmed,
            AnalyticsEventName.premiumMomentPostponed,
            AnalyticsEventName.premiumMomentSkipped,
            AnalyticsEventName.ratePromptShown
        ]
        for name in names {
            XCTAssertLessThanOrEqual(name.count, 40, name)
            XCTAssertNotNil(name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression), name)
        }
    }

    // MARK: - Trigger sources

    func test_triggerSource_isTheMomentRawValue() {
        XCTAssertEqual(PremiumMoment.qsoLogged.rawValue, "qso")
        XCTAssertEqual(PremiumMoment.adifExport.rawValue, "adif")
        XCTAssertEqual(PremiumMoment.txStarted.rawValue, "tx")
    }

    // MARK: - Shown / confirmed / postponed

    func test_shown_sendsTriggerSourceAndLaunches_forEveryMoment() {
        for moment in PremiumMoment.allCases {
            logger.logPremiumMomentShown(moment, appLaunches: 12)
            assertFunnelEvent(AnalyticsEventName.premiumMomentShown, moment: moment, launches: 12)
        }
    }

    func test_confirmed_sendsTriggerSourceAndLaunches_forEveryMoment() {
        for moment in PremiumMoment.allCases {
            logger.logPremiumMomentConfirmed(moment, appLaunches: 7)
            assertFunnelEvent(AnalyticsEventName.premiumMomentConfirmed, moment: moment, launches: 7)
        }
    }

    func test_postponed_sendsTriggerSourceAndLaunches_forEveryMoment() {
        for moment in PremiumMoment.allCases {
            logger.logPremiumMomentPostponed(moment, appLaunches: 3)
            assertFunnelEvent(AnalyticsEventName.premiumMomentPostponed, moment: moment, launches: 3)
        }
    }

    func test_funnelEvents_carryNoReasonOrRoll() {
        logger.logPremiumMomentShown(.qsoLogged, appLaunches: 1)
        XCTAssertNil(logger.lastEvent?.parameters[AnalyticsParam.reason])
        XCTAssertNil(logger.lastEvent?.parameters[AnalyticsParam.roll])
    }

    // MARK: - Skipped

    func test_skipped_sendsReason_forEveryMomentAndReason() {
        for moment in PremiumMoment.allCases {
            for reason in PremiumMomentSkipReason.allCases {
                logger.logPremiumMomentSkipped(moment, reason: reason, appLaunches: 9)
                let event = logger.lastEvent
                XCTAssertEqual(event?.name, AnalyticsEventName.premiumMomentSkipped)
                XCTAssertEqual(event?.string(AnalyticsParam.triggerSource), moment.rawValue)
                XCTAssertEqual(event?.string(AnalyticsParam.reason), reason.rawValue)
                XCTAssertEqual(event?.int(AnalyticsParam.appLaunches), 9)
                XCTAssertNil(event?.parameters[AnalyticsParam.roll])
            }
        }
    }

    func test_skipped_byProbabilityRoll_sendsTheRoll() {
        logger.logPremiumMomentSkipped(.txStarted, reason: .probabilityRoll, appLaunches: 20, roll: 87)
        XCTAssertEqual(logger.lastEvent?.string(AnalyticsParam.reason), "probability_roll")
        XCTAssertEqual(logger.lastEvent?.int(AnalyticsParam.roll), 87)
    }

    func test_skipReasons_matchTheAgreedValues() {
        XCTAssertEqual(PremiumMomentSkipReason.isPremium.rawValue, "is_premium")
        XCTAssertEqual(PremiumMomentSkipReason.promptPresentedThisSession.rawValue, "prompt_presented_this_session")
        XCTAssertEqual(PremiumMomentSkipReason.shareSheetActive.rawValue, "share_sheet_active")
        XCTAssertEqual(PremiumMomentSkipReason.cooldown.rawValue, "cooldown")
        XCTAssertEqual(PremiumMomentSkipReason.probabilityRoll.rawValue, "probability_roll")
    }

    func test_skipReasons_fitFirebaseParameterValueLimit() {
        for reason in PremiumMomentSkipReason.allCases {
            XCTAssertLessThanOrEqual(reason.rawValue.count, 100, reason.rawValue)
        }
    }

    // MARK: - Skip reason policy

    func test_skipReason_isPremium_winsOverEverything() {
        XCTAssertEqual(
            PromptMomentPolicy.premiumMomentSkipReason(isPremium: true, presentedThisSession: true, shareSheetActive: true),
            .isPremium
        )
    }

    func test_skipReason_presentedThisSession_beforeShareSheet() {
        XCTAssertEqual(
            PromptMomentPolicy.premiumMomentSkipReason(isPremium: false, presentedThisSession: true, shareSheetActive: true),
            .promptPresentedThisSession
        )
    }

    func test_skipReason_shareSheetActive() {
        XCTAssertEqual(
            PromptMomentPolicy.premiumMomentSkipReason(isPremium: false, presentedThisSession: false, shareSheetActive: true),
            .shareSheetActive
        )
    }

    func test_skipReason_isNil_whenTheMomentCanCount() {
        XCTAssertNil(
            PromptMomentPolicy.premiumMomentSkipReason(isPremium: false, presentedThisSession: false, shareSheetActive: false)
        )
    }

    // MARK: - Rate prompt trigger

    func test_ratePromptShown_sendsTriggerSource_forEveryTrigger() {
        let expected: [RatePromptTrigger: String] = [.launches: "launches", .qso: "qso", .debug: "debug"]
        for (trigger, value) in expected {
            logger.logRatePromptShown(trigger: trigger)
            XCTAssertEqual(logger.lastEvent?.name, "rate_prompt_shown")
            XCTAssertEqual(logger.lastEvent?.string(AnalyticsParam.triggerSource), value)
        }
    }

    func test_ratePromptShown_reusesTheExistingTriggerSourceParameter() {
        XCTAssertEqual(AnalyticsParam.triggerSource, "trigger_source")
    }

    // MARK: - Helpers

    private func assertFunnelEvent(
        _ name: String,
        moment: PremiumMoment,
        launches: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let event = logger.lastEvent
        XCTAssertEqual(event?.name, name, file: file, line: line)
        XCTAssertEqual(event?.string(AnalyticsParam.triggerSource), moment.rawValue, file: file, line: line)
        XCTAssertEqual(event?.int(AnalyticsParam.appLaunches), launches, file: file, line: line)
    }
}
