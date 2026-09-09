// CompoundCallsignTests.swift
// ft8_hamTests
//
// Tests for compound (portable / travelling) callsigns: "I/VE6XAD" for a
// Canadian station operating from Italy, "VE6XAD/P" for the same station
// operating portable, and everything that has to follow from accepting them —
// country resolution, message composition and decoding.

import XCTest
@testable import ft8_ham

final class CompoundCallsignTests: XCTestCase {

    // MARK: - Parsing

    func test_parse_plainCallsign_hasNoModifier() {
        let call = CompoundCallsign.parse("VE6XAD")
        XCTAssertEqual(call?.baseCall, "VE6XAD")
        XCTAssertNil(call?.modifier)
        XCTAssertFalse(call?.isCompound ?? true)
    }

    /// The reported case: a foreign prefix in front of the base call.
    func test_parse_foreignPrefix_isAccepted() {
        let call = CompoundCallsign.parse("I/VE6XAD")
        XCTAssertEqual(call?.baseCall, "VE6XAD")
        XCTAssertEqual(call?.modifier, .prefix("I"))
        XCTAssertEqual(call?.text, "I/VE6XAD")
    }

    /// The same station written the other way round.
    func test_parse_foreignSuffix_isAccepted() {
        let call = CompoundCallsign.parse("VE6XAD/I")
        XCTAssertEqual(call?.baseCall, "VE6XAD")
        XCTAssertEqual(call?.modifier, .suffix("I"))
    }

    func test_parse_multiCharacterPrefix_isAccepted() {
        XCTAssertEqual(CompoundCallsign.parse("EA6/K1ABC")?.modifier, .prefix("EA6"))
        XCTAssertEqual(CompoundCallsign.parse("KH6/W1AW")?.modifier, .prefix("KH6"))
        XCTAssertEqual(CompoundCallsign.parse("3DA0/G3ABC")?.modifier, .prefix("3DA0"))
    }

    func test_parse_operatingSuffixes_areAccepted() {
        for suffix in ["P", "M", "MM", "AM", "QRP", "R", "1", "ABC"] {
            XCTAssertNotNil(
                CompoundCallsign.parse("EA4IQL/\(suffix)"),
                "EA4IQL/\(suffix) should be a valid callsign"
            )
        }
    }

    func test_parse_lowercase_isNormalised() {
        XCTAssertEqual(CompoundCallsign.parse("i/ve6xad")?.text, "I/VE6XAD")
    }

    // MARK: - Parsing: rejections

    func test_parse_twoModifiers_isRejected() {
        XCTAssertNil(CompoundCallsign.parse("EA4IQL/P/MM"))
        XCTAssertNil(CompoundCallsign.parse("I/VE6XAD/P"))
    }

    /// A non-standard callsign travels as 11 characters of plain text.
    func test_parse_longerThanProtocolLimit_isRejected() {
        XCTAssertNil(CompoundCallsign.parse("3DA0/AB12XYZ"))   // 12 characters
        XCTAssertNotNil(CompoundCallsign.parse("3DA/AB12XYZ")) // 11 characters
    }

    func test_parse_danglingSlash_isRejected() {
        XCTAssertNil(CompoundCallsign.parse("VE6XAD/"))
        XCTAssertNil(CompoundCallsign.parse("/VE6XAD"))
    }

    func test_parse_modifierOnBothSidesWithoutBaseCall_isRejected() {
        XCTAssertNil(CompoundCallsign.parse("I/P"))
        XCTAssertNil(CompoundCallsign.parse("ABC/DEF"))
    }

    func test_parse_protocolTokensAndFields_areRejected() {
        for token in ["CQ", "QRZ", "DE", "RR73", "73", "IN76", "+05", "R-08"] {
            XCTAssertNil(CompoundCallsign.parse(token), "\(token) is not a callsign")
        }
    }

    // MARK: - isValidCallsign, the reported symptom

