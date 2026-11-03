//
//  FT8EngineFreeTextTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
@testable import ft8_ham

/// Round-trips free text through the real encoder and decoder (pure DSP,
/// no audio hardware involved).
final class FT8EngineFreeTextTests: XCTestCase {

    private func roundTrip(_ text: String, mode: DigitalMode = .ft8, file: StaticString = #filePath, line: UInt = #line) {
        let engine = ft8_Engine()
        guard let audio = engine.generateFreeText(text, frequency: 1400, mode: mode) else {
            XCTFail("No audio generated for '\(text)'", file: file, line: line)
            return
        }
        XCTAssertGreaterThan(audio.count, 12_000 * 4, "audio is too short", file: file, line: line)

        let decoded = engine.decodeAudioBuffer(audio, sampleRate: 12_000, mode: mode)
            .compactMap { $0["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(decoded.contains(text), "'\(text)' decoded as \(decoded)", file: file, line: line)
    }

    func test_freeText_survivesTheAir_FT8() {
        roundTrip("TNX 73 GL")
    }

    func test_freeText_thatLooksLikeCallsigns_isStillSentAsFreeText() {
        // "HELLO WORLD" would be mangled into hashed callsigns by the standard
        // packers; the free-text entry point must keep it verbatim.
        roundTrip("HELLO WORLD")
    }

    func test_freeText_fullLengthAndPunctuation() {
        roundTrip("QRT +73/GL?")
        roundTrip("ABCDEFGHIJKLM")
    }

    func test_freeText_FT4() {
        roundTrip("TEST FT4", mode: .ft4)
    }

    func test_freeText_rejectsTextThatDoesNotFit() {
        let engine = ft8_Engine()
        XCTAssertNil(engine.generateFreeText("FOURTEEN CHARS", frequency: 1400, mode: .ft8))
        XCTAssertNil(engine.generateFreeText("lowercase", frequency: 1400, mode: .ft8))
    }
}
