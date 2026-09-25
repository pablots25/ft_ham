//
//  CallAlertTests.swift
//  ft8_hamTests
//
//  Covers the "calling you" highlight and alerts: which decoded messages
//  count as a call to us, when a slot may alert, which audio routes may play
//  the sound, and how the view model raises the alert once per slot.
//

import AVFoundation
import SwiftUI
import XCTest
@testable import ft8_ham

// MARK: - Detector

final class CallAlertDetectorTests: XCTestCase {

    private let my = "EA1AAA"

    private func rx(_ text: String) -> FT8Message {
        FT8Message(text: text, mode: .ft8, isTX: false)
    }

    func test_isCallingMe_gridCallFromAnotherStation() {
        XCTAssertTrue(CallAlertDetector.isCallingMe(rx("EA1AAA DL2XYZ JO62"), myCallsign: my))
    }

    func test_isCallingMe_signalReportAndFinals() {
        XCTAssertTrue(CallAlertDetector.isCallingMe(rx("EA1AAA DL2XYZ -05"), myCallsign: my))
        XCTAssertTrue(CallAlertDetector.isCallingMe(rx("EA1AAA DL2XYZ R-05"), myCallsign: my))
        XCTAssertTrue(CallAlertDetector.isCallingMe(rx("EA1AAA DL2XYZ RR73"), myCallsign: my))
    }

    func test_isCallingMe_isCaseInsensitiveOnOurCallsign() {
        XCTAssertTrue(CallAlertDetector.isCallingMe(rx("EA1AAA DL2XYZ JO62"), myCallsign: " ea1aaa "))
    }

    func test_isCallingMe_falseForOtherStationsTraffic() {
        XCTAssertFalse(CallAlertDetector.isCallingMe(rx("F4ABC DL2XYZ JO62"), myCallsign: my))
    }

    func test_isCallingMe_falseForCQ() {
        XCTAssertFalse(CallAlertDetector.isCallingMe(rx("CQ DL2XYZ JO62"), myCallsign: my))
    }

    func test_isCallingMe_falseForOurOwnTransmission() {
        let tx = FT8Message(text: "DL2XYZ EA1AAA IN70", mode: .ft8, isTX: true)
        XCTAssertFalse(CallAlertDetector.isCallingMe(tx, myCallsign: my))
        let echo = FT8Message(text: "EA1AAA DL2XYZ JO62", mode: .ft8, isTX: true)
        XCTAssertFalse(CallAlertDetector.isCallingMe(echo, myCallsign: my))
    }

    func test_isCallingMe_falseWhenWeAreTheSender() {
        // Our own call decoded back as the sender is not someone calling us.
        XCTAssertFalse(CallAlertDetector.isCallingMe(rx("DL2XYZ EA1AAA IN70"), myCallsign: my))
    }

    func test_isCallingMe_falseWithoutOurCallsign() {
        XCTAssertFalse(CallAlertDetector.isCallingMe(rx("EA1AAA DL2XYZ JO62"), myCallsign: ""))
        XCTAssertFalse(CallAlertDetector.isCallingMe(rx("EA1AAA DL2XYZ JO62"), myCallsign: "   "))
    }

    func test_allowsAlert_whenNoQSOInProgress() {
        XCTAssertTrue(CallAlertDetector.allowsAlert(in: .idle))
        XCTAssertTrue(CallAlertDetector.allowsAlert(in: .callingCQ))
        XCTAssertTrue(CallAlertDetector.allowsAlert(in: .completed(dxCallsign: "DL2XYZ")))
        XCTAssertTrue(CallAlertDetector.allowsAlert(in: .timeout(dxCallsign: "DL2XYZ")))
    }

    func test_allowsAlert_blockedDuringQSO() {
        let active: [QSOState] = [
            .sendingGrid(dxCallsign: "DL2XYZ"),
            .sendingReport(dxCallsign: "DL2XYZ"), .listeningReport(dxCallsign: "DL2XYZ"),
            .sendingRReport(dxCallsign: "DL2XYZ"), .listeningRReport(dxCallsign: "DL2XYZ"),
            .sendingRRR(dxCallsign: "DL2XYZ"), .listeningRRR(dxCallsign: "DL2XYZ"),
            .sending73(dxCallsign: "DL2XYZ")
        ]
        for state in active {
            XCTAssertFalse(CallAlertDetector.allowsAlert(in: state), "\(state)")
        }
    }