    func test_isValidCallsign_reportedCases_areAccepted() {
        XCTAssertTrue(isValidCallsign("VE6XAD"))
        XCTAssertTrue(isValidCallsign("I/VE6XAD"))
        XCTAssertTrue(isValidCallsign("VE6XAD/I"))
    }

    /// The cases the previous rules already accepted must keep working.
    func test_isValidCallsign_existingBehaviourIsPreserved() {
        XCTAssertTrue(isValidCallsign("EA4IQL"))
        XCTAssertTrue(isValidCallsign("K1ABC/1"))
        XCTAssertTrue(isValidCallsign("W1AW/QRP"))
        XCTAssertTrue(isValidCallsign("VE3ABC/VE3"))
        XCTAssertTrue(isValidCallsign("ea4iql"))
        XCTAssertFalse(isValidCallsign(""))
        XCTAssertFalse(isValidCallsign("ABCDEF"))
        XCTAssertFalse(isValidCallsign("EA4IQL/P/MM"))
        XCTAssertFalse(isValidCallsign("IN76"))
    }

    // MARK: - Country resolution

    /// A prefix names the entity being operated from, so the country follows the
    /// prefix and not the home call.
    func test_country_prefixModifier_resolvesToVisitedEntity() {
        XCTAssertEqual(CountryResolver.countryAndCoordinates(for: "I/VE6XAD").country, "Italy")
        XCTAssertEqual(CountryResolver.countryAndCoordinates(for: "VE6XAD").country, "Canada")
    }

    /// An operating suffix says nothing about location: the country stays home.
    func test_country_operatingSuffix_keepsHomeEntity() {
        XCTAssertEqual(CountryResolver.countryAndCoordinates(for: "VE6XAD/P").country, "Canada")
        XCTAssertEqual(CountryResolver.countryAndCoordinates(for: "VE6XAD/MM").country, "Canada")
        XCTAssertEqual(CountryResolver.countryAndCoordinates(for: "K1ABC/1").country, "United States")
    }

    /// A suffix that is itself a DXCC prefix does move the entity.
    func test_country_prefixLikeSuffix_resolvesToVisitedEntity() {
        XCTAssertEqual(CountryResolver.countryAndCoordinates(for: "W1AW/VE3").country, "Canada")
    }

    /// A hashed callsign printed by the decoder resolves like the bare call.
    func test_country_bracketedCallsign_resolves() {
        XCTAssertEqual(CountryResolver.countryAndCoordinates(for: "<I/VE6XAD>").country, "Italy")
    }

    // MARK: - Protocol packing

    func test_isStandardPackable_onlyPlainCallsAndProtocolSuffixes() {
        XCTAssertTrue(CompoundCallsign.parse("VE6XAD")!.isStandardPackable)
        XCTAssertTrue(CompoundCallsign.parse("VE6XAD/P")!.isStandardPackable)
        XCTAssertTrue(CompoundCallsign.parse("VE6XAD/R")!.isStandardPackable)
        XCTAssertFalse(CompoundCallsign.parse("I/VE6XAD")!.isStandardPackable)
        XCTAssertFalse(CompoundCallsign.parse("VE6XAD/MM")!.isStandardPackable)
    }

    // MARK: - Decoded token handling

    func test_fromDecodedToken_stripsHashBrackets() {
        XCTAssertEqual(CompoundCallsign.fromDecodedToken("<I/VE6XAD>")?.text, "I/VE6XAD")
        XCTAssertEqual(CompoundCallsign.fromDecodedToken("K1ABC")?.text, "K1ABC")
    }

    /// "<...>" is a call the decoder has not heard spelled out yet.
    func test_fromDecodedToken_unresolvedHash_isNotACallsign() {
        XCTAssertNil(CompoundCallsign.fromDecodedToken("<...>"))
    }
}

// MARK: - Decoding messages that carry a compound callsign

final class CompoundCallsignMessageTests: XCTestCase {

