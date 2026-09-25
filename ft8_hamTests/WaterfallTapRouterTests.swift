//
//  WaterfallTapRouterTests.swift
//  ft_hamTests
//
//  Tests for WaterfallTapRouter: which taps on the waterfall reply to a
//  decoded label and which only set the TX frequency.
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

    func testSettingOffAlwaysSetsFrequency() {
        for gesture in ReplyTapGesture.allCases {
            for isSecondTap in [false, true] {
                for hasLabel in [false, true] {
                    XCTAssertEqual(
                        outcome(tapToReply: false, gesture: gesture,
                                isSecondTap: isSecondTap, hasReplyableLabel: hasLabel),
                        .setFrequency,
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

    func testSingleTapOffLabelSetsFrequency() {
        XCTAssertEqual(outcome(gesture: .single, hasReplyableLabel: false), .setFrequency)
    }

    // MARK: - Double tap

    func testDoubleTapFirstTapSetsFrequency() {
        XCTAssertEqual(outcome(gesture: .double, isSecondTap: false, hasReplyableLabel: true), .setFrequency)
    }

    func testDoubleTapSecondTapOnLabelReplies() {
        XCTAssertEqual(outcome(gesture: .double, isSecondTap: true, hasReplyableLabel: true), .reply)
    }

    func testDoubleTapSecondTapOffLabelSetsFrequency() {
        XCTAssertEqual(outcome(gesture: .double, isSecondTap: true, hasReplyableLabel: false), .setFrequency)
    }
}