    func test_alertMessage_returnsFirstCallToUs() {
        let messages = [rx("CQ F4ABC JN18"), rx("EA1AAA DL2XYZ JO62"), rx("EA1AAA G0ABC IO91")]
        let hit = CallAlertDetector.alertMessage(in: messages, myCallsign: my, qsoState: .idle)
        XCTAssertEqual(hit?.text, "EA1AAA DL2XYZ JO62")
    }

    func test_alertMessage_nilWhenNobodyCalls() {
        let messages = [rx("CQ F4ABC JN18"), rx("F4ABC DL2XYZ JO62")]
        XCTAssertNil(CallAlertDetector.alertMessage(in: messages, myCallsign: my, qsoState: .idle))
    }

    func test_alertMessage_nilDuringQSO() {
        let messages = [rx("EA1AAA DL2XYZ -05")]
        XCTAssertNil(CallAlertDetector.alertMessage(
            in: messages, myCallsign: my, qsoState: .listeningReport(dxCallsign: "DL2XYZ")
        ))
    }
}

// MARK: - Sound route

final class CallAlertSoundRouteTests: XCTestCase {

    func test_speakerAndHeadphonesAreSafe() {
        XCTAssertTrue(CallAlertService.isSafeRouteForAlertSound([.builtInSpeaker]))
        XCTAssertTrue(CallAlertService.isSafeRouteForAlertSound([.headphones]))
        XCTAssertTrue(CallAlertService.isSafeRouteForAlertSound([.bluetoothA2DP]))
    }

    func test_receiverAndAllBluetoothProfilesAreSafe() {
        XCTAssertTrue(CallAlertService.isSafeRouteForAlertSound([.builtInReceiver]))
        XCTAssertTrue(CallAlertService.isSafeRouteForAlertSound([.bluetoothHFP]))
        XCTAssertTrue(CallAlertService.isSafeRouteForAlertSound([.bluetoothLE]))
    }

    func test_otherRoutesAreNotSafe() {
        XCTAssertFalse(CallAlertService.isSafeRouteForAlertSound([.airPlay]))
        XCTAssertFalse(CallAlertService.isSafeRouteForAlertSound([.carAudio]))
    }

    func test_radioInterfacesAreNotSafe() {
        XCTAssertFalse(CallAlertService.isSafeRouteForAlertSound([.usbAudio]))
        XCTAssertFalse(CallAlertService.isSafeRouteForAlertSound([.lineOut]))
        XCTAssertFalse(CallAlertService.isSafeRouteForAlertSound([.HDMI]))
    }

    func test_mixedRouteWithInterfaceIsNotSafe() {
        XCTAssertFalse(CallAlertService.isSafeRouteForAlertSound([.builtInSpeaker, .usbAudio]))
    }

    func test_emptyRouteIsNotSafe() {
        XCTAssertFalse(CallAlertService.isSafeRouteForAlertSound([]))
    }
}

// MARK: - View model

@MainActor
final class CallAlertViewModelTests: XCTestCase {

    private let settingKeys = [
        "highlightMyCallsign", "callAlertSound", "callAlertHaptic", "callAlertNotification",
        "watchedCallsigns", "watchAlertEnabled"
    ]

    private var viewModel: FT8ViewModel!
    private var alerter: MockCallAlerter!

    override func setUp() async throws {
        try await super.setUp()
        settingKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        viewModel = FT8ViewModel(txMessages: [], rxMessages: [])
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IN70"
        viewModel.autoSequencingEnabled = false
        viewModel.autoCQReplyEnabled = false
        alerter = MockCallAlerter()
        viewModel.callAlerter = alerter
    }

    override func tearDown() async throws {
        settingKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        viewModel = nil
        alerter = nil
        try await super.tearDown()
    }

    private func rx(_ text: String) -> FT8Message {
        FT8Message(text: text, mode: .ft8, isTX: false)
    }

    private func decode(_ texts: [String]) async {
        await viewModel.applyBatchUpdates(.test(messages: texts.map(rx)), slotIndex: nil)
    }

    // MARK: Defaults

    func test_defaults_highlightOnAlertsOff() {
        XCTAssertTrue(viewModel.highlightMyCallsign)
        XCTAssertTrue(viewModel.watchAlertEnabled)
        XCTAssertTrue(viewModel.watchList.isEmpty)
        XCTAssertFalse(viewModel.callAlertSound)
        XCTAssertFalse(viewModel.callAlertHaptic)
        XCTAssertFalse(viewModel.callAlertNotification)
    }

