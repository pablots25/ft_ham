//
//  WaterfallLabel.swift
//  ft_ham
//
//  Created by Pablo Turrion on 21/9/26.
//

import Foundation

/// A decoded message as the waterfall shows it: the text, where it was, and
/// what it means to the operator (which decides its colour).
struct WaterfallLabel: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Addressed to, or from a QSO with, our own callsign.
        case forMe
        /// A CQ from someone else.
        case cq
        /// Everything else on the band.
        case other
    }

    var text: String
    /// Base tone frequency in Hz.
    var frequency: Double
    var kind: Kind
    /// The sending station, used to mark stations already in the log.
    var callsign: String?
    /// Seconds from the start of the slot to the start of the signal (the
    /// decoder's DT), when known. Lets the label sit on the signal itself
    /// rather than at the moment it was decoded.
    var timeOffset: Double?
    /// The sending station is already in the logbook.
    var isWorked: Bool = false
    /// The decoded message behind the label, for replying from the waterfall.
    var messageID: UUID?

    init(
        text: String,
        frequency: Double,
        kind: Kind = .other,
        callsign: String? = nil,
        timeOffset: Double? = nil,
        isWorked: Bool = false,
        messageID: UUID? = nil
    ) {
        self.text = text
        self.frequency = frequency
        self.kind = kind
        self.callsign = callsign
        self.timeOffset = timeOffset
        self.isWorked = isWorked
        self.messageID = messageID
    }

    init(message: FT8Message) {
        let kind: Kind
        if message.forMe {
            kind = .forMe
        } else if message.msgType == .cq {
            kind = .cq
        } else {
            kind = .other
        }
        self.init(
            text: message.text,
            frequency: message.frequency,
            kind: kind,
            callsign: message.callsign,
            timeOffset: message.timeOffset.isFinite ? message.timeOffset : nil,
            messageID: message.id
        )
    }
}

/// A label the view model has placed on the row grid.
struct WaterfallPlacedLabel: Equatable, Sendable {
    var label: WaterfallLabel
    /// Absolute row of the signal's start (its oldest row), or of the
    /// decode moment when the start is unknown.
    var anchorRow: Int
    /// Rows the signal occupies above `anchorRow`; 0 when unknown, in which
    /// case the label hangs down from the anchor.
    var spanRows: Int
}
