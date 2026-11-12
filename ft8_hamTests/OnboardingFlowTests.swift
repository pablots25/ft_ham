//
//  OnboardingFlowTests.swift
//  ft8_hamTests
//
//  The simplified onboarding: step order, the station check that gates
//  "Start receiving", the GPS locator helper and the contextual
//  notification prompt.
//

import UserNotifications
import XCTest
@testable import ft8_ham

final class OnboardingFlowTests: XCTestCase {

    // MARK: - Step order

    func test_steps_areWelcomeStationAudioReady() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .station, .audio, .ready])
        XCTAssertEqual(OnboardingStep.count, 4)
    }

    func test_next_walksEveryStepAndStopsAtReady() {
        XCTAssertEqual(OnboardingStep.welcome.next, .station)
        XCTAssertEqual(OnboardingStep.station.next, .audio)
        XCTAssertEqual(OnboardingStep.audio.next, .ready)
        XCTAssertNil(OnboardingStep.ready.next)
    }

    func test_isLast_onlyForReady() {
        XCTAssertEqual(OnboardingStep.allCases.filter(\.isLast), [.ready])
    }

    func test_number_isOneBased() {
        XCTAssertEqual(OnboardingStep.allCases.map(\.number), [1, 2, 3, 4])
    }

    // MARK: - Station check

    func test_isReady_validCallsignAndLocator() {
        XCTAssertTrue(OnboardingStation.isReady(callsign: "EA4IQL", locator: "IN80"))
    }

    func test_isReady_falseWhenEitherIsMissing() {
        XCTAssertFalse(OnboardingStation.isReady(callsign: "", locator: "IN80"))
        XCTAssertFalse(OnboardingStation.isReady(callsign: "EA4IQL", locator: ""))
        XCTAssertFalse(OnboardingStation.isReady(callsign: "", locator: ""))
    }

    func test_isReady_falseForInvalidValues() {
        XCTAssertFalse(OnboardingStation.isReady(callsign: "NOT A CALL", locator: "IN80"))
        XCTAssertFalse(OnboardingStation.isReady(callsign: "EA4IQL", locator: "ZZ99"))
        XCTAssertFalse(OnboardingStation.isReady(callsign: "EA4IQL", locator: "RR73"))
    }

    // MARK: - GPS locator

    func test_locator_madrid() {
        XCTAssertEqual(OnboardingStation.locator(latitude: 40.4168, longitude: -3.7038), "IN80")
    }

    func test_locator_newYork() {
        XCTAssertEqual(OnboardingStation.locator(latitude: 40.7128, longitude: -74.0060), "FN20")
    }

    func test_locator_isFourCharacters() {
        XCTAssertEqual(OnboardingStation.locator(latitude: -33.8688, longitude: 151.2093)?.count, 4)
    }

    func test_locator_edgesStayInsideTheGrid() {
        XCTAssertEqual(OnboardingStation.locator(latitude: 90, longitude: 180), "RR99")
        XCTAssertEqual(OnboardingStation.locator(latitude: -90, longitude: -180), "AA00")
    }

    func test_locator_outOfRangeIsNil() {
        XCTAssertNil(OnboardingStation.locator(latitude: 91, longitude: 0))
        XCTAssertNil(OnboardingStation.locator(latitude: 0, longitude: -181))
    }

    // MARK: - Notification prompt

    func test_shouldRequest_onlyWhenUndeterminedAndNotAsked() {
        XCTAssertTrue(NotificationPermissionPrompt.shouldRequest(status: .notDetermined, alreadyAsked: false))
        XCTAssertFalse(NotificationPermissionPrompt.shouldRequest(status: .notDetermined, alreadyAsked: true))
    }

    func test_shouldRequest_neverAfterTheSystemDialog() {
        let decided: [UNAuthorizationStatus] = [.authorized, .denied, .provisional, .ephemeral]
        for status in decided {
            XCTAssertFalse(NotificationPermissionPrompt.shouldRequest(status: status, alreadyAsked: false))
            XCTAssertFalse(NotificationPermissionPrompt.shouldRequest(status: status, alreadyAsked: true))
        }
    }

    // MARK: - Reset

    func test_resetOnboarding_clearsTheNotificationAskedFlag() {
        UserDefaults.standard.set(true, forKey: NotificationPermissionPrompt.askedKey)
        AppStorageResetter.resetOnboarding()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: NotificationPermissionPrompt.askedKey))
    }
}
