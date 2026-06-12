//
//  FlagUtilityTests.swift
//  ft8_hamTests
//

import XCTest
@testable import ft8_ham

final class FlagUtilityTests: XCTestCase {

    // MARK: - Direct countryToFlag lookups

    func testGermanyDirectLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "Germany"), "🇩🇪")
    }

    func testSouthSudanDirectLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "South Sudan"), "🇸🇸")
    }

    func testEswatiniDirectLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "Eswatini"), "🇸🇿")
    }

    func testTimorLesteLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "Timor - Leste"), "🇹🇱")
    }

    func testFalklandIslandsLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "Falkland Islands"), "🇫🇰")
    }

    func testSouthGeorgiaIslandLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "South Georgia Island"), "🇬🇸")
    }

    func testBouvetLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "Bouvet"), "🇧🇻")
    }

    func testCeutaMelillaLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "Ceuta & Melilla"), "🇪🇦")
    }

    func testHeardIslandLookup() {
        XCTAssertEqual(FlagUtility.flag(for: "Heard Island"), "🇭🇲")
    }

    // MARK: - CTY alias resolutions (cty.plist name → canonical name → flag)

    func testFedRepOfGermanyAlias() {
        // CTY name for DL callsigns
        XCTAssertEqual(FlagUtility.flag(for: "Fed. Rep. of Germany"), "🇩🇪")
    }

    func testDemRepOfCongoAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Dem. Rep. of the Congo"), "🇨🇩")
    }

    func testKingdomOfEswatiniAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Kingdom of Eswatini"), "🇸🇿")
    }

    func testRepublicOfSouthSudanAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Republic of South Sudan"), "🇸🇸")
    }

    func testRodriguezIslandAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Rodriguez Island"), "🇲🇺")
    }

    func testAgalegaAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Agalega & St. Brandon"), "🇲🇺")
    }

    func testAnnobonIslandAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Annobon Island"), "🇬🇶")
    }

    func testConwayReefAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Conway Reef"), "🇫🇯")
    }

    func testRotumaIslandAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Rotuma Island"), "🇫🇯")
    }

    func testSanFelixAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "San Felix & San Ambrosio"), "🇨🇱")
    }

    func testPeter1IslandAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Peter 1 Island"), "🇳🇴")
    }

    // MARK: - Pre-existing alias regressions

    func testRepublicOfKoreaAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Republic of Korea"), "🇰🇷")
    }

    func testDPROfKoreaAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "DPR of Korea"), "🇰🇵")
    }

    func testCoteDIvoireAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Cote d'Ivoire"), "🇨🇮")
    }

    func testCzechAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Czech"), "🇨🇿")
    }

    func testRussianFederationAlias() {
        XCTAssertEqual(FlagUtility.flag(for: "Russian Federation"), "🇷🇺")
    }

    // MARK: - Edge cases

    func testNilCountry() {
        XCTAssertNil(FlagUtility.flag(for: nil))
    }

    func testUnknownCountry() {
        XCTAssertNil(FlagUtility.flag(for: "ITU HQ"))
        XCTAssertNil(FlagUtility.flag(for: "United Nations HQ"))
        XCTAssertNil(FlagUtility.flag(for: "Vienna Intl Ctr"))
    }
}
