//
//  PremiumFeatureTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 13/04/26.
//

import XCTest
@testable import ft8_ham

final class PremiumFeatureTests: XCTestCase {

    func testStatisticsDisplayName() {
        XCTAssertEqual(PremiumFeature.statistics.displayName, "Statistics")
    }

    func testStatisticsIcon() {
        XCTAssertEqual(PremiumFeature.statistics.icon, "chart.bar.xaxis")
    }

    func testStatisticsAnalyticsSource() {
        XCTAssertEqual(PremiumFeature.statistics.analyticsSource, "statistics")
    }

    func testStatisticsRawValue() {
        XCTAssertEqual(PremiumFeature.statistics.rawValue, "statistics")
    }

    func testAllCasesIncludesStatistics() {
        XCTAssertTrue(PremiumFeature.allCases.contains(.statistics))
    }

    func testAllCasesCount() {
        XCTAssertEqual(PremiumFeature.allCases.count, 7)
    }
}
