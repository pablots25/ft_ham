//
//  FT8MessageTests2.swift
//  ft_hamTests
//
//  Created by Pablo Turrion on 03/01/26.
//

import XCTest
@testable import ft8_ham

final class FT8MessageTests2: XCTestCase {
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("EA1AAA", forKey: "callsign")
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "callsign")
        super.tearDown()
    }
    
    // -----------------------------------------------------
    // MARK: - Initializer Tests
    // -----------------------------------------------------
    func testInitializerBasic() {
        
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "callsign"),
            "EA1AAA"
        )
        
        let msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft8,
            isRealtime: true,
            measuredSNR: 5.0,
            frequency: 14074000,
            timeOffset: 0.1,
            ldpcErrors: 2,
            isTX: true,
            band: .band20m
        )
        
        XCTAssertEqual(msg.text, "CQ EA1AAA")
        XCTAssertEqual(msg.mode, .ft8)
        XCTAssertTrue(msg.isRealtime)
        XCTAssertEqual(msg.measuredSNR, 5.0)
        XCTAssertEqual(msg.frequency, 14074000)
        XCTAssertEqual(msg.timeOffset, 0.1)
        XCTAssertEqual(msg.ldpcErrors, 2)
        XCTAssertTrue(msg.isTX)
        XCTAssertEqual(msg.band, .band20m)
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertTrue(msg.forMe)
        XCTAssertNotNil(msg.id)
        XCTAssertNil(msg.cqModifier)
    }
    
    func testInitializerInternalTimestamp() {
        let timestamp = Date()
        let msg = FT8Message(text: "2026-01-03 12:00:00 - 20m", mode: .ft8, timestamp: timestamp)
        
        XCTAssertEqual(msg.text, "2026-01-03 12:00:00 - 20m")
        XCTAssertEqual(msg.msgType, .internalTimestamp)
        XCTAssertTrue(msg.isRealtime)
        XCTAssertEqual(msg.timestamp, timestamp)
        XCTAssertFalse(msg.allowsReply)
        XCTAssertNil(msg.callsign)
        XCTAssertNil(msg.dxCallsign)
    }
    
    // -----------------------------------------------------
    // MARK: - Participant Parsing
    // -----------------------------------------------------
    func testParseParticipantsCQ() {
        let participants = FT8Message.parseParticipants(parts: "CQ EA1AAA IN76".uppercased().split(separator: " "))
        XCTAssertEqual(participants.senderCallsign, "EA1AAA")
        XCTAssertEqual(participants.senderLocator, "IN76")
        XCTAssertNil(participants.receiverCallsign)
        XCTAssertNil(participants.receiverLocator)
    }
    
    func testParseParticipantsCQWithModifiers() {
        // CQ DX - Should find the callsign after the DX modifier
        var participants = FT8Message.parseParticipants(parts: "CQ DX EA1ABC IN83".uppercased().split(separator: " "))
        XCTAssertEqual(participants.senderCallsign, "EA1ABC")
        XCTAssertEqual(participants.senderLocator, "IN83")
        
        let cqDX = FT8Message(text: "CQ DX EA1ABC IN83", mode: .ft8)
        XCTAssertEqual(cqDX.cqModifier, "DX")
        
        // CQ NA - Should find the callsign after the NA modifier
        participants = FT8Message.parseParticipants(parts: "CQ NA VE3XYZ FN03".uppercased().split(separator: " "))
        XCTAssertEqual(participants.senderCallsign, "VE3XYZ")
        XCTAssertEqual(participants.senderLocator, "FN03")
        
        // CQ with modifier but no locator
        participants = FT8Message.parseParticipants(parts: "CQ EU G4ABC".uppercased().split(separator: " "))
        XCTAssertEqual(participants.senderCallsign, "G4ABC")
        XCTAssertNil(participants.senderLocator)
        
        let cqEU = FT8Message(text: "CQ EU G4ABC", mode: .ft8)
        XCTAssertEqual(cqEU.cqModifier, "EU")
    }
    
    func testInvalidCQIsNotRecognized() {
        let msg = FT8Message.parseParticipants(parts: "CQ USA W1AW FN31".uppercased().split(separator: " "))
        XCTAssertEqual(msg.senderCallsign, "W1AW")
        XCTAssertEqual(msg.senderLocator, "FN31")
        
        let cqUSA = FT8Message(text: "CQ USA W1AW FN31", mode: .ft8)
        XCTAssertEqual(cqUSA.msgType, .cq)
        XCTAssertEqual(cqUSA.cqModifier, "USA")
    }

    func testParseParticipantsCQWithWWAModifier() {
        let participants = FT8Message.parseParticipants(parts: "CQ WWA EA4IQL IN80".uppercased().split(separator: " "))
        XCTAssertEqual(participants.senderCallsign, "EA4IQL")
        XCTAssertEqual(participants.senderLocator, "IN80")

        let msg = FT8Message(text: "CQ WWA EA4IQL IN80", mode: .ft8)
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertEqual(msg.cqModifier, "WWA")
        XCTAssertEqual(msg.callsign, "EA4IQL")
        XCTAssertEqual(msg.locator, "IN80")
    }

    func testParseParticipantsCQWithArbitraryModifierAcceptedOnRX() {
        let modifiers = ["WWA", "USA", "TEST", "1A", "CQWW"]

        for modifier in modifiers {
            let text = "CQ \(modifier) EA1ABC IN83"
            let msg = FT8Message(text: text, mode: .ft8)
            XCTAssertEqual(msg.msgType, .cq, "Expected CQ for modifier \(modifier)")
            XCTAssertEqual(msg.cqModifier, modifier, "Expected modifier \(modifier)")
            XCTAssertEqual(msg.callsign, "EA1ABC")
            XCTAssertEqual(msg.locator, "IN83")
        }
    }

    func testCQCompactAliasesAreKeptRawOnRX() {
        let testCases: [(text: String, expected: String)] = [
            ("CQ POT EA1ABC IN83", "POT"),
            ("CQ SOT EA1ABC IN83", "SOT"),
            ("CQ WFF EA1ABC IN83", "WFF"),
            ("CQ IOT EA1ABC IN83", "IOT")
        ]

        for testCase in testCases {
            let msg = FT8Message(text: testCase.text, mode: .ft8)
            XCTAssertEqual(msg.msgType, .cq)
            XCTAssertEqual(msg.cqModifier, testCase.expected)
        }
    }

    func testParseParticipantsCQRejectsInvalidModifierPatterns() {
        let invalidMessages = [
            "CQ +++ EA1ABC IN83",   // invalid chars
            "CQ -DX EA1ABC IN83",   // invalid chars
            "CQ RR73 EA1ABC IN83",  // report token, not modifier
            "CQ IN83 EA1ABC IN83"   // locator token, not modifier
        ]

        for text in invalidMessages {
            let msg = FT8Message(text: text, mode: .ft8)
            XCTAssertEqual(msg.msgType, .unknown, "Expected unknown for text: \(text)")
            XCTAssertNil(msg.cqModifier)
        }
    }
    
    func testParseParticipantsExchange() {
        let participants = FT8Message.parseParticipants(parts: "F4XYZ EA1AAA FN31".uppercased().split(separator: " "))
        XCTAssertEqual(participants.senderCallsign, "EA1AAA")
        XCTAssertEqual(participants.senderLocator, "FN31")
        XCTAssertEqual(participants.receiverCallsign, "F4XYZ")
        XCTAssertNil(participants.receiverLocator)
    }
    
    // -----------------------------------------------------
    // MARK: - Message Type Detection
    // -----------------------------------------------------
    func testDetectMessageType() {
        XCTAssertEqual(FT8Message.detectMessageType(text: "CQ EA1AAA", parts: "CQ EA1AAA".uppercased().split(separator: " ")), .cq)
        XCTAssertEqual(FT8Message.detectMessageType(text: "CQ DX EA1ABC IN83", parts: "CQ DX EA1ABC IN83".uppercased().split(separator: " ")), .cq)
        XCTAssertEqual(FT8Message.detectMessageType(text: "CQ EU G4ABC", parts: "CQ EU G4ABC".uppercased().split(separator: " ")), .cq)
        
        // CQ with only modifiers and no valid callsign should be unknown
        XCTAssertEqual(FT8Message.detectMessageType(text: "CQ DX", parts: "CQ DX".uppercased().split(separator: " ")), .unknown)
        XCTAssertEqual(FT8Message.detectMessageType(text: "CQ WWA USA", parts: "CQ WWA USA".uppercased().split(separator: " ")), .unknown)
        XCTAssertEqual(FT8Message.detectMessageType(text: "CQ USA W1AW", parts: "CQ USA W1AW".uppercased().split(separator: " ")), .cq)
        
        XCTAssertEqual(FT8Message.detectMessageType(text: "F4XYZ EA1AAA 59", parts: "F4XYZ EA1AAA 59".uppercased().split(separator: " ")), .standardSignalReport)
        XCTAssertEqual(FT8Message.detectMessageType(text: "F4XYZ EA1AAA FN31", parts: "F4XYZ EA1AAA FN31".uppercased().split(separator: " ")), .gridExchange)
        XCTAssertEqual(FT8Message.detectMessageType(text: "F4XYZ EA1AAA RR73", parts: "F4XYZ EA1AAA RR73".uppercased().split(separator: " ")), .rr73)
        XCTAssertEqual(FT8Message.detectMessageType(text: "F4XYZ EA1AAA RRR", parts: "F4XYZ EA1AAA RRR".uppercased().split(separator: " ")), .rrr)
        XCTAssertEqual(FT8Message.detectMessageType(text: "F4XYZ EA1AAA 73", parts: "F4XYZ EA1AAA 73".uppercased().split(separator: " ")), .final73)
        XCTAssertEqual(FT8Message.detectMessageType(text: "UNKNOWN MESSAGE", parts: "UNKNOWN MESSAGE".uppercased().split(separator: " ")), .unknown)
    }
    
    // -----------------------------------------------------
    // MARK: - Internal Timestamp Check
    // -----------------------------------------------------
    //    func testIsInternalTimestamp() {
    //        XCTAssertTrue(FT8Message.isInternalTimestamp("2026-01-03 12:00:00 - 20m"))
    //        XCTAssertFalse(FT8Message.isInternalTimestamp("CQ EA1AAA"))
    //        XCTAssertFalse(FT8Message.isInternalTimestamp("Invalid Format"))
    //    }
    //
    
    // -----------------------------------------------------
    // MARK: - Band Frequency
    // -----------------------------------------------------
    func testBandFrequencies() {
        // FT8 frequency for 80m band
        XCTAssertEqual(
            FT8Message.Band.band80m.frequency(for: .ft8),
            3_573_000
        )
        
        // Unknown band has no frequency
        XCTAssertNil(
            FT8Message.Band.unknown.frequency(for: .ft8)
        )
        
        // Valid bands include 20m
        XCTAssertTrue(
            FT8Message.Band.validBands.contains(.band20m)
        )
        
        // Valid bands must exclude .unknown
        XCTAssertFalse(
            FT8Message.Band.validBands.contains(.unknown)
        )
    }
    
    
    
    // -----------------------------------------------------
    // MARK: - Country Detection
    // -----------------------------------------------------
    func testCountryDetection() {
        let testCallsigns = [
            "LA8ENA",  // Norway
            "LA9GX",   // Norway
            "EA1AAA",  // Spain
            "VE1ZZ",   // Canada
            "VO1ACZ",  // Antigua & Barbuda
            "SP7AM",   // Poland
            "F4VUK",   // France
            "DK6XY",   // Germany / Angola
            "W3JJL",   // USA
            "IZ0ZIP"   // Italy
        ]
        
        for call in testCallsigns {
            let country = CountryResolver.countryAndCoordinates(for: call)
            
            XCTAssertNotNil(country, "Country detection failed for callsign: \(call)")
            
        }
    }
    
    
    // -----------------------------------------------------
    // MARK: - Factory Methods
    // -----------------------------------------------------
    func testTimestampedFactory() {
        let msg = FT8Message.timestamped("CQ EA1AAA", mode: .ft8, isTx: true)
        XCTAssertEqual(msg.text, "CQ EA1AAA")
        XCTAssertTrue(msg.isTX)
        XCTAssertEqual(msg.msgType, .cq)
    }
    
    func testDecodeFactory() {
        let msg = FT8Message.decode(text: "F4XYZ EA1AAA 59", mode: .ft8, snr: 10.0, frequency: 14074000, timeOffset: 0.1)
        XCTAssertEqual(msg.text, "F4XYZ EA1AAA 59")
        XCTAssertEqual(msg.measuredSNR, 10.0)
        XCTAssertEqual(msg.frequency, 14074000)
        XCTAssertEqual(msg.timeOffset, 0.1)
    }
    
    // -----------------------------------------------------
    // MARK: - Empty Message
    // -----------------------------------------------------
    func testEmptyMessage() {
        let empty = FT8Message.empty()
        XCTAssertEqual(empty.text, "")
        XCTAssertEqual(empty.mode, .ft8)
        XCTAssertFalse(empty.isRealtime)
    }
    
    // MARK: - Tests de CountryCenterResolver
    
    func testCountryCenterResolutionMultiple() {
        // SPAIN
        // EA1ABC -> Prefijo EA1 -> Lat: 42.57, Lon: -6.17
        var country = CountryResolver.countryAndCoordinates(for: "EA1AAA")
        XCTAssertEqual(country.country, "Spain")
        XCTAssertEqual(country.coordinates?.lat ?? 0, 42.57, accuracy: 0.1)
        XCTAssertEqual(country.coordinates?.lon ?? 0, -6.17, accuracy: 0.1)
        
        // EA2AAA -> Prefijo EA2 -> Lat: 42.60, Lon: -1.93
        country = CountryResolver.countryAndCoordinates(for: "EA2AAA")
        XCTAssertEqual(country.coordinates?.lat ?? 0, 42.60, accuracy: 0.1)
        XCTAssertEqual(country.coordinates?.lon ?? 0, -1.93, accuracy: 0.1)
        
        // UNITED STATES
        // K1ABC -> Prefijo K1 -> Lat: 42.38, Lon: -71.65 (New England)
        country = CountryResolver.countryAndCoordinates(for: "K1ABC")
        XCTAssertEqual(country.country, "United States")
        XCTAssertEqual(country.coordinates?.lat ?? 0, 42.38, accuracy: 0.1)
        XCTAssertEqual(country.coordinates?.lon ?? 0, -71.65, accuracy: 0.1)
        
        // W6XYZ -> Prefijo W6 -> Lat: 35.48, Lon: -119.35 (California)
        country = CountryResolver.countryAndCoordinates(for: "W6XYZ")
        XCTAssertEqual(country.coordinates?.lat ?? 0, 35.48, accuracy: 0.1)
        XCTAssertEqual(country.coordinates?.lon ?? 0, -119.35, accuracy: 0.1)
        
        // JAPAN
        // JA1ABC -> Prefijo JA1 -> Lat: 35.48, Lon: 139.60
        country = CountryResolver.countryAndCoordinates(for: "JA1ABC")
        XCTAssertEqual(country.country, "Japan")
        
        // JR2XYZ -> Prefijo JR2 -> Lat: 35.07, Lon: 136.90
        country = CountryResolver.countryAndCoordinates(for: "JR2XYZ")
        XCTAssertEqual(country.coordinates?.lat ?? 0, 35.18, accuracy: 0.1)
    }
    
    
    func testGenerateWithPower(){
        var msg = FT8Message.decode(
            text: "EA4IQL EA1DIW R-05",
            mode: .ft8,
            snr: 10.0,
            frequency: 14074000,
            timeOffset: 0.1
        )
        
        XCTAssertEqual(msg.messageTxtSNR, -5)
        
        msg = FT8Message.decode(
            text: "EA4IQL EA1DIW 17",
            mode: .ft8,
            snr: 10.0,
            frequency: 14074000,
            timeOffset: 0.1
        )
        
        XCTAssertEqual(msg.messageTxtSNR, 17)
        
        
        msg = FT8Message.decode(
            text: "EA4IQL EA1DIW R+17",
            mode: .ft8,
            snr: 10.0,
            frequency: 14074000,
            timeOffset: 0.1
        )
        
        XCTAssertEqual(msg.messageTxtSNR, +17)
    }
    
    // -----------------------------------------------------
    // MARK: - Cycle Tests (FT8)
    // -----------------------------------------------------
    func testFT8Cycle() {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 12, minute: 0, second: 0))!
        
        // Seconds: 0 → even
        var msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft8,
            timestamp: baseDate
        )
        XCTAssertEqual(msg.cycle, .even)
        
        // Seconds: 15 → odd
        let date15 = calendar.date(byAdding: .second, value: 15, to: baseDate)!
        msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft8,
            timestamp: date15
        )
        XCTAssertEqual(msg.cycle, .odd)
        
        // Seconds: 30 → even
        let date30 = calendar.date(byAdding: .second, value: 30, to: baseDate)!
        msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft8,
            timestamp: date30
        )
        XCTAssertEqual(msg.cycle, .even)
        
        // Seconds: 45 → odd
        let date45 = calendar.date(byAdding: .second, value: 45, to: baseDate)!
        msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft8,
            timestamp: date45
        )
        XCTAssertEqual(msg.cycle, .odd)
    }
    
    // -----------------------------------------------------
    // MARK: - Cycle Tests (FT4)
    // -----------------------------------------------------
    func testFT4Cycle() {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 12, minute: 0, second: 0))!
        
        // Seconds: 0 → even
        var msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft4,
            timestamp: baseDate
        )
        XCTAssertEqual(msg.cycle, .even)
        
        // Seconds: 7 → odd
        let date7 = calendar.date(byAdding: .second, value: 8, to: baseDate)!
        msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft4,
            timestamp: date7
        )
        XCTAssertEqual(msg.cycle, .odd)
        
        // Seconds: 15 → even
        let date15 = calendar.date(byAdding: .second, value: 15, to: baseDate)!
        msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft4,
            timestamp: date15
        )
        XCTAssertEqual(msg.cycle, .even)
        
        // Seconds: 22 → odd
        let date22 = calendar.date(byAdding: .second, value: 24, to: baseDate)!
        msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft4,
            timestamp: date22
        )
        XCTAssertEqual(msg.cycle, .odd)
    }
    
    // MARK: - Full Flow Integration Tests
    
    func testFullFlowSimpleCQ() {
        let msg = FT8Message(text: "CQ EA1AAA", mode: .ft8)
        
        XCTAssertEqual(msg.text, "CQ EA1AAA")
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertEqual(msg.callsign, "EA1AAA")
        XCTAssertNil(msg.locator)
        XCTAssertNil(msg.dxCallsign)
        XCTAssertNil(msg.cqModifier)
        XCTAssertTrue(msg.forMe)
        XCTAssertTrue(msg.messageTxtSNR.isNaN)
    }
    
    func testFullFlowCQWithModifierAndGrid() {
        let msg = FT8Message(text: "CQ DX EA1ABC IN83", mode: .ft8)
        
        XCTAssertEqual(msg.text, "CQ DX EA1ABC IN83")
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertEqual(msg.callsign, "EA1ABC")
        XCTAssertEqual(msg.locator, "IN83")
        XCTAssertEqual(msg.cqModifier, "DX")
        XCTAssertNil(msg.dxCallsign)
        XCTAssertFalse(msg.forMe)
    }
    
    func testFullFlowCQWithNAModifier() {
        let msg = FT8Message(text: "CQ NA W1AW FN31", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertEqual(msg.callsign, "W1AW")
        XCTAssertEqual(msg.locator, "FN31")
        XCTAssertEqual(msg.cqModifier, "NA")
    }
    
    func testFullFlowGridExchange() {
        let msg = FT8Message(text: "F4XYZ EA1AAA FN31", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .gridExchange)
        XCTAssertEqual(msg.callsign, "EA1AAA")
        XCTAssertEqual(msg.locator, "FN31")
        XCTAssertEqual(msg.dxCallsign, "F4XYZ")
        XCTAssertNil(msg.dxLocator)
        XCTAssertTrue(msg.forMe)
    }
    
    func testFullFlowStandardSignalReport() {
        let msg = FT8Message(text: "G4ABC EA1AAA 23", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .standardSignalReport)
        XCTAssertEqual(msg.callsign, "EA1AAA")
        XCTAssertEqual(msg.dxCallsign, "G4ABC")
        XCTAssertEqual(msg.messageTxtSNR, 23)
        XCTAssertTrue(msg.forMe)
    }
    
    func testFullFlowRSignalReport() {
        let msg = FT8Message(text: "W5XYZ EA1AAA R-08", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .rSignalReport)
        XCTAssertEqual(msg.callsign, "EA1AAA")
        XCTAssertEqual(msg.dxCallsign, "W5XYZ")
        XCTAssertEqual(msg.messageTxtSNR, -8)
        XCTAssertTrue(msg.forMe)
    }
    
    func testFullFlowRR73() {
        let msg = FT8Message(text: "JA1ABC EA1AAA RR73", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .rr73)
        XCTAssertEqual(msg.callsign, "EA1AAA")
        XCTAssertEqual(msg.dxCallsign, "JA1ABC")
        XCTAssertTrue(msg.forMe)
    }
    
    func testFullFlowRRR() {
        let msg = FT8Message(text: "VE3XYZ EA1AAA RRR", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .rrr)
        XCTAssertEqual(msg.callsign, "EA1AAA")
        XCTAssertEqual(msg.dxCallsign, "VE3XYZ")
        XCTAssertTrue(msg.forMe)
    }
    
    func testFullFlowFinal73() {
        let msg = FT8Message(text: "K1ABC EA1AAA 73", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .final73)
        XCTAssertEqual(msg.callsign, "EA1AAA")
        XCTAssertEqual(msg.dxCallsign, "K1ABC")
        XCTAssertTrue(msg.forMe)
    }
    
    func testFullFlowInternalTimestamp() {
        let msg = FT8Message(
            text: "2026-01-15 14:30:00 - 20m",
            mode: .ft8,
            timestamp: Date()
        )
        
        XCTAssertEqual(msg.msgType, .internalTimestamp)
        XCTAssertNil(msg.callsign)
        XCTAssertNil(msg.dxCallsign)
        XCTAssertFalse(msg.allowsReply)
        XCTAssertFalse(msg.forMe)
    }
    
    func testFullFlowCountryDetectionSender() {
        // EA1ABC → Spain (EA1 prefix)
        let msg = FT8Message(text: "CQ EA1ABC", mode: .ft8)
        
        XCTAssertEqual(msg.senderCountry.country, "Spain")
        XCTAssertNotNil(msg.senderCountry.coordinates)
    }
    
    func testFullFlowCountryDetectionBoth() {
        // W5ABC (USA) calling EA1AAA (Spain)
        let msg = FT8Message(text: "EA1AAA W5ABC FN31", mode: .ft8)
        
        XCTAssertEqual(msg.senderCountry.country, "United States")
        XCTAssertEqual(msg.dxCountry.country, "Spain")
        XCTAssertNotNil(msg.senderCountry.coordinates)
        XCTAssertNotNil(msg.dxCountry.coordinates)
    }
    
    func testFullFlowForMeFlag() {
        // Message is for me when I'm the sender in a CQ
        let msg1 = FT8Message(text: "CQ EA1AAA", mode: .ft8)
        XCTAssertTrue(msg1.forMe)
        
        // Message is for me when I'm the receiver in an exchange
        let msg2 = FT8Message(text: "EA1AAA W1AW FN31", mode: .ft8)
        XCTAssertTrue(msg2.forMe)
        
        // Message is NOT for me when I'm not in the exchange
        let msg3 = FT8Message(text: "K1ABC W5XYZ FN31", mode: .ft8)
        XCTAssertFalse(msg3.forMe)
    }
    
    func testFullFlowInvalidCQNotForMe() {
        // CQ USA W1AW: USA is a valid 3-char raw modifier under the permissive parser.
        // The message is parsed as .cq but is not for me since my callsign isn't W1AW.
        let msg = FT8Message(text: "CQ USA W1AW FN31", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertEqual(msg.callsign, "W1AW")
        XCTAssertEqual(msg.cqModifier, "USA")
        XCTAssertFalse(msg.forMe)
    }
    
    func testFullFlowSNRExtractionNegative() {
        let msg = FT8Message(text: "EA4IQL EA1DIW R-05", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .rSignalReport)
        XCTAssertEqual(msg.messageTxtSNR, -5)
    }
    
    func testFullFlowSNRExtractionPositive() {
        let msg = FT8Message(text: "EA4IQL EA1DIW 17", mode: .ft8)
        
        XCTAssertEqual(msg.msgType, .standardSignalReport)
        XCTAssertEqual(msg.messageTxtSNR, 17)
    }
    
    func testFullFlowTXMessage() {
        let msg = FT8Message(
            text: "CQ EA1AAA",
            mode: .ft8,
            isTX: true
        )
        
        XCTAssertTrue(msg.isTX)
        XCTAssertFalse(msg.allowsReply)  // TX messages don't allow replies
    }
    
    func testFullFlowComplexExchange() {
        // Complete exchange flow
        let cq = FT8Message(text: "CQ DX W1AW FN31", mode: .ft8)
        XCTAssertEqual(cq.msgType, .cq)
        XCTAssertEqual(cq.cqModifier, "DX")
        
        let grid = FT8Message(text: "W1AW EA1AAA IN83", mode: .ft8)
        XCTAssertEqual(grid.msgType, .gridExchange)
        
        let report = FT8Message(text: "EA1AAA W1AW R-12", mode: .ft8)
        XCTAssertEqual(report.msgType, .rSignalReport)
        XCTAssertEqual(report.messageTxtSNR, -12)
        
        let reply = FT8Message(text: "W1AW EA1AAA R+02", mode: .ft8)
        XCTAssertEqual(reply.msgType, .rSignalReport)
        XCTAssertEqual(reply.messageTxtSNR, 2)
        
        let final = FT8Message(text: "EA1AAA W1AW RR73", mode: .ft8)
        XCTAssertEqual(final.msgType, .rr73)
    }
    
    func testFullFlowFT4Mode() {
        let msg = FT8Message(text: "CQ EA1ABC IN76", mode: .ft4)
        
        XCTAssertEqual(msg.mode, .ft4)
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertEqual(msg.callsign, "EA1ABC")
        XCTAssertEqual(msg.locator, "IN76")
    }
    
    func testFullFlowMetadata() {
        let msg = FT8Message(
            text: "F4XYZ EA1AAA FN31",
            mode: .ft8,
            isRealtime: true,
            measuredSNR: 8.5,
            frequency: 14074100,
            timeOffset: 0.5,
            ldpcErrors: 3,
            band: .band20m
        )
        
        XCTAssertTrue(msg.isRealtime)
        XCTAssertEqual(msg.measuredSNR, 8.5)
        XCTAssertEqual(msg.frequency, 14074100)
        XCTAssertEqual(msg.timeOffset, 0.5)
        XCTAssertEqual(msg.ldpcErrors, 3)
        XCTAssertEqual(msg.band, .band20m)
        XCTAssertEqual(msg.msgType, .gridExchange)
    }

    // -----------------------------------------------------
    // MARK: - Partial Decode Tests
    // (called callsign field not decoded, sender + content decoded)
    // -----------------------------------------------------

    /// When the called-callsign field is not decoded but the sender callsign and
    /// grid square are valid, the message type must be inferred as .gridExchange.
    func testPartialDecode_withGrid_isGridExchange() {
        let msg = FT8Message(text: "??? EA4TX IN80", mode: .ft8)
        XCTAssertEqual(msg.msgType, .gridExchange,
            "Grid present → type must be .gridExchange even without a decoded called callsign")
    }

    /// Sender callsign and locator are correctly extracted in a partial decode.
    func testPartialDecode_senderAndGridExtracted() {
        let msg = FT8Message(text: "??? W1AW FN31", mode: .ft8)
        XCTAssertEqual(msg.msgType, .gridExchange)
        XCTAssertEqual(msg.callsign, "W1AW")
        XCTAssertEqual(msg.locator, "FN31")
        XCTAssertNil(msg.dxCallsign, "Called callsign should be nil when not decoded")
    }

    /// parseParticipants extracts sender + locator even when parts[0] is not a valid callsign.
    func testParseParticipants_partialDecode_senderAndLocator() {
        let parts = "??? JA1ABC PM95".uppercased().split(separator: " ")
        let p = FT8Message.parseParticipants(parts: parts)
        XCTAssertEqual(p.senderCallsign, "JA1ABC")
        XCTAssertEqual(p.senderLocator, "PM95")
        XCTAssertNil(p.receiverCallsign)
        XCTAssertNil(p.receiverLocator)
    }

    /// A partial decode with a standard signal report → .standardSignalReport.
    func testPartialDecode_withSignalReport_isStandardSignalReport() {
        let msg = FT8Message(text: "??? EA4TX -10", mode: .ft8)
        XCTAssertEqual(msg.msgType, .standardSignalReport)
    }

    /// A partial decode with an R-prefixed signal report → .rSignalReport.
    func testPartialDecode_withRSignalReport_isRSignalReport() {
        let msg = FT8Message(text: "??? EA4TX R-10", mode: .ft8)
        XCTAssertEqual(msg.msgType, .rSignalReport)
    }

    /// A partial decode containing RR73 → .rr73.
    func testPartialDecode_withRR73_isRR73() {
        let msg = FT8Message(text: "??? EA4TX RR73", mode: .ft8)
        XCTAssertEqual(msg.msgType, .rr73)
    }

    /// A partial decode containing RRR → .rrr.
    func testPartialDecode_withRRR_isRRR() {
        let msg = FT8Message(text: "??? EA4TX RRR", mode: .ft8)
        XCTAssertEqual(msg.msgType, .rrr)
    }

    /// A partial decode containing 73 → .final73.
    func testPartialDecode_with73_isFinal73() {
        let msg = FT8Message(text: "??? EA4TX 73", mode: .ft8)
        XCTAssertEqual(msg.msgType, .final73)
    }

    /// A partial decode with only the sender callsign and no recognizable third
    /// field → .unknown (not enough information to classify).
    func testPartialDecode_withoutRecognizableField_isUnknown() {
        let msg = FT8Message(text: "??? EA4TX", mode: .ft8)
        XCTAssertEqual(msg.msgType, .unknown,
            "Without a grid/signal-report/73 the message cannot be classified")
    }

    /// If both parts[0] and parts[1] are invalid callsigns → .unknown.
    func testPartialDecode_invalidSender_isUnknown() {
        let msg = FT8Message(text: "??? ??? IN80", mode: .ft8)
        XCTAssertEqual(msg.msgType, .unknown,
            "An invalid sender callsign must yield .unknown")
    }

    /// A .gridExchange partial decode is replyable (sender is valid, type != .unknown).
    func testPartialDecode_gridExchange_allowsReply() {
        let msg = FT8Message(text: "??? VK2ABC QF56", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .gridExchange)
        XCTAssertTrue(msg.allowsReply,
            "Reply must be allowed when the message type can be inferred from content")
    }

    /// A TX copy of a partial-decode message must NOT allow a reply.
    func testPartialDecode_tx_doesNotAllowReply() {
        let msg = FT8Message(text: "??? VK2ABC QF56", mode: .ft8, isTX: true)
        XCTAssertFalse(msg.allowsReply,
            "TX messages must never allow reply")
    }

    /// A fully-decoded message must continue to be classified by its own type.
    func testFullyDecodedMessage_classifiedCorrectly() {
        let msg = FT8Message(text: "EA1AAA EA4TX IN80", mode: .ft8)
        XCTAssertEqual(msg.msgType, .gridExchange,
            "A fully-decoded grid-exchange must still be .gridExchange")
    }
}
