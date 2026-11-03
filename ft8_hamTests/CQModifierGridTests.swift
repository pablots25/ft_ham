//
//  CQModifierGridTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 13/10/26.
//

import XCTest
@testable import ft8_ham

/// Regression: an operator activating with SOTA or POTA saw "CQ SOTA VE7ZAX CN8"
/// in the main screen. The composer and the encoder always carried the full
/// grid; the read-only field that shows the next message clipped the last
/// character. These tests pin the full grid through composition and the air,
/// and the display's ability to shrink a long message instead of clipping it.
final class CQModifierGridTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
        super.tearDown()
    }

    private func composedCQ(modifier: String, callsign: String = "VE7ZAX", locator: String = "CN89") -> String {
        UserDefaults.standard.set(modifier, forKey: "cqModifier")
        return FT8MessageComposer().generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: "", dxLocator: "",
            snrToSend: 0
        )[0]
    }

    private func assertSurvivesTheAir(_ message: String, mode: DigitalMode = .ft8, file: StaticString = #filePath, line: UInt = #line) {
        let engine = ft8_Engine()
        guard let audio = engine.generateAudio(message, frequency: 1400, mode: mode, toFile: nil) else {
            XCTFail("No audio generated for '\(message)'", file: file, line: line)
            return
        }
        let decoded = engine.decodeAudioBuffer(audio, sampleRate: 12_000, mode: mode)
            .compactMap { $0["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(decoded.contains(message), "'\(message)' decoded as \(decoded)", file: file, line: line)
    }

    // MARK: - Composition

    func test_sotaCQ_keepsTheFourCharacterGrid() {
        XCTAssertEqual(composedCQ(modifier: "SOTA"), "CQ SOTA VE7ZAX CN89")
    }

    func test_potaCQ_keepsTheFourCharacterGrid() {
        XCTAssertEqual(composedCQ(modifier: "POTA"), "CQ POTA VE7ZAX CN89")
    }

    func test_activationCQ_trimsASixCharacterLocatorToFour() {
        XCTAssertEqual(composedCQ(modifier: "SOTA", locator: "CN89ab"), "CQ SOTA VE7ZAX CN89")
    }

    // MARK: - On the air

    func test_sotaCQ_decodesWithTheFullGrid_FT8() {
        assertSurvivesTheAir(composedCQ(modifier: "SOTA"))
    }

    func test_potaCQ_decodesWithTheFullGrid_FT8() {
        assertSurvivesTheAir(composedCQ(modifier: "POTA"))
    }

    func test_wwffCQ_decodesWithTheFullGrid_FT4() {
        assertSurvivesTheAir(composedCQ(modifier: "WWFF"), mode: .ft4)
    }

    // MARK: - Display

    func test_selectedMessageField_canShrinkInsteadOfClipping() {
        // A fixed-size field cannot show a 19-character CQ between the
        // selector buttons; the field must be allowed to scale its text.
        XCTAssertLessThan(SelectedTXMessageField.minimumScaleFactor, 1)
        XCTAssertGreaterThan(SelectedTXMessageField.minimumScaleFactor, 0)
    }
}
