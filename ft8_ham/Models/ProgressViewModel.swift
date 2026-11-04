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
/// FT8ViewModel is the single source of truth for mode (isFT4).
@MainActor
final class ProgressViewModel: ObservableObject {

    /// Static cycle lengths (derived from FT8ViewModel mode)
    private static let ft8CycleLength: Double = 15.0
    private static let ft4CycleLength: Double = 7.5

    /// Where the corrected clock reads right now; injectable for tests.
    private let now: () -> Date

    init(now: @escaping () -> Date = { AppClock.now() }) {
        self.now = now
    }

    // MARK: - Public API

    static func cycleLengthForMode(isFT4: Bool) -> Double {
        isFT4 ? ft4CycleLength : ft8CycleLength
    }

    /// 0…1, how far into the current slot the corrected clock is.
    func cycleProgress(isFT4: Bool) -> Double {
        Self.phase(at: now(), cycleLength: Self.cycleLengthForMode(isFT4: isFT4))
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
