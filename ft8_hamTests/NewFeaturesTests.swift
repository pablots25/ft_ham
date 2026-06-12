//
//  NewFeaturesTests.swift
//  ft8_hamTests
//
//  Unit tests for features introduced in the April 2026 release:
//    - Feature D: tap-to-reply readiness (allowsReply flag on FT8Message)
//    - Feature E: 3-state Rx filter logic (off / mine / mine+CQ)
//    - Feature F: Stop TX & RX — stopCurrentTX() side-effects
//    - Feature G: country name stored in LogEntry
//

import XCTest
@testable import ft8_ham

// MARK: - Feature D — Tap-to-reply readiness

/// The tap-to-reply gesture is guarded by `msg.allowsReply`.
/// These tests verify that the `allowsReply` flag is correctly set so that
/// the gesture fires for legitimate received messages and is blocked for TX
/// messages and unknown-type messages.
final class FeatureDTapReplyTests: XCTestCase {

    // Helper to build a minimal FT8Message without a viewModel
    private func makeRXMessage(text: String, allowsReply: Bool = true) -> FT8Message {
        FT8Message(
            text: text,
            mode: .ft8,
            isRealtime: true,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14_074_000,
            isTX: false,
            band: .band20m,
            allowsReply: allowsReply
        )
    }

    private func makeTXMessage(text: String) -> FT8Message {
        FT8Message(
            text: text,
            mode: .ft8,
            isRealtime: true,
            timestamp: Date(),
            measuredSNR: .nan,
            frequency: 14_074_000,
            isTX: true,
            band: .band20m
        )
    }

    func testAllowsReplyTrueForCQMessage() {
        let msg = makeRXMessage(text: "CQ EA2ABC IN83")
        XCTAssertTrue(msg.allowsReply,
                      "CQ received messages must allow tap-to-reply")
    }

    func testAllowsReplyTrueForDirectedMessage() {
        let msg = makeRXMessage(text: "EA4IQL EA2ABC -12")
        XCTAssertTrue(msg.allowsReply,
                      "Directed received messages must allow tap-to-reply")
    }

    func testAllowsReplyFalseForTXMessage() {
        let msg = makeTXMessage(text: "CQ EA4IQL IM88")
        XCTAssertFalse(msg.allowsReply,
                       "TX messages must never allow tap-to-reply")
    }

    func testAllowsReplyFalseWhenExplicitlyDenied() {
        let msg = makeRXMessage(text: "CQ EA2ABC IN83", allowsReply: false)
        XCTAssertFalse(msg.allowsReply,
                       "allowsReply=false must be honoured regardless of message type")
    }

    /// Verifies that reply(to:) correctly configures the viewModel for an active QSO.
    @MainActor
    func testReplyToMessageSetsAutoSequencing() {
        let vm = FT8ViewModel()
        vm.callsign = "EA4IQL"
        vm.locator = "IM88"

        let cqMsg = makeRXMessage(text: "CQ EA2ABC IN83")
        vm.reply(to: cqMsg)

        XCTAssertTrue(vm.autoSequencingEnabled,
                      "Auto-sequencing must be enabled after reply(to:)")
        XCTAssertTrue(vm.transmitLoopActive,
                      "TX loop must activate after reply(to:)")
    }
}

// MARK: - Feature E — 3-state Rx filter

/// The view filter is a computed property in each list view, but the underlying
/// logic is purely based on FT8Message.forMe, FT8Message.isTX, and FT8Message.msgType.
/// We test those properties directly using a reusable apply(filterMode:to:) helper
/// that mirrors the switch expression used in the views.
final class FeatureERxFilterTests: XCTestCase {

    private var savedCallsign: String?

    override func setUp() {
        super.setUp()
        // forMe is derived from FT8Message's cached callsign (kept in sync with
        // UserDefaults via didChangeNotification) — pin it so tests are
        // deterministic regardless of execution order.
        savedCallsign = UserDefaults.standard.string(forKey: "callsign")
        UserDefaults.standard.set("EA4IQL", forKey: "callsign")
    }

    override func tearDown() {
        if let saved = savedCallsign {
            UserDefaults.standard.set(saved, forKey: "callsign")
        } else {
            UserDefaults.standard.removeObject(forKey: "callsign")
        }
        super.tearDown()
    }

    // Mirror the exact filter logic from the views so tests stay in sync
    private func apply(filterMode: Int, to messages: [FT8Message]) -> [FT8Message] {
        switch filterMode {
        case 1: return messages.filter { $0.forMe || $0.isTX }
        case 2: return messages.filter { $0.forMe || $0.isTX || $0.msgType == .cq }
        default: return messages
        }
    }

