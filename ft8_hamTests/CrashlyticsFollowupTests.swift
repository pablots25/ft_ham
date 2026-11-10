// CrashlyticsFollowupTests.swift
// ft8_hamTests
//
// Regression tests for the Crashlytics review of 1.3.0 (23), November 2026.
//
//   1. 93f6a2a7 — "Failed to start audio engine ... error -50" from
//      recoverAudioIfNeeded() right after activation. Nothing retried it, so RX
//      stayed silent for minutes. Defence: an engine reset on a failed start,
//      timed retries, and the context of the failure in the non-fatal.
//   2. 8fc06c9e — "Attempting to log QSO without valid SNRs" from the Log QSO
//      button. Both reports were stored as "Invalid", the valid one included,
//      and exported to ADIF. Defence: a missing report is left empty, the ADIF
//      field is left out, and the manual log is a warning.
//   3. e6eaeaf5 — "Error showing notification: Source is not authorized" is the
//      user's choice, not a bug, so it no longer records a non-fatal.
//   4. The log sanitizer let lowercase and mixed-case callsigns through.
//   5. A TX audio generation failure showed nothing to the user.

import XCTest
import UserNotifications
@testable import ft8_ham

@MainActor
final class CrashlyticsFollowupTests: XCTestCase {

    // MARK: - 1. Audio engine recovery

    func test_audioRecoveryRetryDelays_areIncreasingAndBounded() {
        let delays = AudioManager.audioRecoveryRetryDelays
        XCTAssertFalse(delays.isEmpty)
        XCTAssertEqual(delays, delays.sorted(), "Each retry should wait at least as long as the previous one")
        let total = delays.reduce(Duration.zero, +)
        XCTAssertLessThanOrEqual(total, .seconds(15), "Recovery should give up within one FT8 slot")
    }

    func test_needsAudioRecovery_whenTheSessionNeverCameUp() {
        XCTAssertTrue(AudioManager.needsAudioRecovery(
            isSessionConfigured: false, wantsMicInput: false, isListening: false))
    }

    func test_needsAudioRecovery_whenRXIsWantedWithoutATap() {
        XCTAssertTrue(AudioManager.needsAudioRecovery(
            isSessionConfigured: true, wantsMicInput: true, isListening: false))
    }

    func test_needsAudioRecovery_notWhenRXIsListening() {
        XCTAssertFalse(AudioManager.needsAudioRecovery(
            isSessionConfigured: true, wantsMicInput: true, isListening: true))
    }

    func test_needsAudioRecovery_notWhenRXIsOff() {
        XCTAssertFalse(AudioManager.needsAudioRecovery(
            isSessionConfigured: true, wantsMicInput: false, isListening: false))
    }

    func test_audioRecoveryRetry_stopsOnceTheSetupRecovers() async {
        var attempts = 0
        let recovered = await AudioManager.retryMicTap(
            delays: AudioManager.audioRecoveryRetryDelays,
            sleep: { _ in }
        ) { _ in
            attempts += 1
            return attempts == 2
        }

        XCTAssertTrue(recovered)
        XCTAssertEqual(attempts, 2)
    }

    func test_engineStartDiagnostics_listsTheStateThatTellsCausesApart() {
        let text = AudioManager.engineStartDiagnostics(
            recordPermission: "granted",
            isInputAvailable: false,
            hardwareSampleRate: 48_000,
            inputChannels: 0,
            inputFormat: (sampleRate: 0, channels: 0),
            inputPorts: [],
            outputPorts: ["Speaker"],
            appState: "active"
        )

        XCTAssertEqual(
            text,
            "(mic: granted, input available: false, HW: 48000 Hz 0 ch, input node: 0 Hz 0 ch, "
                + "route: none -> Speaker, app: active)"
        )
    }

    func test_engineStartDiagnostics_withoutAnInputNode() {
        let text = AudioManager.engineStartDiagnostics(
            recordPermission: "undetermined",
            isInputAvailable: true,
            hardwareSampleRate: 44_100,
            inputChannels: 1,
            inputFormat: nil,
            inputPorts: ["MicrophoneBuiltIn"],
            outputPorts: ["Speaker", "BluetoothA2DPOutput"],
            appState: "unknown"
        )

        XCTAssertTrue(text.contains("input node: none"))
        XCTAssertTrue(text.contains("route: MicrophoneBuiltIn -> Speaker,BluetoothA2DPOutput"))
        XCTAssertTrue(text.contains("mic: undetermined"))
    }

