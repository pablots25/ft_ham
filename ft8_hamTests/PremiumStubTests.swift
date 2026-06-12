// PremiumStubTests.swift
// ft8_hamTests
//
// Contract tests for the premium feature stubs:
//   • CATControlStub — all async methods return success=false with an error message
//   • PSKReporterStub — report/flush are no-ops; stats remain at zero defaults
//
// These tests verify the stub CONTRACT (what callers can rely on when premium is absent),
// not the premium implementation itself.
//
// CATControlStub is a thread-safe singleton; PSKReporterStub is @MainActor-isolated,
// so its test class runs on the main actor.

import XCTest
@testable import ft8_ham

/// Contract tests for `CATControlStub` — the no-op CAT rig controller.
final class CATControlStubTests: XCTestCase {

    // MARK: - Shared system under test

    private var sut: CATControlStub!

    override func setUp() {
        super.setUp()
        sut = CATControlStub.shared
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - setPTT

    func test_setPTT_enabled_returnsSuccessFalse() async {
        // Given: PTT enabled request to a local rigctld port
        // When
        let response = await sut.setPTT(enabled: true, host: "127.0.0.1", port: 4532)
        // Then
        XCTAssertFalse(response.success, "Stub must never succeed")
    }

    func test_setPTT_disabled_returnsSuccessFalse() async {
        let response = await sut.setPTT(enabled: false, host: "127.0.0.1", port: 4532)
        XCTAssertFalse(response.success)
    }

    func test_setPTT_returnsNonNilErrorMessage() async {
        let response = await sut.setPTT(enabled: true, host: "127.0.0.1", port: 4532)
        XCTAssertNotNil(response.errorMessage,
                        "Stub must return an error message explaining premium is required")
        XCTAssertFalse(response.errorMessage!.isEmpty)
    }

    func test_setPTT_errorMessage_containsPremiumKeyword() async {
        let response = await sut.setPTT(enabled: true, host: "127.0.0.1", port: 4532)
        let msg = response.errorMessage ?? ""
        XCTAssertTrue(msg.lowercased().contains("premium"),
                      "Error should mention 'premium', got: '\(msg)'")
    }

    // MARK: - setFrequency

    func test_setFrequency_returnsSuccessFalse() async {
        let response = await sut.setFrequency(frequency: 14_074_000, host: "127.0.0.1", port: 4532)
        XCTAssertFalse(response.success)
    }

    func test_setFrequency_returnsNonNilErrorMessage() async {
        let response = await sut.setFrequency(frequency: 7_074_000, host: "127.0.0.1", port: 4532)
        XCTAssertNotNil(response.errorMessage)
    }

    // MARK: - getFrequency

    func test_getFrequency_returnsSuccessFalse() async {
        let response = await sut.getFrequency(host: "127.0.0.1", port: 4532)
        XCTAssertFalse(response.success)
    }

    func test_getFrequency_returnsNonNilErrorMessage() async {
        let response = await sut.getFrequency(host: "127.0.0.1", port: 4532)
        XCTAssertNotNil(response.errorMessage)
    }

    func test_getFrequency_responseStringIsEmpty() async {
        let response = await sut.getFrequency(host: "127.0.0.1", port: 4532)
        // The stub doesn't return a frequency value
        XCTAssertEqual(response.response, "")
    }

    // MARK: - connect / disconnect (void, no-op)

    func test_connect_doesNotCrash() {
        // connect() is a void no-op; we simply verify it doesn't throw/crash
        sut.connect(host: "127.0.0.1", port: 4532)
    }

    func test_disconnect_doesNotCrash() {
        sut.disconnect()
    }

    // MARK: - Protocol conformance (compile-time check via assignment)

    func test_stubConformsToCATControlProtocol() {
        // This would fail to compile if CATControlStub did not fully conform.
        let _: any CATControlProtocol = CATControlStub.shared
    }
}

// MARK: -

/// Contract tests for `PSKReporterStub` — the no-op PSK Reporter.
@MainActor
final class PSKReporterStubTests: XCTestCase {

    private var sut: PSKReporterStub!

    override func setUp() {
        super.setUp()
        sut = PSKReporterStub.shared
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - report(_:testMode:)

    func test_report_doesNotCrash() {
        let report = PSKReporterReport(
            receiverCallsign: "EA4IQL",
            senderCallsign: "K1ABC",
            receiverLocator: "IN76",
            frequencyHz: 14_074_000,
            mode: .ft8,
            snr: -10
        )
        // Should complete without crash or exception
        sut.report(report, testMode: false)
    }

    func test_report_doesNotIncrementStats() {
        let before = sut.stats
        let report = PSKReporterReport(
            receiverCallsign: "EA4IQL",
            senderCallsign: "K1ABC",
            receiverLocator: "IN76",
            frequencyHz: 14_074_000,
            mode: .ft8,
            snr: 5
        )
        sut.report(report)
        // Stats must remain unchanged — stub is a no-op
        XCTAssertEqual(sut.stats.sent,       before.sent)
        XCTAssertEqual(sut.stats.successful, before.successful)
        XCTAssertEqual(sut.stats.errors,     before.errors)
    }

    // MARK: - flushPendingReports()

    func test_flushPendingReports_doesNotCrash() {
        sut.flushPendingReports()
    }

    func test_flushPendingReports_doesNotChangeStats() {
        let before = sut.stats
        sut.flushPendingReports()
        XCTAssertEqual(sut.stats.sent,    before.sent)
        XCTAssertEqual(sut.stats.errors,  before.errors)
    }

    // MARK: - Default stats

    func test_defaultStats_allCountersAreZero() {
        let stats = PSKReporterStats()
        XCTAssertEqual(stats.sent,       0)
        XCTAssertEqual(stats.successful, 0)
        XCTAssertEqual(stats.heldBack,   0)
        XCTAssertEqual(stats.errors,     0)
    }

    func test_defaultStats_derivedPropertiesAreZero() {
        let stats = PSKReporterStats()
        XCTAssertEqual(stats.totalReports,      0)
        XCTAssertEqual(stats.successfulReports, 0)
        XCTAssertEqual(stats.failedReports,     0)
        XCTAssertEqual(stats.pendingReports,    0)
    }

    // MARK: - Protocol conformance (compile-time check)

    func test_stubConformsToPSKReporterProtocol() {
        let _: any PSKReporterProtocol = PSKReporterStub.shared
    }
}
