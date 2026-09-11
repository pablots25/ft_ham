//
//  RXFilterMode.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import SwiftUI

/// The decode-list filter cycled by the funnel button in every layout.
///
/// Raw values are persisted through the existing `@AppStorage` Int keys
/// (`rxFilterMode*`), so the order of the first three cases must not change.
enum RXFilterMode: Int, CaseIterable {
    case all = 0
    case mine
    case mineAndCQ
    case needed

    init(storage rawValue: Int) {
        self = RXFilterMode(rawValue: rawValue) ?? .all
    }

    var next: RXFilterMode {
        RXFilterMode(rawValue: rawValue + 1) ?? .all
    }

    var systemImage: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .mine, .mineAndCQ: return "line.3.horizontal.decrease.circle.fill"
        case .needed: return "star.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .secondary
        case .mine: return .primary
        case .mineAndCQ: return .accentColor
        case .needed: return .teal
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .all: return "Show all messages"
        case .mine: return "Show mine"
        case .mineAndCQ: return "Show mine and CQ"
        case .needed: return "Show needed only"
        }
    }

    /// Own TX rows always survive so the operator keeps seeing what went out.
    func apply(_ messages: [FT8Message], isNeeded: (FT8Message) -> Bool) -> [FT8Message] {
        switch self {
        case .all:
            return messages
        case .mine:
            return messages.filter { $0.forMe || $0.isTX }
        case .mineAndCQ:
            return messages.filter { $0.forMe || $0.isTX || $0.msgType == .cq }
        case .needed:
            return messages.filter { $0.isTX || $0.forMe || isNeeded($0) }
        }
    }
}

/// The funnel button shared by all decode-list layouts.
struct RXFilterButton: View {
    @Binding var filterMode: Int

    private var mode: RXFilterMode { RXFilterMode(storage: filterMode) }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                filterMode = mode.next.rawValue
            }
        } label: {
            Image(systemName: mode.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(mode.tint)
                .accessibilityLabel(mode.accessibilityLabel)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rxFilterButton")
    }
}
