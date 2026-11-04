//
//  QSOStripDensityTests.swift
//  ft_hamTests
//
//  The QSO strip is regular unless a caller asks for compact, so only
//  the narrow condensed landscape grid switches to icon-only buttons.
//

import XCTest
@testable import ft8_ham

@MainActor
final class QSOStripDensityTests: XCTestCase {

    func testDefaultDensityIsRegular() {
        XCTAssertEqual(QSOStatusView().density, .regular)
    }

    func testCompactDensityIsKept() {
        XCTAssertEqual(QSOStatusView(density: .compact).density, .compact)
    }
}
