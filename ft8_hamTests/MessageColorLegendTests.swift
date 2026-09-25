//
//  MessageColorLegendTests.swift
//  ft8_hamTests
//
//  Regression tests ensuring that backgroundColor(for:) returns the correct
//  Color for every message type / state combination shown in the Color Legend.
//
//  Row tints are now scheme-adaptive dynamic colors (see rowTint), so equality
//  is checked on the resolved RGBA components rather than on Color identity.
//

import XCTest
import SwiftUI
@testable import ft8_ham

final class MessageColorLegendTests: XCTestCase {

    // Our local station callsign used throughout these tests.
    private let myCallsign = "EA1AAA"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(myCallsign, forKey: "callsign")
        // Row colors are user-configurable; these tests check the defaults.
        RowColorStore.shared.resetToDefaults()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "callsign")
        super.tearDown()
    }

    // MARK: - Helpers

    private func rgba(_ color: Color, style: UIUserInterfaceStyle) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let ui = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    /// Asserts a row tint matches the expected base hue at the light-mode alpha,
    /// and that dark mode uses a stronger alpha for contrast.
    private func assertTint(
        _ actual: Color,
        matches base: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let light = rgba(actual, style: .light)
        let expected = rgba(base.opacity(0.20), style: .light)
        XCTAssertEqual(light.0, expected.0, accuracy: 0.02, "red", file: file, line: line)
        XCTAssertEqual(light.1, expected.1, accuracy: 0.02, "green", file: file, line: line)
        XCTAssertEqual(light.2, expected.2, accuracy: 0.02, "blue", file: file, line: line)
        XCTAssertEqual(light.3, expected.3, accuracy: 0.02, "alpha", file: file, line: line)

        // Dark mode should be more opaque than light mode for adequate contrast.
        let dark = rgba(actual, style: .dark)
        XCTAssertGreaterThan(dark.3, light.3, "dark-mode tint must be stronger", file: file, line: line)
    }

    // MARK: - Legend entry 1: Yellow — own CQ TX

    func test_backgroundColor_cqTX_isYellow() {
        let msg = FT8Message(text: "CQ \(myCallsign) IN76", mode: .ft8, isTX: true)
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertTrue(msg.isTX)
        assertTint(backgroundColor(for: msg), matches: .yellow)
    }

    // MARK: - Legend entry 2: Purple — received CQ from another (worked) station

    func test_backgroundColor_cqReceived_isPurple() {
        let msg = FT8Message(text: "CQ EA2BBB IN76", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertFalse(msg.isTX)
        // isNewCallsign defaults to false → worked/known station keeps purple.
        assertTint(backgroundColor(for: msg), matches: .purple)
    }

    // MARK: - New-callsign highlight: green for an unworked CQ

    func test_backgroundColor_cqReceived_newCallsign_isGreen() {
        let msg = FT8Message(text: "CQ EA2BBB IN76", mode: .ft8, isTX: false)
        assertTint(backgroundColor(for: msg, isNewCallsign: true), matches: .green)
    }

    // MARK: - Legend entry 3: Blue — grid exchange directed at me

    func test_backgroundColor_gridExchangeForMe_isBlue() {
        let msg = FT8Message(text: "\(myCallsign) EA2BBB IN76", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .gridExchange)
        XCTAssertTrue(msg.forMe)
        assertTint(backgroundColor(for: msg), matches: .blue)
    }

    func test_backgroundColor_gridExchangeNotForMe_isSystemBackground() {
        let msg = FT8Message(text: "EA3CCC EA2BBB IN76", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .gridExchange)
        XCTAssertFalse(msg.forMe)
        XCTAssertEqual(backgroundColor(for: msg), Color(UIColor.systemBackground))
    }

    // MARK: - Legend entry 4: Orange — signal report directed at me

    func test_backgroundColor_signalReportForMe_isOrange() {
        let msg = FT8Message(text: "\(myCallsign) EA2BBB -07", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .standardSignalReport)
        XCTAssertTrue(msg.forMe)
        assertTint(backgroundColor(for: msg), matches: .orange)
    }

    func test_backgroundColor_rSignalReportForMe_isOrange() {
        let msg = FT8Message(text: "\(myCallsign) EA2BBB R-07", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .rSignalReport)
        XCTAssertTrue(msg.forMe)
        assertTint(backgroundColor(for: msg), matches: .orange)
    }

    func test_backgroundColor_signalReportNotForMe_isSystemBackground() {
        let msg = FT8Message(text: "EA3CCC EA2BBB -07", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .standardSignalReport)
        XCTAssertFalse(msg.forMe)
        XCTAssertEqual(backgroundColor(for: msg), Color(UIColor.systemBackground))
    }

    // MARK: - Legend entry 5: Purple — final exchange messages (RR73 / RRR / 73)

    func test_backgroundColor_rr73_isPurple() {
        let msg = FT8Message(text: "\(myCallsign) EA2BBB RR73", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .rr73)
        assertTint(backgroundColor(for: msg), matches: .purple)
    }

    func test_backgroundColor_rrr_isPurple() {
        let msg = FT8Message(text: "\(myCallsign) EA2BBB RRR", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .rrr)
        assertTint(backgroundColor(for: msg), matches: .purple)
    }

    func test_backgroundColor_final73_isPurple() {
        let msg = FT8Message(text: "\(myCallsign) EA2BBB 73", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .final73)
        assertTint(backgroundColor(for: msg), matches: .purple)
    }

    // MARK: - Legend entry 6: Gray — unknown message type

    func test_backgroundColor_unknown_isGray() {
        let msg = FT8Message(text: "INVALID GARBLED MESSAGE", mode: .ft8, isTX: false)
        XCTAssertEqual(msg.msgType, .unknown)
        assertTint(backgroundColor(for: msg), matches: .gray)
    }

    // MARK: - Legend entry 7: System background — internal timestamp

    func test_backgroundColor_internalTimestamp_isSystemBackground() {
        let timestamp = Date()
        let msg = FT8Message(text: "2026-04-05 12:00:00 - 20m", mode: .ft8, timestamp: timestamp)
        XCTAssertEqual(msg.msgType, .internalTimestamp)
        XCTAssertEqual(backgroundColor(for: msg), Color(UIColor.systemBackground))
    }

    // MARK: - Calling-you highlight: red wins over every other tint

    func test_backgroundColor_callingMe_isRed() {
        let grid = FT8Message(text: "\(myCallsign) EA2BBB IN76", mode: .ft8, isTX: false)
        assertTint(backgroundColor(for: grid, highlight: .callingMe), matches: .red)

        let final = FT8Message(text: "\(myCallsign) EA2BBB RR73", mode: .ft8, isTX: false)
        assertTint(backgroundColor(for: final, isNewCallsign: true, highlight: .callingMe), matches: .red)
    }

    func test_backgroundColor_watched_isCyan() {
        let cq = FT8Message(text: "CQ 3Y0J JD15", mode: .ft8, isTX: false)
        assertTint(backgroundColor(for: cq, isNewCallsign: true, highlight: .watched), matches: .cyan)
    }

    func test_backgroundColor_usesCustomColor() {
        let defaults = UserDefaults(suiteName: "MessageColorLegendTests.custom")!
        defaults.removePersistentDomain(forName: "MessageColorLegendTests.custom")
        let store = RowColorStore(defaults: defaults)
        store.setColor(.green, for: .finals)

        let final = FT8Message(text: "\(myCallsign) EA2BBB RR73", mode: .ft8, isTX: false)
        let expected = RowColorStore.color(fromHex: RowColorStore.hex(from: .green))!
        assertTint(backgroundColor(for: final, colors: store), matches: expected)
        defaults.removePersistentDomain(forName: "MessageColorLegendTests.custom")
    }
}
