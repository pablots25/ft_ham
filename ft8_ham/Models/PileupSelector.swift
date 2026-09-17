//
//  PileupSelector.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation

/// Picks which caller gets the QSO when several stations answer our CQ in
/// the same slot.
///
/// The decoder returns the slot's messages in an arbitrary order, so without
/// this the "winner" of a pile-up is whoever the dictionary happened to list
/// first. The selector moves one randomly chosen caller to the front of the
/// batch; `QSOStatusManager` then locks onto it and ignores the rest.
struct PileupSelector {
    /// Prefer stations not yet in the logbook when at least one is calling.
    var preferNeverWorked: Bool
    var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()

    /// Messages in `messages` that are a station answering our CQ.
    /// Duplicate decodes of the same caller (different tones) count once.
    static func candidates(in messages: [FT8Message], myCallsign: String) -> [FT8Message] {
        let me = myCallsign.uppercased()
        guard !me.isEmpty else { return [] }
        var seen = Set<String>()
        return messages.filter { msg in
            guard !msg.isTX,
                  msg.msgType == .gridExchange || msg.msgType == .standardSignalReport,
                  msg.dxCallsign?.uppercased() == me,
                  let call = msg.callsign, isValidCallsign(call),
                  !seen.contains(call) else { return false }
            seen.insert(call)
            return true
        }
    }

    /// Returns `messages` with the chosen caller moved to the front; every
    /// other message keeps its relative order. Returns the input unchanged
    /// when there is at most one caller.
    mutating func prioritize(
        _ messages: [FT8Message],
        myCallsign: String,
        workedCallsigns: Set<String>
    ) -> (messages: [FT8Message], chosen: FT8Message?, pileupSize: Int) {
        let callers = Self.candidates(in: messages, myCallsign: myCallsign)
        guard callers.count > 1 else { return (messages, callers.first, callers.count) }

        var pool = callers
        if preferNeverWorked {
            let fresh = callers.filter { !workedCallsigns.contains($0.callsign ?? "") }
            if !fresh.isEmpty { pool = fresh }
        }
        let chosen = pool[Int.random(in: 0..<pool.count, using: &rng)]

        var reordered = messages
        if let idx = reordered.firstIndex(where: { $0.id == chosen.id }) {
            reordered.remove(at: idx)
            reordered.insert(chosen, at: 0)
        }
        return (reordered, chosen, callers.count)
    }
}
