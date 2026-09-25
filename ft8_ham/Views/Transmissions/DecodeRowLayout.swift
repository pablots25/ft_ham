//
//  DecodeRowLayout.swift
//  ft_ham
//
//  Created by Pablo Turrion on 25/09/26.
//

import SwiftUI

// MARK: - Metrics

/// Column widths and spacing shared by `MessageListHeaderView` and every
/// decode row, so the header labels sit exactly over their columns.
///
/// The widths scale with Dynamic Type relative to `.caption2`, the font of the
/// metadata columns. Declare it as a stored `var` in a view: SwiftUI resolves
/// the nested `@ScaledMetric`s against that view's environment.
struct DecodeRowMetrics: DynamicProperty {
    /// "HH:mm:ss"
    @ScaledMetric(relativeTo: .caption2) var timeWidth: CGFloat = 48
    /// "-24"
    @ScaledMetric(relativeTo: .caption2) var snrWidth: CGFloat = 22
    /// "2950"
    @ScaledMetric(relativeTo: .caption2) var frequencyWidth: CGFloat = 30
    /// "-0.20s"
    @ScaledMetric(relativeTo: .caption2) var timeOffsetWidth: CGFloat = 38
    @ScaledMetric(relativeTo: .caption2) var columnSpacing: CGFloat = 6

    /// Gap between the pieces of the message column (TX tag, text, badges, mode).
    static let messageSpacing: CGFloat = 4
    /// Leading and trailing inset of a row and of the header. It is wider than
    /// the active-QSO bar so the bar never covers content.
    static let horizontalPadding: CGFloat = 5
    static let activeQSOBarWidth: CGFloat = 4
}

// MARK: - Row logic

/// Pure decisions behind a decode row, kept out of the views so they are testable.
enum DecodeRowLayout {

    /// Normalizes the locked DX callsign once per list body pass.
    /// An empty callsign means no QSO is in progress.
    static func activeCallsign(from lockedDXCallsign: String) -> String? {
        let trimmed = lockedDXCallsign.trimmingCharacters(in: .whitespaces).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A row belongs to the active QSO when the locked station sent it or it
    /// is addressed to that station. `activeCallsign` must already be uppercased.
    static func isActiveQSO(_ msg: FT8Message, activeCallsign: String?) -> Bool {
        guard let activeCallsign, msg.msgType != .internalTimestamp else { return false }
        return msg.callsign?.uppercased() == activeCallsign
            || msg.dxCallsign?.uppercased() == activeCallsign
    }

    /// The "(FT4)" / "(FT8)" suffix is only worth its width when the row was
    /// decoded in a mode other than the current one (mixed-mode history).
    static func showsModeSuffix(for msg: FT8Message, isFT4: Bool) -> Bool {
        msg.mode != (isFT4 ? .ft4 : .ft8)
    }

    static func snrText(_ msg: FT8Message) -> String {
        msg.measuredSNR.isNaN ? "0" : String(format: "%.0f", msg.measuredSNR)
    }

    static func frequencyText(_ msg: FT8Message) -> String {
        msg.frequency.isNaN ? "0" : String(format: "%.0f", msg.frequency)
    }

    static func timeOffsetText(_ msg: FT8Message) -> String {
        msg.timeOffset.isNaN ? "0.00s" : String(format: "%.2fs", msg.timeOffset)
    }
}

// MARK: - Metadata columns

/// Time, SNR, audio frequency and time offset in fixed-width columns.
/// Missing values keep their slot but are drawn clear so columns stay aligned.
struct DecodeRowColumns: View {
    let msg: FT8Message
    private var metrics = DecodeRowMetrics()

    init(msg: FT8Message) {
        self.msg = msg
    }

