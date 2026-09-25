//
//  CommonMsgUtils.swift
//  ft_ham
//
//  Created by Pablo Turrion on 4/1/26.
//

import SwiftUI

/// Soft row tint that adapts its opacity per color scheme. The flat 0.2 tints
/// read as too faint over the dark-mode background, so dark mode uses a stronger
/// alpha for adequate contrast.
func rowTint(_ color: Color) -> Color {
    Color(UIColor { trait in
        let alpha: CGFloat = trait.userInterfaceStyle == .dark ? 0.32 : 0.20
        return UIColor(color).withAlphaComponent(alpha)
    })
}

/// A highlight that overrides the message-type tint of a decoded row.
enum RowHighlight: Equatable {
    case none
    /// Another station calls our callsign.
    case callingMe
    /// The sender is on the operator's watchlist.
    case watched
}

private let systemBackgroundTint = Color(UIColor.systemBackground)

// Color selector based on FT8 message type with adaptive colors for dark mode.
// `isNewCallsign` highlights an incoming CQ from a station not yet worked.
// `highlight` (calling you, watched station) wins over the message type.
// The colors come from `RowColorStore`, which the operator can customize.
func backgroundColor(
    for msg: FT8Message,
    isNewCallsign: Bool = false,
    highlight: RowHighlight = .none,
    colors: RowColorStore = .shared
) -> Color {
    switch highlight {
    case .callingMe: return colors.tint(.callingMe)
    case .watched: return colors.tint(.watched)
    case .none: break
    }
    return switch msg.msgType {
    case .internalTimestamp:
        systemBackgroundTint
    case .cq:
        if msg.isTX {
            colors.tint(.ownTX)
        } else if isNewCallsign {
            colors.tint(.newCallsign) // new (unworked) callsign
        } else {
            colors.tint(.cq)
        }
    case .gridExchange:
        if msg.forMe {
            colors.tint(.gridToMe)
        } else {
            systemBackgroundTint
        }
    case .standardSignalReport, .rSignalReport:
        if msg.forMe {
            colors.tint(.reportToMe)
        } else {
            systemBackgroundTint
        }
    case .rr73, .rrr, .final73:
        colors.tint(.finals)
    case .unknown:
        msg.isTX ? colors.tint(.ownTX) : colors.tint(.unknown) // own free text is own-TX color
    }
}

/// Bell for a station calling you, star for a watched station, in the
/// operator's chosen highlight color.
struct RowHighlightMarker: View {
    let highlight: RowHighlight

    var body: some View {
        switch highlight {
        case .none:
            EmptyView()
        case .callingMe:
            Image(systemName: "bell.fill")
                .font(.caption2)
                .foregroundStyle(RowColorStore.shared.color(.callingMe))
                .accessibilityLabel(Text("Calling you"))
        case .watched:
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(RowColorStore.shared.color(.watched))
                .accessibilityLabel(Text("Watched station"))
        }
    }
}
