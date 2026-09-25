//
//  NotificationRoutingTests.swift
//  ft8_hamTests
//
//  Covers how local notifications are presented in the foreground and which
//  responses open the Logbook tab.
//

import UserNotifications
import XCTest
@testable import ft8_ham

final class NotificationPresentationTests: XCTestCase {

    func test_loggedQSO_presentsNothingInForeground() {
        let options = NotificationHelper.foregroundPresentationOptions(
            identifier: UUID().uuidString,
            categoryIdentifier: NotificationHelper.qsoLoggedCategoryID
        )
        XCTAssertEqual(options, [])
    }

    func test_callAlert_presentsSilentBanner() {
        let options = NotificationHelper.foregroundPresentationOptions(
            identifier: NotificationHelper.callAlertID,
            categoryIdentifier: ""
        )
        XCTAssertEqual(options, [.banner])
    }

    func test_otherNotifications_keepBannerAndSound() {
        let options = NotificationHelper.foregroundPresentationOptions(
            identifier: "sequencer_paused_background",
            categoryIdentifier: ""
        )
        XCTAssertEqual(options, [.banner, .sound])
    }

    func test_callAlertIdentifierIsStable() {
        XCTAssertEqual(NotificationHelper.callAlertID, "call_alert")
    }
}

final class NotificationResponseTests: XCTestCase {

    func test_reviewQSOAction_opensLogbook() {
        XCTAssertTrue(NotificationHelper.opensLogbook(
            actionIdentifier: NotificationHelper.reviewQSOActionID,
            categoryIdentifier: NotificationHelper.qsoLoggedCategoryID
        ))
    }

    func test_tapOnLoggedQSO_opensLogbook() {
        XCTAssertTrue(NotificationHelper.opensLogbook(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: NotificationHelper.qsoLoggedCategoryID
        ))
    }

    func test_dismissOrOtherNotifications_doNotOpenLogbook() {
        XCTAssertFalse(NotificationHelper.opensLogbook(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            categoryIdentifier: NotificationHelper.qsoLoggedCategoryID
        ))
        XCTAssertFalse(NotificationHelper.opensLogbook(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: ""
        ))
    }
}

@MainActor
final class TabRouterTests: XCTestCase {

    func test_pendingTabIsConsumedOnce() {
        let router = TabRouter()
        XCTAssertNil(router.consume())
        router.open(.logbook)
        XCTAssertEqual(router.pendingTab, .logbook)
        XCTAssertEqual(router.consume(), .logbook)
        XCTAssertNil(router.consume())
    }

    func test_logbookTabTagMatchesContentView() {
        XCTAssertEqual(AppTab.logbook.rawValue, 3)
        XCTAssertEqual(AppTab.configuration.rawValue, 4)
    }
}
