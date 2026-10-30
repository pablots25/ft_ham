//
//  WaterfallTapRouterTests.swift
//  ft_hamTests
//
//  Tests for WaterfallTapRouter: which taps on the waterfall reply to a
//  decoded label. A plain tap never moves the TX frequency: that needs
//  the frequency button.
//

import XCTest
@testable import ft8_ham

final class WaterfallTapRouterTests: XCTestCase {

    private func outcome(
        tapToReply: Bool = true,
        gesture: ReplyTapGesture,
        isSecondTap: Bool = false,
        hasReplyableLabel: Bool
    ) -> WaterfallTapOutcome {
        WaterfallTapRouter.outcome(
            tapToReply: tapToReply,
            gesture: gesture,
            isSecondTap: isSecondTap,
            hasReplyableLabel: hasReplyableLabel
        )
    }

    // MARK: - Setting off

    func testSettingOffNeverReplies() {
        for gesture in ReplyTapGesture.allCases {
            for isSecondTap in [false, true] {
                for hasLabel in [false, true] {
                    XCTAssertEqual(
                        outcome(tapToReply: false, gesture: gesture,
                                isSecondTap: isSecondTap, hasReplyableLabel: hasLabel),
                        .ignore,
                        "gesture=\(gesture) second=\(isSecondTap) label=\(hasLabel)"
                    )
                }
            }
        }
    }

    // MARK: - Single tap

    func testSingleTapOnLabelReplies() {
        XCTAssertEqual(outcome(gesture: .single, hasReplyableLabel: true), .reply)
    }

    func testSingleTapOffLabelDoesNothing() {
        XCTAssertEqual(outcome(gesture: .single, hasReplyableLabel: false), .ignore)
    }

    // MARK: - Double tap

    func testDoubleTapFirstTapDoesNothing() {
        XCTAssertEqual(outcome(gesture: .double, isSecondTap: false, hasReplyableLabel: true), .ignore)
    }

    func testDoubleTapSecondTapOnLabelReplies() {
        XCTAssertEqual(outcome(gesture: .double, isSecondTap: true, hasReplyableLabel: true), .reply)
    }

    func testDoubleTapSecondTapOffLabelDoesNothing() {
        XCTAssertEqual(outcome(gesture: .double, isSecondTap: true, hasReplyableLabel: false), .ignore)
    }
}