    func test_cqFromCompoundCallsign_isParsed() {
        let message = FT8Message(text: "CQ I/VE6XAD", mode: .ft8)
        XCTAssertEqual(message.msgType, .cq)
        XCTAssertEqual(message.callsign, "I/VE6XAD")
        XCTAssertEqual(message.senderCountry.country, "Italy")
    }

    func test_cqFromSuffixedCallsign_isParsed() {
        let message = FT8Message(text: "CQ VE6XAD/P IN76", mode: .ft8)
        XCTAssertEqual(message.msgType, .cq)
        XCTAssertEqual(message.callsign, "VE6XAD/P")
        XCTAssertEqual(message.locator, "IN76")
    }

    /// Once a compound call has been spelled out, the other station refers to it
    /// by hash and the decoder prints it in angle brackets.
    func test_hashedCallsign_isParsedWithoutBrackets() {
        let message = FT8Message(text: "<K1ABC> I/VE6XAD RR73", mode: .ft8)
        XCTAssertEqual(message.msgType, .rr73)
        XCTAssertEqual(message.callsign, "I/VE6XAD")
        XCTAssertEqual(message.dxCallsign, "K1ABC")
    }

    func test_hashedSenderCallsign_isParsedWithoutBrackets() {
        let message = FT8Message(text: "K1ABC <I/VE6XAD> -12", mode: .ft8)
        XCTAssertEqual(message.msgType, .standardSignalReport)
        XCTAssertEqual(message.callsign, "I/VE6XAD")
        XCTAssertEqual(message.dxCallsign, "K1ABC")
    }

    /// A call the decoder has not yet heard in plain text cannot be worked.
    func test_unresolvedHash_leavesCallsignUnset() {
        let message = FT8Message(text: "<...> K1ABC RR73", mode: .ft8)
        XCTAssertEqual(message.callsign, "K1ABC")
        XCTAssertNil(message.dxCallsign)
    }

    /// A compound callsign answers a CQ without a grid, because the message type
    /// that spells the call out has no room for one. That still has to open a QSO.
    func test_bareCallToCall_opensAQSO() {
        let message = FT8Message(text: "K1ABC I/VE6XAD", mode: .ft8)
        XCTAssertEqual(message.msgType, .gridExchange)
        XCTAssertEqual(message.callsign, "I/VE6XAD")
        XCTAssertEqual(message.dxCallsign, "K1ABC")
        XCTAssertNil(message.locator)
    }

    /// A bare call whose recipient is an unresolved hash cannot be acted on.
    func test_bareCallToUnknownHash_staysUnknown() {
        let message = FT8Message(text: "<...> K1ABC", mode: .ft8)
        XCTAssertEqual(message.msgType, .unknown)
    }

    /// A message addressed to my compound callsign is recognised as mine.
    func test_messageToMyCompoundCallsign_isForMe() {
        let participants = FT8Message.parseParticipants(
            parts: "<I/VE6XAD> K1ABC -12".uppercased().split(separator: " ")
        )
        XCTAssertTrue(
            FT8Message.isForMe(participants: participants, myCallsign: "I/VE6XAD", isTX: false)
        )
    }
}

// MARK: - Composing messages from a compound callsign

final class CompoundCallsignComposerTests: XCTestCase {

    private var sut: FT8MessageComposer!

    override func setUp() {
        super.setUp()
        sut = FT8MessageComposer()
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
        sut = nil
        super.tearDown()
    }

    private func messages(from callsign: String) -> [String] {
        sut.generateMessages(
            callsign: callsign,
            locator: "IN76",
            dxCallsign: "K1ABC",
            dxLocator: "FN20",
            snrToSend: -10
        )
    }

    /// A compound callsign travels in a message type that has no grid field, so
    /// the CQ must not offer one: the message list shows what actually goes out.
    func test_cqFromCompoundCallsign_omitsGrid() {
        XCTAssertEqual(messages(from: "I/VE6XAD")[0], "CQ I/VE6XAD")
    }

