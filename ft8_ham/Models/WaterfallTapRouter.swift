//
//  WaterfallTapRouter.swift
//  ft_ham
//

import Foundation

/// What a plain tap on the waterfall does.
enum WaterfallTapOutcome: Equatable {
    /// Reply to the decoded message whose label sits under the finger.
    case reply
    /// Move the TX frequency to where the tap landed.
    case setFrequency
}

/// Decides between replying and setting the TX frequency for a tap on the
/// waterfall. Pure logic so the view stays thin and the rules are testable.
enum WaterfallTapRouter {
    /// - Parameters:
    ///   - tapToReply: The "Tap a signal to reply" setting.
    ///   - gesture: The reply gesture chosen in Display settings.
    ///   - isSecondTap: Whether this tap closely follows the previous one.
    ///   - hasReplyableLabel: Whether a replyable decoded label is under the tap.
    static func outcome(tapToReply: Bool, gesture: ReplyTapGesture,
                        isSecondTap: Bool, hasReplyableLabel: Bool) -> WaterfallTapOutcome {
        guard tapToReply, hasReplyableLabel else { return .setFrequency }
        switch gesture {
        case .single: return .reply
        case .double: return isSecondTap ? .reply : .setFrequency
        }
    }
}
