//
//  WaterfallSafeAreaTests.swift
//  ft8_hamTests
//
//  Regression tests for the tab bar icons disappearing over the waterfall:
//  the Metal waterfall must stop above the tab bar in every orientation.
//

import SwiftUI
import XCTest
@testable import ft8_ham

final class WaterfallSafeAreaTests: XCTestCase {

    func test_portrait_waterfallDoesNotExtendUnderTabBar() {
        XCTAssertFalse(FullScreenWaterfallView.waterfallEdges(isLandscape: false).contains(.bottom))
    }

    func test_landscape_waterfallDoesNotExtendUnderTabBar() {
        XCTAssertFalse(FullScreenWaterfallView.waterfallEdges(isLandscape: true).contains(.bottom))
    }

    func test_portrait_waterfallStillSpansFullWidth() {
        let edges = FullScreenWaterfallView.waterfallEdges(isLandscape: false)
        XCTAssertTrue(edges.contains(.leading))
        XCTAssertTrue(edges.contains(.trailing))
    }

    func test_portrait_waterfallStaysBelowHeader() {
        XCTAssertFalse(FullScreenWaterfallView.waterfallEdges(isLandscape: false).contains(.top))
    }

    func test_landscape_waterfallStillFillsTopAndSides() {
        let edges = FullScreenWaterfallView.waterfallEdges(isLandscape: true)
        XCTAssertTrue(edges.contains(.top))
        XCTAssertTrue(edges.contains(.leading))
        XCTAssertTrue(edges.contains(.trailing))
    }
}