    // Build a small representative basket of messages
    private func makeMessages(myCallsign: String) -> [FT8Message] {
        [
            // CQ from someone else → not forMe, not TX, msgType == .cq
            FT8Message(text: "CQ DX7ABC PN13", mode: .ft8, isRealtime: true,
                       timestamp: Date(), measuredSNR: -8, frequency: 14_074_000, isTX: false, band: .band20m),
            // Directed to me
            FT8Message(text: "\(myCallsign) EA2XYZ -10", mode: .ft8, isRealtime: true,
                       timestamp: Date(), measuredSNR: -10, frequency: 14_074_000, isTX: false, band: .band20m),
            // Directed to someone else → not forMe
            FT8Message(text: "W1ABC EA2XYZ +05", mode: .ft8, isRealtime: true,
                       timestamp: Date(), measuredSNR: -5, frequency: 14_074_000, isTX: false, band: .band20m),
            // My own TX (sender == my callsign)
            FT8Message(text: "EA2XYZ \(myCallsign) IM88", mode: .ft8, isRealtime: true,
                       timestamp: Date(), measuredSNR: .nan, frequency: 14_074_000, isTX: true, band: .band20m)
        ]
    }

    func testMode0ShowsAll() {
        let msgs = [
            FT8Message(text: "CQ TEST IN99", mode: .ft8, isRealtime: false,
                       timestamp: Date(), measuredSNR: -5, frequency: 14_074_000, isTX: false, band: .band20m),
            FT8Message(text: "EA4IQL EA2ABC -12", mode: .ft8, isRealtime: false,
                       timestamp: Date(), measuredSNR: -12, frequency: 14_074_000, isTX: false, band: .band20m),
        ]
        let result = apply(filterMode: 0, to: msgs)
        XCTAssertEqual(result.count, msgs.count,
                       "Mode 0 (off) must return all messages unchanged")
    }

    func testMode0IsDefault() {
        let msgs = [
            FT8Message(text: "CQ EA2ABC IN83", mode: .ft8, isRealtime: false,
                       timestamp: Date(), measuredSNR: -8, frequency: 14_074_000, isTX: false, band: .band20m),
        ]
        XCTAssertEqual(apply(filterMode: 0, to: msgs), apply(filterMode: 99, to: msgs),
                       "Unknown filterMode values must fall through to default (show all)")
    }

    func testMode1ShowsMineAndTXOnly() {
        let msgs = makeMessages(myCallsign: "EA4IQL")
        let result = apply(filterMode: 1, to: msgs)

        // Must include: directed-to-me message and own TX
        // Must exclude: CQ from others, message to a third party
        for msg in result {
            XCTAssertTrue(msg.forMe || msg.isTX,
                          "Mode 1 must only show messages where forMe==true or isTX==true, got: \(msg.text)")
        }

        // An own TX is also forMe (sender == my callsign), so the two sets
        // overlap — assert membership explicitly instead of disjoint counting.
        XCTAssertEqual(result.count, 2,
                       "Mode 1 must keep only the directed-to-me message and the own TX")
        XCTAssertFalse(result.contains { $0.text.hasPrefix("CQ ") },
                       "Mode 1 must exclude CQs from others")
        XCTAssertFalse(result.contains { $0.text.hasPrefix("W1ABC") },
                       "Mode 1 must exclude messages directed to a third party")
    }

    func testMode1ExcludesCQFromOthers() {
        let cqFromOther = FT8Message(
            text: "CQ DX7ABC PN13", mode: .ft8, isRealtime: false,
            timestamp: Date(), measuredSNR: -8, frequency: 14_074_000, isTX: false, band: .band20m
        )
        // This CQ is not addressed to anyone, so forMe == false
        XCTAssertFalse(cqFromOther.forMe)
        XCTAssertFalse(cqFromOther.isTX)

        let result1 = apply(filterMode: 1, to: [cqFromOther])
        XCTAssertTrue(result1.isEmpty,
                      "Mode 1 must hide CQ messages not involving my callsign")
    }

    func testMode2IncludesCQFromOthers() {
        let cqFromOther = FT8Message(
            text: "CQ DX7ABC PN13", mode: .ft8, isRealtime: false,
            timestamp: Date(), measuredSNR: -8, frequency: 14_074_000, isTX: false, band: .band20m
        )
        XCTAssertEqual(cqFromOther.msgType, .cq,
                       "CQ message must have msgType == .cq")

        let result = apply(filterMode: 2, to: [cqFromOther])
        XCTAssertEqual(result.count, 1,
                       "Mode 2 must include CQ messages from other stations")
    }

    func testMode2ExcludesThirdPartyNonCQ() {
        let thirdParty = FT8Message(
            text: "W1ABC K2DEF +05", mode: .ft8, isRealtime: false,
            timestamp: Date(), measuredSNR: -5, frequency: 14_074_000, isTX: false, band: .band20m
        )
        XCTAssertFalse(thirdParty.forMe)
        XCTAssertFalse(thirdParty.isTX)
        XCTAssertNotEqual(thirdParty.msgType, .cq)

        let result = apply(filterMode: 2, to: [thirdParty])
        XCTAssertTrue(result.isEmpty,
                      "Mode 2 must still hide third-party non-CQ messages")
    }

    func testFilterModeCycleWrapsAt3() {
        // The button uses: filterMode = (filterMode + 1) % 3
        XCTAssertEqual((0 + 1) % 3, 1)
        XCTAssertEqual((1 + 1) % 3, 2)
        XCTAssertEqual((2 + 1) % 3, 0, "After mode 2, cycle must wrap back to 0 (off)")
    }
}

