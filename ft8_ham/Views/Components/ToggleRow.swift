//
//  ToggleRow.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

// MARK: - HelpTip Enum (Fallback for iOS 16)

enum HelpTip: Identifiable {
    case autoRXAtStart
    case autoCQReply
    case autoCQNewBandMode
    case decodeSelfTX
    case holdTXFrequency
    case autoSequencing
    case autoQSOLogging
    case analytics
    case locatorGPS
    case pskReporter
    case cqIncludeGrid
    case snrExplained
    case dtExplained
    case audioFrequencyHz
    case audioGain
    case txOutputGain
    case highlightNewCallsigns
    case neededBadges
    case pileupRandom
    case pileupPreferNew
    case ntpSync
    case iCloudSync
    case presence
    case waterfallPalette
    case waterfallFlatten
    case waterfallLevel
    case highlightMyCallsign
    case callAlertSound
    case callAlertHaptic
    case callAlertNotification
    case watchAlert

    var id: Self { self }

    var text: String {
        switch self {
        case .autoRXAtStart:
            return String(localized: "Auto RX help")
        case .autoCQReply:
            return String(localized: "Auto CQ Reply help")
        case .autoCQNewBandMode:
            return String(localized: "Auto CQ New Band Mode help")
        case .decodeSelfTX:
            return String(localized: "Decode Self TX help")
        case .holdTXFrequency:
            return String(localized: "Hold TX Frequency help")
        case .autoSequencing:
            return String(localized: "Auto Sequencing help")
        case .autoQSOLogging:
            return String(localized: "Auto QSO Logging help")
        case .analytics:
            return String(localized: "Analytics help")
        case .locatorGPS:
            return String(localized: "Auto Locator help")
        case .pskReporter:
            return String(localized: "PSK Reporter help")
        case .cqIncludeGrid:
            return String(localized: "Include Grid in CQ help")
        case .snrExplained:
            return String(localized: "SNR dB help")
        case .dtExplained:
            return String(localized: "DT offset help")
        case .audioFrequencyHz:
            return String(localized: "Audio Frequency help")
        case .audioGain:
            return String(localized: "Audio Gain help")
        case .txOutputGain:
            return String(localized: "TX Output Gain help")
        case .highlightNewCallsigns:
            return String(localized: "Highlight new callsigns help")
        case .neededBadges:
            return String(localized: "Needed badges help")
        case .pileupRandom:
            return String(localized: "Pile-up random caller help")
        case .pileupPreferNew:
            return String(localized: "Pile-up prefer new help")
        case .ntpSync:
            return String(localized: "NTP sync help")
        case .iCloudSync:
            return String(localized: "iCloud sync help")
        case .presence:
            return String(localized: "Presence help")
        case .waterfallPalette:
            return String(
                localized: "Waterfall palette help",
                defaultValue: "Colour scale of the waterfall. Blue keeps the noise dark and shows signals in cyan and white; Classic is the scale earlier versions used."
            )
        case .waterfallFlatten:
            return String(
                localized: "Waterfall flatten help",
                defaultValue: "Evens out the audio passband so the noise looks the same across the whole band. Useful with a radio's line output, where the edges of the filter are much quieter than the middle."
            )
        case .waterfallLevel:
            return String(
                localized: "Waterfall level help",
                defaultValue: "Auto level follows the noise floor so the display looks the same with a microphone or a sound card. Zero sets where the darkest colour starts below the noise; Gain sets how many dB the colour scale spans."
            )
        case .highlightMyCallsign:
            return String(
                localized: "Highlight calls to me help",
                defaultValue: "Tints and bolds every decoded message where another station calls your callsign, with a bell next to it."
            )
        case .callAlertSound:
            return String(
                localized: "Call alert sound help",
                defaultValue: "Plays a short sound when a station calls you or a watched station is heard. It stays silent while you transmit and when the audio goes to a USB or line interface, so it never reaches the radio."
            )
        case .callAlertHaptic:
            return String(
                localized: "Call alert haptic help",
                defaultValue: "Vibrates when a station calls you or a watched station is heard."
            )
        case .callAlertNotification:
            return String(
                localized: "Call alert notification help",
                defaultValue: "Shows a banner with the message when a station calls you or a watched station is heard. Useful when the app is open on another screen, such as the map or the logbook."
            )
        case .watchAlert:
            return String(
                localized: "Watch alert help",
                defaultValue: "Uses the sound, vibration and notification settings below when a watched station is heard. Each station alerts at most once every 10 minutes, and not while you are working it."
            )
        }
    }

    var accessibilityHint: String {
        text
    }
}

// MARK: - Toggle Row Component

struct ToggleRow: View, Equatable {
    let labelKey: LocalizedStringKey
    let helpTip: HelpTip
    @Binding var isOn: Bool
    @Binding var activeHelp: HelpTip?

    
    static func == (lhs: ToggleRow, rhs: ToggleRow) -> Bool {
        lhs.labelKey == rhs.labelKey &&
        lhs.helpTip == rhs.helpTip &&
        lhs.isOn == rhs.isOn &&
        lhs.activeHelp == rhs.activeHelp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .accessibilityLabel(Text(labelKey))
                    .accessibilityHint(Text(helpTip.accessibilityHint))

                Text(labelKey)
                    .font(.body)
                    .lineLimit(2)

                Spacer()

                HelpIconButton(helpHint: helpTip.accessibilityHint) {
                        activeHelp = (activeHelp == helpTip) ? nil : helpTip
                }
            }

            if activeHelp == helpTip {
                HelpBubble(text: helpTip.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }
        }
    }
}

struct HelpIconButton: View {
    let helpHint: String
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.1)) {
                action()
            }
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(Text("Help"))
        .accessibilityHint(Text(helpHint))
    }
}

// MARK: - Help Bubble

struct HelpBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(8)
    }
}