    func test_engineStartDiagnostics_surviveTheSanitizer() {
        let text = AudioManager.engineStartDiagnostics(
            recordPermission: "granted",
            isInputAvailable: true,
            hardwareSampleRate: 48_000,
            inputChannels: 1,
            inputFormat: (sampleRate: 48_000, channels: 1),
            inputPorts: ["USBAudio"],
            outputPorts: ["BluetoothHFP"],
            appState: "active"
        )

        XCTAssertEqual(AppLogger(category: "TEST").sanitize(text), text)
    }

    func test_engineStartFailure_stillMapsToTheEngineToast() {
        let error = AudioManagerError.engineStartFailed(
            underlying: NSError(domain: "com.apple.coreaudio.avfaudio", code: -50)
        )
        XCTAssertEqual(AudioErrorToastText.kind(of: error.localizedDescription), .engineStart)
    }

    // MARK: - 2. Missing signal reports

    func test_storedReport_keepsAValidReport() {
        XCTAssertEqual(LogEntry.storedReport(snr: -7), "-7")
        XCTAssertEqual(LogEntry.storedReport(snr: 0), "0")
    }

    func test_storedReport_leavesAMissingReportEmpty() {
        XCTAssertEqual(LogEntry.storedReport(snr: Int.min), "")
    }

    func test_adifReport_leavesOutEmptyAndLegacyInvalidReports() {
        XCTAssertNil(LogEntry.adifReport(""))
        XCTAssertNil(LogEntry.adifReport("  "))
        XCTAssertNil(LogEntry.adifReport("Invalid"))
        XCTAssertNil(LogEntry.adifReport("INVALID"))
        XCTAssertEqual(LogEntry.adifReport("-12"), "-12")
        XCTAssertEqual(LogEntry.adifReport("+05"), "+05")
    }

    func test_forceLog_keepsTheSentReportWhenTheReceivedOneIsMissing() {
        let manager = QSOStatusManager()

        let entry = manager.createLogEntry(
            dxCallsign: "K1ABC",
            dxLocator: "FN20",
            qsoDate: Date(timeIntervalSince1970: 1_700_000_000),
            band: .band20m,
            isFT4: false,
            rstSent: -1,
            rstRcvd: Int.min,
            isManualLog: true
        )

        XCTAssertEqual(entry.rstSent, "-1")
        XCTAssertEqual(entry.rstRcvd, "")
    }

    func test_logEntry_withBothReportsMissing_leavesBothEmpty() {
        let manager = QSOStatusManager()

        let entry = manager.createLogEntry(
            dxCallsign: "K1ABC",
            dxLocator: "FN20",
            qsoDate: Date(timeIntervalSince1970: 1_700_000_000),
            band: .band20m,
            isFT4: false,
            rstSent: Int.min,
            rstRcvd: Int.min
        )

        XCTAssertEqual(entry.rstSent, "")
        XCTAssertEqual(entry.rstRcvd, "")
    }

    func test_syncADIF_leavesOutAMissingReport() {
        let adif = LogSyncManager.shared.buildSingleEntryADIF(entry(rstSent: "-1", rstRcvd: ""))

        XCTAssertTrue(adif.contains("<RST_SENT:2>-1 "))
        XCTAssertFalse(adif.contains("RST_RCVD"))
    }

    func test_syncADIF_leavesOutALegacyInvalidReport() {
        let adif = LogSyncManager.shared.buildSingleEntryADIF(entry(rstSent: "Invalid", rstRcvd: "Invalid"))

        XCTAssertFalse(adif.contains("RST_SENT"))
        XCTAssertFalse(adif.contains("RST_RCVD"))
        XCTAssertFalse(adif.contains("Invalid"))
    }

    func test_exportADIF_leavesOutAMissingReport() throws {
        let url = try XCTUnwrap(LogbookManager().exportToADIF([entry(rstSent: "Invalid", rstRcvd: "-15")]))
        let content = try String(contentsOf: url, encoding: .utf8)

        XCTAssertFalse(content.contains("RST_SENT"))
        XCTAssertFalse(content.contains("Invalid"))
        XCTAssertTrue(content.contains("<RST_RCVD:3>-15 "))
    }