    func test_settingsPersist() {
        viewModel.callAlertSound = true
        viewModel.highlightMyCallsign = false
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "callAlertSound"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "highlightMyCallsign"))
    }

    // MARK: Highlight

    func test_highlight_onlyForCallsToUs() {
        XCTAssertTrue(viewModel.isCallingMeHighlighted(rx("EA1AAA DL2XYZ JO62")))
        XCTAssertFalse(viewModel.isCallingMeHighlighted(rx("F4ABC DL2XYZ JO62")))
        XCTAssertFalse(viewModel.isCallingMeHighlighted(rx("CQ DL2XYZ JO62")))
    }

    func test_highlight_offWhenDisabled() {
        viewModel.highlightMyCallsign = false
        XCTAssertFalse(viewModel.isCallingMeHighlighted(rx("EA1AAA DL2XYZ JO62")))
    }

    // MARK: Alerts

    func test_noAlert_whenAllAlertTogglesOff() async {
        await decode(["EA1AAA DL2XYZ JO62"])
        XCTAssertTrue(alerter.calls.isEmpty)
    }

    func test_alert_passesEnabledChannels() async {
        viewModel.callAlertSound = true
        viewModel.callAlertHaptic = false
        viewModel.callAlertNotification = true

        await decode(["EA1AAA DL2XYZ JO62"])

        XCTAssertEqual(alerter.calls.count, 1)
        let call = alerter.calls.first
        XCTAssertEqual(call?.kind, .callingMe)
        XCTAssertEqual(call?.message.text, "EA1AAA DL2XYZ JO62")
        XCTAssertEqual(call?.sound, true)
        XCTAssertEqual(call?.haptic, false)
        XCTAssertEqual(call?.notification, true)
    }

    func test_alert_firesOncePerSlot() async {
        viewModel.callAlertHaptic = true
        await decode(["EA1AAA DL2XYZ JO62", "EA1AAA G0ABC IO91"])
        XCTAssertEqual(alerter.calls.count, 1)
        XCTAssertEqual(alerter.calls.first?.message.text, "EA1AAA DL2XYZ JO62")
    }

    func test_noAlert_forOtherStationsTraffic() async {
        viewModel.callAlertHaptic = true
        await decode(["CQ F4ABC JN18", "F4ABC DL2XYZ JO62"])
        XCTAssertTrue(alerter.calls.isEmpty)
    }

    func test_noAlert_duringActiveQSO() async {
        viewModel.callAlertHaptic = true
        viewModel.qsoManager.qsoState = .listeningReport(dxCallsign: "DL2XYZ")
        await decode(["EA1AAA DL2XYZ -05"])
        XCTAssertTrue(alerter.calls.isEmpty)
    }

    func test_alert_whenOurCQIsAnswered() async {
        // The reply moves the QSO manager out of `.callingCQ` while the slot is
        // processed. The alert must use the state from the start of the slot.
        viewModel.callAlertHaptic = true
        viewModel.autoSequencingEnabled = true
        viewModel.qsoManager.qsoState = .callingCQ

        await decode(["EA1AAA DL2XYZ JO62"])

        XCTAssertEqual(alerter.calls.count, 1)
    }

    func test_alert_firesAfterCompletedOrTimedOutQSO() async {
        viewModel.callAlertHaptic = true
        viewModel.qsoManager.qsoState = .completed(dxCallsign: "F4ABC")
        await decode(["EA1AAA DL2XYZ JO62"])
        XCTAssertEqual(alerter.calls.count, 1)

        viewModel.qsoManager.qsoState = .timeout(dxCallsign: "F4ABC")
        await decode(["EA1AAA G0ABC IO91"])
        XCTAssertEqual(alerter.calls.count, 2)
    }

    func test_alert_whenOurCQIsAnsweredWithAutoReplyOn() async {
        viewModel.callAlertHaptic = true
        viewModel.autoSequencingEnabled = true
        viewModel.autoCQReplyEnabled = true
        viewModel.qsoManager.qsoState = .callingCQ

        await decode(["EA1AAA DL2XYZ JO62"])

        XCTAssertEqual(alerter.calls.count, 1)
        XCTAssertEqual(alerter.calls.first?.kind, .callingMe)
    }

    func test_noAlert_forOurOwnEchoInSlot() async {
        viewModel.callAlertHaptic = true
        let echo = FT8Message(text: "EA1AAA DL2XYZ JO62", mode: .ft8, isTX: true)
        await viewModel.applyBatchUpdates(.test(messages: [echo]), slotIndex: nil)
        XCTAssertTrue(alerter.calls.isEmpty)
    }

    func test_alert_soundHeldBackWhileTransmitting() async {
        viewModel.callAlertSound = true
        viewModel.callAlertHaptic = true
        viewModel.isTransmitting = true

        await decode(["EA1AAA DL2XYZ JO62"])

        XCTAssertEqual(alerter.calls.first?.sound, false)
        XCTAssertEqual(alerter.calls.first?.haptic, true)
    }

    // MARK: Watchlist

    private func watch(_ calls: String...) {
        viewModel.watchList = WatchList(callsigns: calls)
    }

    func test_watchList_persistsThroughStorage() {
        watch("3y0j", "VP8PJ")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "watchedCallsigns"), "3Y0J,VP8PJ")
        XCTAssertEqual(viewModel.watchList.callsigns, ["3Y0J", "VP8PJ"])
    }

    func test_rowHighlight_watchedSender() {
        watch("3Y0J")
        XCTAssertEqual(viewModel.rowHighlight(for: rx("CQ 3Y0J JD15")), .watched)
        XCTAssertEqual(viewModel.rowHighlight(for: rx("F4ABC 3Y0J -12")), .watched)
        XCTAssertEqual(viewModel.rowHighlight(for: rx("3Y0J F4ABC JN18")), .none)
        XCTAssertEqual(viewModel.rowHighlight(for: rx("CQ DL2XYZ JO62")), .none)
    }

    func test_rowHighlight_callToUsWinsOverWatched() {
        watch("3Y0J")
        XCTAssertEqual(viewModel.rowHighlight(for: rx("EA1AAA 3Y0J -12")), .callingMe)
    }

    func test_rowHighlight_ignoresOwnTransmission() {
        watch("3Y0J")
        let tx = FT8Message(text: "3Y0J EA1AAA IN70", mode: .ft8, isTX: true)
        XCTAssertEqual(viewModel.rowHighlight(for: tx), .none)
    }

    func test_watchedAlert_firesWithKind() async {
        viewModel.callAlertHaptic = true
        watch("3Y0J")
        await decode(["CQ 3Y0J JD15"])
        XCTAssertEqual(alerter.calls.count, 1)
        XCTAssertEqual(alerter.calls.first?.kind, .watched)
    }

    func test_watchedAlert_throttledPerStation() async {
        viewModel.callAlertHaptic = true
        watch("3Y0J", "VP8PJ")
        await decode(["CQ 3Y0J JD15"])
        await decode(["CQ 3Y0J JD15"])
        await decode(["CQ VP8PJ GD18"])
        XCTAssertEqual(alerter.calls.map(\.message.callsign), ["3Y0J", "VP8PJ"])
    }

    func test_watchedAlert_offWhenDisabled() async {
        viewModel.callAlertHaptic = true
        viewModel.watchAlertEnabled = false
        watch("3Y0J")
        await decode(["CQ 3Y0J JD15"])
        XCTAssertTrue(alerter.calls.isEmpty)
    }

    func test_watchedAlert_skippedWhileWorkingThatStation() async {
        viewModel.callAlertHaptic = true
        watch("3Y0J")
        viewModel.qsoManager.qsoState = .listeningReport(dxCallsign: "3Y0J")
        await decode(["F4ABC 3Y0J -12"])
        XCTAssertTrue(alerter.calls.isEmpty)
    }

    func test_watchedAlert_firesDuringAnotherQSO() async {
        viewModel.callAlertHaptic = true
        watch("3Y0J")
        viewModel.qsoManager.qsoState = .listeningReport(dxCallsign: "DL2XYZ")
        await decode(["CQ 3Y0J JD15"])
        XCTAssertEqual(alerter.calls.first?.kind, .watched)
    }

    func test_callToUsTakesPrecedenceOverWatchedInSameSlot() async {
        viewModel.callAlertHaptic = true
        watch("3Y0J")
        await decode(["CQ 3Y0J JD15", "EA1AAA DL2XYZ JO62"])
        XCTAssertEqual(alerter.calls.count, 1)
        XCTAssertEqual(alerter.calls.first?.kind, .callingMe)
    }
}

