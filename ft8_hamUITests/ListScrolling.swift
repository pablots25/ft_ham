//
//  ListScrolling.swift
//  ft8_hamUITests
//
//  Created by Pablo Turrion on 16/10/26.
//

import XCTest

extension XCUIApplication {

    /// Scrolls the first list on screen until `element` exists and is
    /// hittable, returning whether it got there.
    ///
    /// SwiftUI lists only create rows near the visible area, so a row further
    /// down does not exist until it is scrolled to: waiting for it first
    /// fails. A full `swipeUp()` flings the list by about a screen and can
    /// carry a row from the bottom edge past the top, so this drags in short
    /// steps without momentum and checks after each one.
    @MainActor
    @discardableResult
    func scrollToElement(_ element: XCUIElement, maxSteps: Int = 15) -> Bool {
        if element.waitForExistence(timeout: 3), element.isHittable { return true }

        let list: XCUIElement = {
            for candidate in [collectionViews.firstMatch, tables.firstMatch, scrollViews.firstMatch]
            where candidate.exists {
                return candidate
            }
            return windows.firstMatch
        }()

        for _ in 0 ..< maxSteps {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: end)
            if element.exists && element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }
}
