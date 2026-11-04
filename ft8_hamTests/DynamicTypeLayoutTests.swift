//
//  DynamicTypeLayoutTests.swift
//  ft8_hamTests
//
//  Regression tests for large text sizes: the operating chrome and the decode
//  columns stop growing where they would push content off an iPhone screen,
//  and the Received and Transmitted lists stack when they no longer fit.
//

import SwiftUI
import XCTest
@testable import ft8_ham

final class DynamicTypeLayoutTests: XCTestCase {

    // MARK: - Operating chrome

    func test_operatingChrome_growsPastTheDefaultSize() {
        XCTAssertGreaterThan(OperatingChromeTypeSize.limit, .xxxLarge)
    }

    func test_operatingChrome_stopsBeforeTheLargestAccessibilitySizes() {
        XCTAssertTrue(OperatingChromeTypeSize.range.contains(.accessibility1))
        XCTAssertFalse(OperatingChromeTypeSize.range.contains(.accessibility2))
        XCTAssertFalse(OperatingChromeTypeSize.range.contains(.accessibility5))
    }

    func test_operatingChrome_keepsSmallSizes() {
        XCTAssertTrue(OperatingChromeTypeSize.range.contains(.xSmall))
    }

    // MARK: - Decode columns

    func test_decodeColumns_growIntoAccessibilitySizes() {
        XCTAssertTrue(DecodeRowMetrics.typeSizeRange.contains(.accessibility1))
    }

    func test_decodeColumns_stopWhereTheyWouldOutgrowAPhone() {
        XCTAssertFalse(DecodeRowMetrics.typeSizeRange.contains(.accessibility2))
    }

    func test_decodeColumns_fitTheNarrowestPhoneAtDefaultSize() {
        // iPhone SE width minus the list's 16 pt padding on each side.
        XCTAssertLessThanOrEqual(DecodeRowMetrics.baseRowWidth, 375 - 32)
    }

    func test_baseRowWidth_sumsColumnsSpacingAndInsets() {
        let expected = DecodeRowMetrics.baseTimeWidth
            + DecodeRowMetrics.baseSNRWidth
            + DecodeRowMetrics.baseFrequencyWidth
            + DecodeRowMetrics.baseTimeOffsetWidth
            + 3 * DecodeRowMetrics.baseColumnSpacing
            + 2 * DecodeRowMetrics.horizontalPadding
        XCTAssertEqual(DecodeRowMetrics.baseRowWidth, expected)
    }

    // MARK: - Received and Transmitted layout

    func test_sectionLayout_sideBySideWhenBothListsFit() {
        let layout = TransmissionSectionLayout(availableWidth: 400, rowWidth: 166, spacing: 25)
        XCTAssertEqual(layout, .sideBySide)
    }

    func test_sectionLayout_singleWhenAListWouldBeTooNarrow() {
        let layout = TransmissionSectionLayout(availableWidth: 361, rowWidth: 196, spacing: 25)
        XCTAssertEqual(layout, .single)
    }

    func test_sectionLayout_exactFitStaysSideBySide() {
        let layout = TransmissionSectionLayout(availableWidth: 2 * 166 + 25, rowWidth: 166, spacing: 25)
        XCTAssertEqual(layout, .sideBySide)
    }

    func test_sectionLayout_spacingCountsAgainstTheColumns() {
        let layout = TransmissionSectionLayout(availableWidth: 2 * 166 + 24, rowWidth: 166, spacing: 25)
        XCTAssertEqual(layout, .single)
    }

    func test_sectionLayout_zeroWidthIsSingle() {
        let layout = TransmissionSectionLayout(availableWidth: 0, rowWidth: 166, spacing: 25)
        XCTAssertEqual(layout, .single)
    }
}

// MARK: - Decode message wrapping

final class DecodeRowMessageLineLimitTests: XCTestCase {

    func test_standardSizes_keepOneLine() {
        for size in [DynamicTypeSize.xSmall, .large, .xxxLarge] {
            XCTAssertEqual(DecodeRowLayout.messageLineLimit(for: size), 1, "\(size)")
        }
    }

    func test_accessibilitySizes_wrap() {
        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            XCTAssertGreaterThan(DecodeRowLayout.messageLineLimit(for: size), 1, "\(size)")
        }
    }
}

// MARK: - Needed badges

final class NeededBadgeStyleTests: XCTestCase {

    func test_fullStyle_showsTheWholeTag() {
        XCTAssertEqual(NeededBadgeView.label(for: "DXCC", style: .full), "DXCC")
        XCTAssertEqual(NeededBadgeView.label(for: "GRID", style: .full), "GRID")
    }

    func test_initialStyle_showsOneLetter() {
        XCTAssertEqual(NeededBadgeView.label(for: "DXCC", style: .initial), "D")
        XCTAssertEqual(NeededBadgeView.label(for: "GRID", style: .initial), "G")
    }

    func test_dotStyle_hasNoText() {
        XCTAssertNil(NeededBadgeView.label(for: "DXCC", style: .dot))
    }

    func test_initials_tellTheBadgesApart() {
        XCTAssertNotEqual(
            NeededBadgeView.label(for: "DXCC", style: .initial),
            NeededBadgeView.label(for: "GRID", style: .initial)
        )
    }
}