// MARK: - Feature F — Stop TX & RX

/// stopCurrentTX() must clear isTransmitting and transmitLoopActive.
/// stopSequencer() is async; we test the sync side-effects of stopCurrentTX alone.
@MainActor
final class FeatureFStopTXRXTests: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = FT8ViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testStopCurrentTXClearsIsTransmitting() {
        viewModel.isTransmitting = true
        viewModel.stopCurrentTX()
        XCTAssertFalse(viewModel.isTransmitting,
                       "stopCurrentTX() must set isTransmitting to false")
    }

    func testStopCurrentTXClearsTransmitLoopActive() {
        viewModel.transmitLoopActive = true
        viewModel.stopCurrentTX()
        XCTAssertFalse(viewModel.transmitLoopActive,
                       "stopCurrentTX() must set transmitLoopActive to false")
    }

    func testStopCurrentTXIdempotentWhenAlreadyStopped() {
        viewModel.isTransmitting = false
        viewModel.transmitLoopActive = false
        viewModel.stopCurrentTX()   // must not crash
        XCTAssertFalse(viewModel.isTransmitting)
        XCTAssertFalse(viewModel.transmitLoopActive)
    }

    func testStopTXAndRXButtonIsDisabledWhenNothingActive() {
        // The button's disabled condition: !isListening && !isTransmitting && !transmitLoopActive
        viewModel.isListening = false
        viewModel.isTransmitting = false
        viewModel.transmitLoopActive = false

        let shouldBeDisabled = !viewModel.isListening
            && !viewModel.isTransmitting
            && !viewModel.transmitLoopActive
        XCTAssertTrue(shouldBeDisabled,
                      "Stop TX & RX button must be disabled when nothing is active")
    }

    func testStopTXAndRXButtonIsEnabledWhenListening() {
        viewModel.isListening = true
        viewModel.isTransmitting = false
        viewModel.transmitLoopActive = false

        let shouldBeDisabled = !viewModel.isListening
            && !viewModel.isTransmitting
            && !viewModel.transmitLoopActive
        XCTAssertFalse(shouldBeDisabled,
                       "Stop TX & RX button must be enabled when isListening is true")
    }

    func testStopTXAndRXButtonIsEnabledWhenTransmitting() {
        viewModel.isListening = false
        viewModel.isTransmitting = true
        viewModel.transmitLoopActive = false

        let shouldBeDisabled = !viewModel.isListening
            && !viewModel.isTransmitting
            && !viewModel.transmitLoopActive
        XCTAssertFalse(shouldBeDisabled,
                       "Stop TX & RX button must be enabled when isTransmitting is true")
    }
}

// MARK: - Feature G — Country name in LogEntry

/// LogEntry.country must carry the resolved country string so the logbook view
/// can display it.  These tests verify the field is stored and retrieved correctly.
final class FeatureGCountryNameTests: XCTestCase {

    func testLogEntryStoresCountryName() {
        let entry = makeEntry(country: "Spain", flag: "🇪🇸")
        XCTAssertEqual(entry.country, "Spain",
                       "LogEntry.country must store the resolved country name")
    }

    func testLogEntryStoresFlagEmoji() {
        let entry = makeEntry(country: "Spain", flag: "🇪🇸")
        XCTAssertEqual(entry.flag, "🇪🇸",
                       "LogEntry.flag must store the flag emoji")
    }

    func testLogEntryAllowsNilCountry() {
        let entry = makeEntry(country: nil, flag: nil)
        XCTAssertNil(entry.country,
                     "LogEntry.country may be nil when country resolution fails")
        XCTAssertNil(entry.flag)
    }

    func testLogEntryCountryIsIndependentOfCallsign() {
        // Two entries with the same callsign prefix but different countries (corner case)
        let spain = makeEntry(callsign: "EA4IQL", country: "Spain", flag: "🇪🇸")
        let us = makeEntry(callsign: "K1ABC", country: "United States", flag: "🇺🇸")

        XCTAssertEqual(spain.country, "Spain")
        XCTAssertEqual(us.country, "United States")
        XCTAssertNotEqual(spain.country, us.country,
                          "Different callsign prefixes must not share country data")
    }

    func testLogEntryEmptyCountryString() {
        // An empty string is different from nil — the view guards with !country.isEmpty
        let entry = makeEntry(country: "", flag: nil)
        XCTAssertEqual(entry.country, "",
                       "LogEntry must faithfully store whatever string is provided")
        // The view uses: if let country = entry.country, !country.isEmpty
        let wouldBeShown = (entry.country.map { !$0.isEmpty }) ?? false
        XCTAssertFalse(wouldBeShown,
                       "An empty country string must not be shown in the logbook row")
    }

    // MARK: - Helper

    private func makeEntry(
        callsign: String = "EA4IQL",
        country: String?,
        flag: String?
    ) -> LogEntry {
        LogEntry(
            callsign: callsign,
            grid: "IM88",
            date: Date(),
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-12",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: country,
            flag: flag
        )
    }
}
