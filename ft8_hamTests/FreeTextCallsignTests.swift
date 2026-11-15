//
//  FreeTextCallsignTests.swift
//  ft_ham
//
//  A free-text station callsign, e.g. the listener (SWL) ID "EA40365FD" that
//  FEDIEA issues, which matches no ITU or 11 m grammar.
//

import XCTest
@testable import ft8_ham

// MARK: - Format and parsing

final class FreeTextCallsignTests: XCTestCase {

    /// The reported case: an SWL ID was impossible to enter.
    func test_isFreeTextFormat_acceptsSWLIdentifier() {
        XCTAssertTrue(CompoundCallsign.isFreeTextFormat("EA40365FD"))
        XCTAssertTrue(CompoundCallsign.isFreeTextFormat("ea40365fd"))
    }

    func test_isFreeTextFormat_rejectsInvalidShapes() {
        XCTAssertFalse(CompoundCallsign.isFreeTextFormat(""), "empty")
        XCTAssertFalse(CompoundCallsign.isFreeTextFormat("A1"), "too short")
        XCTAssertFalse(CompoundCallsign.isFreeTextFormat("ABCDEFGH12345"), "longer than the protocol can carry")
        XCTAssertFalse(CompoundCallsign.isFreeTextFormat("ABCDEF"), "letters only")
        XCTAssertFalse(CompoundCallsign.isFreeTextFormat("123456"), "digits only")
        XCTAssertFalse(CompoundCallsign.isFreeTextFormat("EA4/12345"), "slashes are not free text")
        XCTAssertFalse(CompoundCallsign.isFreeTextFormat("EA-40365"), "punctuation is not allowed")
    }

    /// A free-text call must never be confused with a message field.
    func test_isFreeTextFormat_rejectsMessageFields() {
        for text in ["IN80", "RR73", "R+12", "R-08"] {
            XCTAssertFalse(CompoundCallsign.isFreeTextFormat(text), "\(text) is a message field")
        }
    }

    func test_parse_acceptsOnlyTheRegisteredStationCall() {
        let parsed = CompoundCallsign.parse("EA40365FD", freeTextStation: "EA40365FD")
        XCTAssertEqual(parsed?.kind, .freeText)
        XCTAssertTrue(parsed?.isFreeText ?? false)
        XCTAssertEqual(parsed?.text, "EA40365FD")
        XCTAssertFalse(parsed?.isCompound ?? true)
    }

    /// Any other free-form token in a decoded message is still not a callsign.
    func test_parse_rejectsOtherFreeTextTokens() {
        XCTAssertNil(CompoundCallsign.parse("EA40365FD", freeTextStation: nil))
        XCTAssertNil(CompoundCallsign.parse("EA99999XY", freeTextStation: "EA40365FD"))
    }

    /// Amateur and 11 m calls keep their kind even when free text is on.
    func test_parse_otherKindsAreUnaffected() {
        XCTAssertEqual(CompoundCallsign.parse("EA4IQL", freeTextStation: "EA40365FD")?.kind, .standard)
        XCTAssertEqual(CompoundCallsign.parse("26TE231", freeTextStation: "EA40365FD")?.kind, .elevenMeter)
    }

    /// A free-text call has no ITU structure, so it always travels as type-4.
    func test_freeTextCall_isNotStandardPackable() {
        let parsed = CompoundCallsign.parse("EA40365FD", freeTextStation: "EA40365FD")
        XCTAssertEqual(parsed?.isStandardPackable, false)
    }
}

// MARK: - Opt-in stored in UserDefaults

final class FreeTextCallsignRegistrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "FreeTextCallsignRegistrationTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_registered_requiresOptIn() {
        defaults.set("EA40365FD", forKey: CompoundCallsign.stationCallsignKey)
        XCTAssertNil(CompoundCallsign.registeredFreeTextCallsign(in: defaults))

        defaults.set(true, forKey: CompoundCallsign.freeTextOptInKey)
        XCTAssertEqual(CompoundCallsign.registeredFreeTextCallsign(in: defaults), "EA40365FD")
    }

    func test_registered_normalisesStoredCase() {
        defaults.set(true, forKey: CompoundCallsign.freeTextOptInKey)
        defaults.set("ea40365fd", forKey: CompoundCallsign.stationCallsignKey)
        XCTAssertEqual(CompoundCallsign.registeredFreeTextCallsign(in: defaults), "EA40365FD")
    }

    func test_registered_ignoresCallsThatAreNotFreeText() {
        defaults.set(true, forKey: CompoundCallsign.freeTextOptInKey)
        defaults.set("EA4/12345", forKey: CompoundCallsign.stationCallsignKey)
        XCTAssertNil(CompoundCallsign.registeredFreeTextCallsign(in: defaults))
    }
}

