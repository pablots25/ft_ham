//
//  DecodedMessageContextMenu.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/11/26.
//

import SwiftUI
import UIKit

// MARK: - Menu items

/// What the secondary-click menu of a decoded row offers.
struct DecodedMessageMenuItems: Equatable {
    let canReply: Bool
    /// The callsign to copy, when the message names one.
    let callsign: String?
    let messageText: String

    init(message: FT8Message, allowReply: Bool) {
        canReply = allowReply && message.allowsReply
        let call = message.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        callsign = (call?.isEmpty ?? true) ? nil : call
        messageText = message.text
    }
}

// MARK: - Modifier

/// Adds a secondary-click menu (Reply, Copy Callsign, Copy Message) to a
/// decoded row. Only on a Mac: on iPhone and iPad a long press on a row that
/// updates every cycle would get in the way of scrolling and swiping.
struct DecodedMessageContextMenu: ViewModifier {
    let items: DecodedMessageMenuItems
    let isEnabled: Bool
    let onReply: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                if items.canReply {
                    Button(action: onReply) {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                }
                if let callsign = items.callsign {
                    Button {
                        UIPasteboard.general.string = callsign
                    } label: {
                        Label("Copy Callsign", systemImage: "doc.on.doc")
                    }
                }
                Button {
                    UIPasteboard.general.string = items.messageText
                } label: {
                    Label("Copy Message", systemImage: "text.quote")
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Secondary-click menu for a decoded row, shown on a Mac only.
    func decodedMessageContextMenu(
        _ message: FT8Message,
        allowReply: Bool,
        onReply: @escaping () -> Void
    ) -> some View {
        modifier(DecodedMessageContextMenu(
            items: DecodedMessageMenuItems(message: message, allowReply: allowReply),
            isEnabled: RunningPlatform.isMac,
            onReply: onReply
        ))
    }
}