// MARK: - WatchList

final class WatchListTests: XCTestCase {

    func test_parsesAndNormalizesStorage() {
        let list = WatchList(storage: " 3y0j, vp8pj;K1ABC\n3Y0J ,,")
        XCTAssertEqual(list.callsigns, ["3Y0J", "VP8PJ", "K1ABC"])
        XCTAssertEqual(list.storage, "3Y0J,VP8PJ,K1ABC")
    }

    func test_emptyStorage() {
        XCTAssertTrue(WatchList(storage: "").isEmpty)
    }

    func test_addRejectsInvalidAndDuplicates() {
        var list = WatchList()
        XCTAssertTrue(list.add("3y0j"))
        XCTAssertFalse(list.add("3Y0J"))
        XCTAssertFalse(list.add("AB"))
        XCTAssertFalse(list.add("NODIGIT"))
        XCTAssertFalse(list.add("EA1-AAA"))
        XCTAssertFalse(list.add("ABCDEFGHIJ123"))
        XCTAssertEqual(list.callsigns, ["3Y0J"])
    }

    func test_remove() {
        var list = WatchList(callsigns: ["3Y0J", "VP8PJ"])
        list.remove("3y0j")
        XCTAssertEqual(list.callsigns, ["VP8PJ"])
        XCTAssertFalse(list.contains("3Y0J"))
    }

