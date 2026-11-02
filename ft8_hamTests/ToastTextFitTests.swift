//
//  ToastTextFitTests.swift
//  ft8_hamTests
//
//  Toast warnings are written to fit two lines on the narrowest iPhone at the
//  default text size, in every language. Audio errors show a short message
//  instead of the raw technical text.
//

import UIKit
import XCTest
@testable import ft8_ham

final class ToastTextFitTests: XCTestCase {

    /// 375 pt screen minus the toast's outer padding (24 + 24), its inner
    /// padding (14 + 20), the 22 pt badge and the 12 pt spacing.
    private static let textWidth: CGFloat = 375 - 48 - 34 - 22 - 12

    private static let keys = [
        "Couldn't set up audio. Check your audio device.",
        "Audio couldn't start. Check your audio device.",
        "Can't read the audio input. Check your audio device.",
        "No audio output. Check your audio device.",
        "Couldn't create the TX audio.",
        "Check your callsign and locator in Configuration.",
        "Audio problem. Check your audio device.",
        "cat_ptt_failed_toast",
        "bg_toast_message",
    ]

    private func lineCount(_ text: String) -> Int {
        let base = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: .medium)
        let height = (text as NSString).boundingRect(
            with: CGSize(width: Self.textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
        return Int((height / font.lineHeight).rounded())
    }

    func testToastWarningsFitTwoLinesInEveryLanguage() throws {
        for language in ["en", "de", "es", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in Self.keys {
                let text = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(text, "cat_ptt_failed_toast", language)
                XCTAssertLessThanOrEqual(lineCount(text), 2, "\(language): \(text)")
            }
        }
    }

    // MARK: - Audio error wording

    func testAudioManagerErrorsMapToShortMessages() {
        struct Underlying: LocalizedError {
            var errorDescription: String? { "The operation couldn’t be completed. (com.apple.coreaudio.avfaudio error -10868.)" }
        }
        let cases: [(AudioManagerError, AudioErrorToastText.Kind)] = [
            (.sessionCategoryConfiguration(underlying: Underlying()), .setup),
            (.sessionModeConfiguration(underlying: Underlying()), .setup),
            (.sessionSampleRateConfiguration(underlying: Underlying()), .setup),
            (.sessionActivationFailed(underlying: Underlying()), .setup),
            (.invalidInputFormat(sampleRate: 0, channels: 0), .setup),
            (.engineStartFailed(underlying: Underlying()), .engineStart),
            (.tapInstallationFailed(underlying: Underlying()), .microphone),
            (.audioGenerationFailed(message: "CQ EA4IQL IN80"), .txAudio),
            (.invalidAudioData, .txAudio),
        ]
        for (error, kind) in cases {
            let raw = error.localizedDescription
            XCTAssertEqual(AudioErrorToastText.kind(of: raw), kind, raw)
            XCTAssertFalse(AudioErrorToastText.message(for: raw).contains("-10868"), raw)
        }
    }

    func testOtherAudioMessagesMapToShortMessages() {
        XCTAssertEqual(AudioErrorToastText.kind(of: "No audio output available. Check your audio device connection."), .noOutput)
        XCTAssertEqual(AudioErrorToastText.kind(of: "Audio engine not running after start, skipping playback"), .engineStart)
        XCTAssertEqual(AudioErrorToastText.kind(of: "Invalid callsign/locator"), .station)
        XCTAssertEqual(AudioErrorToastText.kind(of: "Something unexpected"), .unknown)
        XCTAssertFalse(AudioErrorToastText.message(for: "Something unexpected").isEmpty)
    }

    /// One-line toasts are 44 pt tall, so the corner radius keeps the capsule look.
    func testToastCornerRadiusDrawsACapsuleForOneLine() {
        XCTAssertEqual(ToastShape.cornerRadius, 22)
    }
}
