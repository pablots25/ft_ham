//
//  WaterfallTapRouter.swift
//  ft_ham
//

import Foundation

/// What a plain tap on the waterfall does. The TX frequency only moves while
/// the frequency button is on, never from a plain tap.
enum WaterfallTapOutcome: Equatable {
    /// Reply to the decoded message the tap points at.
    case reply
    /// Do nothing.
    case ignore
}

/// Decides whether a tap on the waterfall replies to a decoded label. Pure
/// logic so the view stays thin and the rules are testable.
enum WaterfallTapRouter {
    /// - Parameters:
    ///   - tapToReply: The "Tap a signal to reply" setting.
    ///   - gesture: The reply gesture chosen in Display settings.
    ///   - isSecondTap: Whether this tap closely follows the previous one.
    ///   - hasReplyableLabel: Whether a replyable decoded label is near the tap.
    static func outcome(tapToReply: Bool, gesture: ReplyTapGesture,
                        isSecondTap: Bool, hasReplyableLabel: Bool) -> WaterfallTapOutcome {
        guard tapToReply, hasReplyableLabel else { return .ignore }
        switch gesture {
        case .single: return .reply
        case .double: return isSecondTap ? .reply : .ignore
        }
    }
}
