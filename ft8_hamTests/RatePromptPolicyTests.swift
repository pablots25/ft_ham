//
//  RatePromptPolicyTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 13/11/26.
//

import XCTest
@testable import ft8_ham

/// App Store rating request: retried after a failed roll, and asked again
/// once per major.minor version.
final class RatePromptPolicyTests: XCTestCase {

    // MARK: - Launch trigger

    private func shouldRequest(
        enabled: Bool = true,
        alreadyRequested: Bool = false,
        launches: Int,
        threshold: Int = 60,
        roll: Int = 1,
        probability: Int = 25
    ) -> Bool {
        RatePromptPolicy.shouldRequestAfterLaunches(
            enabled: enabled,
            alreadyRequested: alreadyRequested,
            launches: launches,
            threshold: threshold,
            roll: roll,
            probabilityPercent: probability
        )
    }

    func test_launches_waitsForTheThreshold() {
        XCTAssertFalse(shouldRequest(launches: 1))
        XCTAssertFalse(shouldRequest(launches: 59))
        XCTAssertTrue(shouldRequest(launches: 60))
    }

    func test_launches_retriesAfterAFailedRollOnTheThresholdLaunch() {
        // Regression: with `launches == threshold` a failed roll on launch 60
        // meant the rating was never requested.
        XCTAssertFalse(shouldRequest(launches: 60, roll: 80))
        XCTAssertTrue(shouldRequest(launches: 61, roll: 10))
        XCTAssertTrue(shouldRequest(launches: 500, roll: 25))
    }

    func test_launches_respectsTheProbability() {
        XCTAssertTrue(shouldRequest(launches: 60, roll: 25, probability: 25))
        XCTAssertFalse(shouldRequest(launches: 60, roll: 26, probability: 25))
        XCTAssertFalse(shouldRequest(launches: 60, roll: 1, probability: 0))
    }

    func test_launches_respectsTheRemoteSwitchAndAnEarlierRequest() {
        XCTAssertFalse(shouldRequest(enabled: false, launches: 60))
        XCTAssertFalse(shouldRequest(alreadyRequested: true, launches: 60))
        XCTAssertFalse(shouldRequest(alreadyRequested: true, launches: 500))
    }

    // MARK: - Version buckets

    func test_versionBucket_dropsThePatchAndBuild() {
        XCTAssertEqual(RatePromptPolicy.versionBucket("1.3.2"), "1.3")
        XCTAssertEqual(RatePromptPolicy.versionBucket("1.3"), "1.3")
        XCTAssertEqual(RatePromptPolicy.versionBucket("1.3.2-debug"), "1.3")
        XCTAssertEqual(RatePromptPolicy.versionBucket("2.0.0"), "2.0")
    }

    func test_versionBucket_keepsUnparseableVersions() {
        XCTAssertEqual(RatePromptPolicy.versionBucket("beta"), "beta")
    }

    // MARK: - Once per version

    func test_hasRequested_falseWhenNeverAsked() {
        XCTAssertFalse(RatePromptPolicy.hasRequested(lastRequestedVersion: nil, currentVersion: "1.3.2"))
    }

    func test_hasRequested_patchReleasesShareTheRequest() {
        XCTAssertTrue(RatePromptPolicy.hasRequested(lastRequestedVersion: "1.3.1", currentVersion: "1.3.2"))
        XCTAssertTrue(RatePromptPolicy.hasRequested(lastRequestedVersion: "1.3.2", currentVersion: "1.3.2"))
    }

    func test_hasRequested_nextMinorOrMajorMayAskAgain() {
        XCTAssertFalse(RatePromptPolicy.hasRequested(lastRequestedVersion: "1.3.2", currentVersion: "1.4.0"))
        XCTAssertFalse(RatePromptPolicy.hasRequested(lastRequestedVersion: "1.9", currentVersion: "2.0"))
    }

    // MARK: - Legacy flag migration

    func test_lastRequestedVersion_prefersTheStoredVersion() {
        XCTAssertEqual(
            RatePromptPolicy.lastRequestedVersion(stored: "1.2.0", legacyRequested: true, currentVersion: "1.3.2"),
            "1.2.0"
        )
    }

    func test_lastRequestedVersion_legacyRequestCountsForTheRunningVersion() {
        // Asked before 1.3.2 stored versions: no new request on this update,
        // but 1.4 can ask again.
        let last = RatePromptPolicy.lastRequestedVersion(stored: nil, legacyRequested: true, currentVersion: "1.3.2")
        XCTAssertEqual(last, "1.3.2")
        XCTAssertTrue(RatePromptPolicy.hasRequested(lastRequestedVersion: last, currentVersion: "1.3.2"))
        XCTAssertFalse(RatePromptPolicy.hasRequested(lastRequestedVersion: last, currentVersion: "1.4.0"))
    }

    func test_lastRequestedVersion_nilWhenNeverAsked() {
        XCTAssertNil(RatePromptPolicy.lastRequestedVersion(stored: nil, legacyRequested: false, currentVersion: "1.3.2"))
        XCTAssertNil(RatePromptPolicy.lastRequestedVersion(stored: "", legacyRequested: false, currentVersion: "1.3.2"))
    }

    func test_lastRequestedVersionKey_isStable() {
        XCTAssertEqual(RatePromptPolicy.lastRequestedVersionKey, "ratePromptLastRequestedVersion")
    }
}