    // MARK: - 3. Notifications turned off

    func test_notificationError_whenNotAllowed_isAWarning() {
        let error = UNError(.notificationsNotAllowed)
        XCTAssertEqual(FT8ViewModel.notificationErrorLevel(for: error), .warning)
    }

    func test_notificationError_otherwise_isAnError() {
        XCTAssertEqual(FT8ViewModel.notificationErrorLevel(for: UNError(.attachmentInvalidURL)), .error)
        XCTAssertEqual(
            FT8ViewModel.notificationErrorLevel(for: NSError(domain: "test", code: 1)),
            .error
        )
    }

    // MARK: - 4. Sanitizer

    private let logger = AppLogger(category: "TEST")

    func test_sanitize_redactsLowercaseAndMixedCaseCallsigns() {
        XCTAssertEqual(logger.sanitize("QSO with ea4iql"), "QSO with [CALLSIGN]")
        XCTAssertEqual(logger.sanitize("Ea4Iql/P"), "[CALLSIGN]/P")
        XCTAssertEqual(logger.sanitize("m0abc 73"), "[CALLSIGN] 73")
    }

    func test_sanitize_redactsPrefixesThatStartWithADigitOrHaveThreeCharacters() {
        XCTAssertEqual(logger.sanitize("CQ 8J1RL"), "CQ [CALLSIGN]")
        XCTAssertEqual(logger.sanitize("CQ 3DA0RU"), "CQ [CALLSIGN]")
        XCTAssertEqual(logger.sanitize("2E0ABC"), "[CALLSIGN]")
    }

    func test_sanitize_keepsTechnicalText() {
        let messages = [
            "Failed to start audio engine (com.apple.coreaudio.avfaudio error -50.)",
            "Mic tap installed at 44100Hz",
            "Device iPhone18,3 on 1.3.0 (23)",
            "FT8/FT4 cycle on ft8_ham.AUDIO",
            "HW SR: 48000.0",
        ]
        for message in messages {
            XCTAssertEqual(logger.sanitize(message), message, message)
        }
    }

    // MARK: - 5. TX audio generation

    func test_audioGenerationFailure_mapsToTheTXAudioToast() {
        XCTAssertEqual(
            AudioErrorToastText.kind(of: FT8ViewModel.Constants.audioGenerationFailedMessage),
            .txAudio
        )
    }

    // MARK: - 6. Editing a QSO with a missing report

    func test_editableReport_startsMissingAndLegacyInvalidReportsEmpty() {
        XCTAssertEqual(LogEntry.editableReport(""), "")
        XCTAssertEqual(LogEntry.editableReport("Invalid"), "")
        XCTAssertEqual(LogEntry.editableReport("invalid"), "")
    }

    func test_editableReport_keepsAValidReport() {
        XCTAssertEqual(LogEntry.editableReport("-7"), "-7")
        XCTAssertEqual(LogEntry.editableReport(" +05 "), "+05")
    }

    func test_displayReport_showsAPlaceholderForAMissingReport() {
        XCTAssertEqual(LogEntry.displayReport(""), LogEntry.missingReportPlaceholder)
        XCTAssertEqual(LogEntry.displayReport("Invalid"), LogEntry.missingReportPlaceholder)
        XCTAssertEqual(LogEntry.displayReport("-12"), "-12")
    }

    func test_displayReport_placeholderIsNotANumber() {
        XCTAssertNil(Int(LogEntry.missingReportPlaceholder))
        XCTAssertFalse(LogEntry.missingReportPlaceholder.isEmpty)
    }

    func test_editedReport_isExportedToADIF() {
        let edited = entry(rstSent: LogEntry.editableReport("Invalid"), rstRcvd: "-15")
        let adif = LogSyncManager.shared.buildSingleEntryADIF(edited)

        XCTAssertFalse(adif.contains("RST_SENT"))
        XCTAssertTrue(adif.contains("<RST_RCVD:3>-15 "))
    }

    // MARK: - Helpers

    private func entry(rstSent: String, rstRcvd: String) -> LogEntry {
        LogEntry(
            callsign: "K1ABC",
            grid: "FN20",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: rstSent,
            rstRcvd: rstRcvd,
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
    }
}
