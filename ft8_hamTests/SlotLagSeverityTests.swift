//
//  SlotLagSeverityTests.swift
//  ft8_hamTests
//
//  Late slots in 1.3.1 were reported as non-fatals even when nothing was due
//  to transmit (RX keeps capturing through a skipped slot). These cover how a
//  late slot is classified and how the lag is split into phases.
//

import XCTest
@testable import ft8_ham

final class SlotLagSeverityTests: XCTestCase {

    // MARK: - slotLagSeverity

    func test_severity_withinThresholdIsOnTime() {
        XCTAssertEqual(
            FT8ViewModel.slotLagSeverity(lag: 1.9, isFT4: false, applicationState: .active, transmitDue: true),
            .onTime)
        XCTAssertEqual(
            FT8ViewModel.slotLagSeverity(lag: FT8ViewModel.maxSlotLag, isFT4: false,
                                         applicationState: .active, transmitDue: true),
            .onTime)
    }

    /// The 1.3.1 events were mostly 2.0 to 4.1 s late while active.
    func test_severity_activeStallWithoutTXIsAReceiveStall() {
        for lag in [2.012, 2.31, 4.13, 9.08] {
            XCTAssertEqual(
                FT8ViewModel.slotLagSeverity(lag: lag, isFT4: false, applicationState: .active, transmitDue: false),
                .receiveStall, "lag \(lag)s")
        }
    }

    func test_severity_activeStallWithTXDueIsATransmitStall() {
        XCTAssertEqual(
            FT8ViewModel.slotLagSeverity(lag: 2.31, isFT4: false, applicationState: .active, transmitDue: true),
            .transmitStall)
    }

    func test_severity_notActiveIsExpectedEvenWithTXDue() {
        for state in [UIApplication.State.inactive, .background] {
            XCTAssertEqual(
                FT8ViewModel.slotLagSeverity(lag: 3.0, isFT4: false, applicationState: state, transmitDue: true),
                .expected, "state \(state.rawValue)")
        }
    }

    func test_severity_suspensionGapIsExpectedEvenWithTXDue() {
        XCTAssertEqual(
            FT8ViewModel.slotLagSeverity(lag: 15.5, isFT4: false, applicationState: .active, transmitDue: true),
            .expected)
        XCTAssertEqual(
            FT8ViewModel.slotLagSeverity(lag: 8.0, isFT4: true, applicationState: .active, transmitDue: true),
            .expected)
    }

    // MARK: - lagBreakdown

    func test_breakdown_splitsWakeAndHarvest() {
        XCTAssertEqual(FT8ViewModel.lagBreakdown(lag: 2.313, wakeLag: 0.012),
                       "wake 0.012s, harvest 2.301s")
    }

    func test_breakdown_lateWakeLeavesNoHarvest() {
        XCTAssertEqual(FT8ViewModel.lagBreakdown(lag: 3.5, wakeLag: 3.5),
                       "wake 3.500s, harvest 0.000s")
    }

    /// Clock reads can cross by a hair; harvest never goes negative.
    func test_breakdown_clampsNegativeHarvest() {
        XCTAssertEqual(FT8ViewModel.lagBreakdown(lag: 2.0, wakeLag: 2.001),
                       "wake 2.001s, harvest 0.000s")
    }

    func test_breakdown_withoutWakeLag() {
        XCTAssertEqual(FT8ViewModel.lagBreakdown(lag: 2.5, wakeLag: nil), "phases unknown")
    }

    // MARK: - isTransmitDue / determineAction

    @MainActor
    private func makeViewModel() -> FT8ViewModel {
        let viewModel = FT8ViewModel(audioManager: MockAudioManager(), engine: MockMessageDecoder())
        viewModel.applicationState = { .active }
        viewModel.txSlotPreference = .forceEven
        viewModel.transmitLoopActive = false
        viewModel.freeTextLoopActive = false
        viewModel.isReadyForTX = false
        return viewModel
    }

    private func slot(even: Bool, lag: TimeInterval = 0) -> SlotInfo {
        SlotInfo(startTime: AppClock.now().addingTimeInterval(-lag),
                 slotIndex: even ? 10 : 11, isEven: even, isFT4: false)
    }

    @MainActor
    func test_isTransmitDue_idleIsFalse() {
        XCTAssertFalse(makeViewModel().isTransmitDue(slot(even: true)))
    }

    @MainActor
    func test_isTransmitDue_freeTextOnMyParityOnly() {
        let viewModel = makeViewModel()
        viewModel.freeTextLoopActive = true
        XCTAssertTrue(viewModel.isTransmitDue(slot(even: true)))
        XCTAssertFalse(viewModel.isTransmitDue(slot(even: false)))
    }

    /// Checking whether TX is due must not consume the immediate-response flag.
    @MainActor
    func test_isTransmitDue_doesNotClearReadyForTX() {
        let viewModel = makeViewModel()
        viewModel.isReadyForTX = true
        XCTAssertTrue(viewModel.isTransmitDue(slot(even: true)))
        XCTAssertTrue(viewModel.isReadyForTX)
    }

    @MainActor
    func test_determineAction_readyForTXTransmitsAndClearsTheFlag() {
        let viewModel = makeViewModel()
        viewModel.isReadyForTX = true
        XCTAssertEqual(viewModel.determineAction(for: slot(even: true)), .transmit)
        XCTAssertFalse(viewModel.isReadyForTX)
    }

    @MainActor
    func test_determineAction_readyForTXOffParityKeepsTheFlag() {
        let viewModel = makeViewModel()
        viewModel.isReadyForTX = true
        XCTAssertEqual(viewModel.determineAction(for: slot(even: false)), .receive)
        XCTAssertTrue(viewModel.isReadyForTX)
    }

    /// Only the log level depends on whether TX was due: a late slot is skipped either way.
    @MainActor
    func test_determineAction_lateSlotIsSkippedWithOrWithoutTX() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.determineAction(for: slot(even: true, lag: 3), wakeLag: 0.01), .skip)
        viewModel.freeTextLoopActive = true
        XCTAssertEqual(viewModel.determineAction(for: slot(even: true, lag: 3), wakeLag: 0.01), .skip)
    }

    /// A skipped late slot leaves the immediate-response flag for the next slot, as before.
    @MainActor
    func test_determineAction_lateSlotKeepsReadyForTX() {
        let viewModel = makeViewModel()
        viewModel.isReadyForTX = true
        XCTAssertEqual(viewModel.determineAction(for: slot(even: true, lag: 3)), .skip)
        XCTAssertTrue(viewModel.isReadyForTX)
    }
}