    /// A plain call, and one carrying the protocol's own /P suffix, still send it.
    func test_cqFromStandardCallsign_keepsGrid() {
        XCTAssertEqual(messages(from: "VE6XAD")[0], "CQ VE6XAD IN76")
        XCTAssertEqual(messages(from: "VE6XAD/P")[0], "CQ VE6XAD/P IN76")
    }

    /// The CQ modifier has no field in that message type either.
    func test_cqModifierIsDroppedForCompoundCallsign() {
        UserDefaults.standard.set("DX", forKey: "cqModifier")
        XCTAssertEqual(messages(from: "I/VE6XAD")[0], "CQ I/VE6XAD")
        XCTAssertEqual(messages(from: "VE6XAD")[0], "CQ DX VE6XAD IN76")
    }

    /// Answering a CQ has to spell the call out too, so it carries no grid.
    func test_replyToCQFromCompoundCallsign_omitsGrid() {
        XCTAssertEqual(messages(from: "I/VE6XAD")[1], "K1ABC I/VE6XAD")
        XCTAssertEqual(messages(from: "VE6XAD")[1], "K1ABC VE6XAD IN76")
        XCTAssertEqual(messages(from: "VE6XAD/P")[1], "K1ABC VE6XAD/P IN76")
    }

    /// The rest of the exchange carries the compound call unchanged: by then the
    /// other station has heard it spelled out and resolves it from its hash.
    func test_exchangeMessagesCarryTheCompoundCallsign() {
        let msgs = messages(from: "I/VE6XAD")
        XCTAssertEqual(msgs[2], "K1ABC I/VE6XAD -10")
        XCTAssertEqual(msgs[3], "K1ABC I/VE6XAD R-10")
        XCTAssertEqual(msgs[6], "K1ABC I/VE6XAD RR73")
    }
}

// MARK: - Transmitting a compound callsign

final class CompoundCallsignEncodingTests: XCTestCase {

    /// The encoder has to produce audio for a compound call rather than failing.
    func test_generateFT8_withCompoundCallsign_producesAudio() {
        let engine = ft8_Engine()
        for message in ["CQ I/VE6XAD", "CQ VE6XAD/MM", "K1ABC I/VE6XAD RR73",
                        "K1ABC I/VE6XAD IN76", "CQ VE6XAD IN76"] {
            let data = engine.generateFT8(message, frequency: 1400, isFT4: false, toFile: nil)
            XCTAssertNotNil(data, "No audio generated for '\(message)'")
            XCTAssertGreaterThan(data?.count ?? 0, 0, "Empty audio for '\(message)'")
        }
    }

    /// The point of the whole exercise: a CQ from a compound callsign has to come
    /// off the air with the call spelled out. Encoded as a standard message it
    /// would decode as "CQ <...>", which no one can answer.
    func test_cqFromCompoundCallsign_survivesTheAir() throws {
        try assertRoundTrip("CQ I/VE6XAD")
        try assertRoundTrip("CQ VE6XAD/MM")
    }

    /// Plain callsigns must keep travelling exactly as before, grid included.
    func test_cqFromStandardCallsign_survivesTheAir() throws {
        try assertRoundTrip("CQ EA4IQL IN80")
        try assertRoundTrip("CQ EA4IQL/P IN80")
    }

    /// Encodes a message to a WAV file, decodes that file back, and checks the
    /// text that comes out is the text that went in.
    private func assertRoundTrip(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let engine = ft8_Engine()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let audio = engine.generateFT8(message, frequency: 1400, isFT4: false, toFile: url)
        XCTAssertNotNil(audio, "No audio generated for '\(message)'", file: file, line: line)

        let decoded = engine.decode(url, isFT4: false)
        let texts = decoded.compactMap { $0["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }

        XCTAssertTrue(
            texts.contains(message),
            "'\(message)' decoded as \(texts)",
            file: file,
            line: line
        )
    }
}