    var body: some View {
        HStack(spacing: metrics.columnSpacing) {
            Text(DateFormatter.utcFormatterClock.string(from: msg.timestamp))
                .foregroundStyle(.secondary)
                .frame(width: metrics.timeWidth, alignment: .leading)

            Text(DecodeRowLayout.snrText(msg))
                .foregroundStyle(msg.measuredSNR.isNaN ? Color.clear : .secondary)
                .frame(width: metrics.snrWidth, alignment: .trailing)

            Text(DecodeRowLayout.frequencyText(msg))
                .foregroundStyle(msg.frequency.isNaN ? Color.clear : .secondary)
                .frame(width: metrics.frequencyWidth, alignment: .trailing)

            Text(DecodeRowLayout.timeOffsetText(msg))
                .foregroundStyle(
                    msg.timeOffset.isNaN
                    ? Color.clear
                    : (msg.timeOffset > 0.2 ? Color.red : .secondary)
                )
                .frame(width: metrics.timeOffsetWidth, alignment: .trailing)
        }
        .font(.caption2.monospacedDigit())
        .lineLimit(1)
    }
}

// MARK: - Message column

/// TX tag, highlight marker, message text, needed badges and the optional mode
/// suffix, on one line. The message text has the highest layout priority so the
/// callsigns stay readable. Badges shrink next and the mode suffix goes first.
struct DecodeRowMessage: View {
    let msg: FT8Message
    var needed: NeededStatus = []
    var highlight: RowHighlight = .none
    var showsMode: Bool = false
    var font: Font = .caption
    var forMeColor: Color = .blue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DecodeRowMetrics.messageSpacing) {
            if msg.isTX {
                Text("TX")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            RowHighlightMarker(highlight: highlight)

            Text(msg.text)
                .font(font)
                .fontWeight(highlight == .none ? .regular : .bold)
                .foregroundStyle((msg.forMe && !msg.isTX) ? forMeColor : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            NeededBadgeView(status: needed)
                .layoutPriority(0)

            if showsMode {
                Text(verbatim: "(\(msg.mode.rawValue.uppercased()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
    }
}

// MARK: - Active QSO bar

extension View {
    /// Draws a thin bar on the leading edge of a row that belongs to the QSO in
    /// progress. It is an overlay, so it takes no content width, and it flips
    /// to the trailing edge under right-to-left layouts.
    func activeQSOBar(_ isActive: Bool, color: Color = RowColorStore.shared.color(.activeQSO)) -> some View {
        overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(color)
                    .frame(width: DecodeRowMetrics.activeQSOBarWidth)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Active QSO"))
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
/// Fixtures for the decode row previews.
private enum DecodeRowPreviewFixtures {
    static let message = FT8Message(
        text: "EA4IQL UB5OFG -12", mode: .ft8,
        measuredSNR: -12, frequency: 1510, timeOffset: 0.1, isTX: false
    )
    static let crossModeMessage = FT8Message(
        text: "EA4IQL UB5OFG -12", mode: .ft4,
        measuredSNR: -12, frequency: 1510, timeOffset: 0.3, isTX: false
    )
    static let badgeSets: [NeededStatus] = [[], [.dxcc], [.dxcc, .grid]]
    static let widths: [CGFloat] = [156, 240, 400]
}

private struct DecodeRowPreviewGrid: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(DecodeRowPreviewFixtures.widths, id: \.self) { width in
                    Text(verbatim: "\(Int(width)) pt")
                        .font(.caption.bold())
                    VStack(spacing: 0) {
                        MessageListHeaderView(allowReply: true)
                        ForEach(0..<DecodeRowPreviewFixtures.badgeSets.count, id: \.self) { badgeIndex in
                            ForEach([false, true], id: \.self) { crossMode in
                                ForEach([false, true], id: \.self) { active in
                                    CondensedMsgView(
                                        msg: crossMode ? DecodeRowPreviewFixtures.crossModeMessage : DecodeRowPreviewFixtures.message,
                                        needed: DecodeRowPreviewFixtures.badgeSets[badgeIndex],
                                        showsMode: crossMode,
                                        isActiveQSO: active
                                    )
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(width: width)
                    .border(Color.secondary.opacity(0.3))
                }
            }
            .padding()
        }
    }
}

#Preview("Decode rows, default size") {
    DecodeRowPreviewGrid()
}

#Preview("Decode rows, AX5") {
    DecodeRowPreviewGrid()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Standard rows, default and AX5") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([DynamicTypeSize.large, .accessibility5], id: \.self) { size in
                ForEach(DecodeRowPreviewFixtures.widths, id: \.self) { width in
                    VStack(spacing: 0) {
                        MessageListHeaderView(allowReply: true)
                        ForEach(0..<DecodeRowPreviewFixtures.badgeSets.count, id: \.self) { badgeIndex in
                            ForEach([false, true], id: \.self) { flag in
                                MessageView(
                                    msg: flag ? DecodeRowPreviewFixtures.crossModeMessage : DecodeRowPreviewFixtures.message,
                                    needed: DecodeRowPreviewFixtures.badgeSets[badgeIndex],
                                    showsMode: flag,
                                    isActiveQSO: flag
                                )
                                Divider()
                            }
                        }
                    }
                    .frame(width: width)
                    .border(Color.secondary.opacity(0.3))
                    .dynamicTypeSize(size)
                }
            }
        }
        .padding()
    }
}
#endif