    func test_containsMatchesPortableAndPrefixedCalls() {
        let list = WatchList(callsigns: ["3Y0J", "EA1AAA"])
        XCTAssertTrue(list.contains("3y0j"))
        XCTAssertTrue(list.contains("3Y0J/P"))
        XCTAssertTrue(list.contains("EA8/EA1AAA"))
        XCTAssertFalse(list.contains("3Y0X"))
        XCTAssertFalse(list.contains(nil))
        XCTAssertFalse(list.contains(""))
    }
}

// MARK: - WatchAlertThrottle

final class WatchAlertThrottleTests: XCTestCase {

    func test_onePerStationPerInterval() {
        var throttle = WatchAlertThrottle(interval: 600)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(throttle.shouldAlert(for: "3Y0J", at: t0))
        XCTAssertFalse(throttle.shouldAlert(for: "3y0j", at: t0.addingTimeInterval(599)))
        XCTAssertTrue(throttle.shouldAlert(for: "VP8PJ", at: t0.addingTimeInterval(30)))
        XCTAssertTrue(throttle.shouldAlert(for: "3Y0J", at: t0.addingTimeInterval(600)))
    }
}

// MARK: - RowColorStore

final class RowColorStoreTests: XCTestCase {

    private let suite = "RowColorStoreTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_hexRoundTrip() {
        let color = Color(.sRGB, red: 1, green: 0.5, blue: 0)
        let hex = RowColorStore.hex(from: color)
        XCTAssertEqual(hex, "#FF8000")
        XCTAssertEqual(RowColorStore.hex(from: RowColorStore.color(fromHex: hex)!), hex)
    }

    func test_invalidHexIsRejected() {
        XCTAssertNil(RowColorStore.color(fromHex: "#12345"))
        XCTAssertNil(RowColorStore.color(fromHex: "#GGGGGG"))
        XCTAssertNotNil(RowColorStore.color(fromHex: "00FF00"))
    }

    func test_defaultsWhenNothingStored() {
        let store = RowColorStore(defaults: defaults)
        XCTAssertFalse(store.isCustomized)
        for kind in MessageRowColor.allCases {
            XCTAssertEqual(RowColorStore.hex(from: store.color(kind)),
                           RowColorStore.hex(from: kind.defaultColor), "\(kind)")
        }
    }

    func test_customColorPersistsAndResets() {
        let store = RowColorStore(defaults: defaults)
        store.setColor(Color(.sRGB, red: 0, green: 1, blue: 0), for: .finals)
        XCTAssertTrue(store.isCustomized)

        let reloaded = RowColorStore(defaults: defaults)
        XCTAssertEqual(RowColorStore.hex(from: reloaded.color(.finals)), "#00FF00")
        XCTAssertEqual(RowColorStore.hex(from: reloaded.color(.cq)),
                       RowColorStore.hex(from: MessageRowColor.cq.defaultColor))

        reloaded.resetToDefaults()
        XCTAssertFalse(reloaded.isCustomized)
        XCTAssertEqual(RowColorStore.hex(from: reloaded.color(.finals)),
                       RowColorStore.hex(from: MessageRowColor.finals.defaultColor))
    }
}
