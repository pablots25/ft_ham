//
//  WaterfallSlotMark.swift
//  ft_ham
//
//  Created by Pablo Turrion on 22/9/26.
//

import Foundation

/// One transmission slot as the waterfall shows it: where it starts on the
/// row grid, which side of the even/odd alternation it is on, and whether we
/// transmitted during it.
///
/// FT8 alternates 15 second slots (FT4, 7.5 seconds). Stations you can work
/// transmit in the slot opposite yours, so seeing the alternation and your
/// own transmissions on the waterfall saves reading the clock.
struct WaterfallSlotMark: Equatable, Sendable, Identifiable {
    /// The monitor's slot counter, which also ties rows to their slot.
    var slotSequence: UInt
    /// Absolute row where the slot starts (its oldest row).
    var startRow: Int
    /// Rows the slot covers, from `startRow` upward. The slot in progress
    /// carries its expected length until the next one starts.
    var rowCount: Int
    /// True for slots beginning at an even multiple of the cycle length
    /// (:00 and :30 for FT8), which is the convention the sequencer uses.
    var isEvenCycle: Bool
    /// We transmitted in this slot.
    var isTransmit: Bool = false

    var id: UInt { slotSequence }

    /// Even or odd for the slot containing `date`, matching `SlotManager`.
    static func isEvenCycle(at date: Date, cycleLength: Double) -> Bool {
        guard cycleLength > 0 else { return true }
        let slotIndex = Int(floor(date.timeIntervalSince1970 / cycleLength))
        return slotIndex % 2 == 0
    }
}
