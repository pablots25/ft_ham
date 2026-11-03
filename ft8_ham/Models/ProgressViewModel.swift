//
//  ProgressViewModel.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//

import Foundation

/// Isolated ViewModel for cycle progress tracking.
///
/// The phase comes from `AppClock.now()`, the same SNTP-corrected clock
/// `SlotManager` uses to schedule transmissions, so the bar and the TX slots
/// can never disagree. Reading one clock (instead of an uptime anchor checked
/// against the raw wall clock) also means there is nothing to realign.
/// FT8ViewModel is the single source of truth for mode (digitalMode).
@MainActor
final class ProgressViewModel: ObservableObject {

    /// Where the corrected clock reads right now; injectable for tests.
    private let now: () -> Date

    init(now: @escaping () -> Date = { AppClock.now() }) {
        self.now = now
    }

    // MARK: - Public API

    static func cycleLengthForMode(_ mode: DigitalMode) -> Double {
        mode.slotDuration
    }

    /// 0…1, how far into the current slot the corrected clock is.
    func cycleProgress(mode: DigitalMode) -> Double {
        Self.phase(at: now(), cycleLength: Self.cycleLengthForMode(mode))
    }

    /// Fraction of the slot elapsed at `date`, with slots aligned to the
    /// UTC epoch as `SlotManager` aligns them.
    nonisolated static func phase(at date: Date, cycleLength: Double) -> Double {
        guard cycleLength > 0 else { return 0 }
        var elapsed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: cycleLength)
        if elapsed < 0 { elapsed += cycleLength }
        return elapsed / cycleLength
    }
}