// MARK: - Station callsign validation

final class FreeTextStationCallsignTests: XCTestCase {

    /// The reported case: rejected today, accepted once the operator opts in.
    func test_stationCallsign_gatesFreeTextOnOptIn() {
        XCTAssertFalse(isValidStationCallsign("EA40365FD", allowElevenMeter: false))
        XCTAssertFalse(isValidStationCallsign("EA40365FD", allowElevenMeter: true))
        XCTAssertTrue(isValidStationCallsign("EA40365FD", allowElevenMeter: false, allowFreeText: true))
    }

    func test_stationCallsign_amateurCallsAreUnaffected() {
        for allow in [false, true] {
            XCTAssertTrue(isValidStationCallsign("EA4IQL", allowElevenMeter: false, allowFreeText: allow))
            XCTAssertTrue(isValidStationCallsign("I/VE6XAD", allowElevenMeter: false, allowFreeText: allow))
        }
    }

    /// The 11 m opt-in keeps working on its own, and free text also covers an
    /// 11 m-shaped ID for an operator who only ticked free text.
    func test_stationCallsign_elevenMeterAndFreeText() {
        XCTAssertTrue(isValidStationCallsign("26TE231", allowElevenMeter: true, allowFreeText: false))
        XCTAssertTrue(isValidStationCallsign("26TE231", allowElevenMeter: false, allowFreeText: true))
        XCTAssertFalse(isValidStationCallsign("26TE231", allowElevenMeter: false, allowFreeText: false))
    }

    func test_stationCallsign_freeTextStillRejectsMessageFields() {
        for text in ["IN80", "RR73", "CQ", "ABC", "12345"] {
            XCTAssertFalse(
                isValidStationCallsign(text, allowElevenMeter: true, allowFreeText: true),
                "\(text) should be rejected"
            )
        }
    }
}

// MARK: - Composing, transmitting and recognising a free-text callsign

final class FreeTextCallsignMessageTests: XCTestCase {

    private let call = "EA40365FD"
    private var savedCallsign: Any?
    private var savedOptIn: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedCallsign = defaults.object(forKey: CompoundCallsign.stationCallsignKey)
        savedOptIn = defaults.object(forKey: CompoundCallsign.freeTextOptInKey)
        defaults.set(call, forKey: CompoundCallsign.stationCallsignKey)
        defaults.set(true, forKey: CompoundCallsign.freeTextOptInKey)
        defaults.set("NONE", forKey: "cqModifier")
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        restore(savedCallsign, forKey: CompoundCallsign.stationCallsignKey)
        restore(savedOptIn, forKey: CompoundCallsign.freeTextOptInKey)
        defaults.removeObject(forKey: "cqModifier")
        super.tearDown()
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// With the opt-in on, the stored call counts as a configured callsign, so
    /// RX can start (`settingsLoaded` relies on `isValidCallsign`).
    func test_isValidCallsign_acceptsRegisteredStationCall() {
        XCTAssertTrue(isValidCallsign(call))
        UserDefaults.standard.set(false, forKey: CompoundCallsign.freeTextOptInKey)
        XCTAssertFalse(isValidCallsign(call))
    }

    /// Like any non-standard call, it is spelled out with no grid.
    func test_composer_sendsFreeTextCallWithoutGrid() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: call,
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN20",
            snrToSend: -10
        )
        XCTAssertEqual(messages[0], "CQ \(call)")
        XCTAssertEqual(messages[1], "K1ABC \(call)")
    }

    /// A message addressed to the free-text call is recognised as mine.
    func test_messageToMyFreeTextCall_isForMe() {
        let participants = FT8Message.parseParticipants(
            parts: "<\(call)> K1ABC -12".split(separator: " ")
        )
        XCTAssertEqual(participants.receiverCallsign, call)
        XCTAssertTrue(FT8Message.isForMe(participants: participants, myCallsign: call, isTX: false))
    }

    /// A CQ from the free-text call has to come off the air spelled out.
    func test_cqFromFreeTextCall_survivesTheAir() throws {
        let engine = ft8_Engine()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let message = "CQ \(call)"
        let audio = engine.generateFT8(message, frequency: 1400, isFT4: false, toFile: url)
        XCTAssertNotNil(audio, "No audio generated for '\(message)'")

        let decoded = engine.decode(url, isFT4: false)
            .compactMap { $0["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(decoded.contains(message), "'\(message)' decoded as \(decoded)")
    }
}
