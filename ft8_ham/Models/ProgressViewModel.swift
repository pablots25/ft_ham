//
//  ProgressViewModel.swift
//  ft8_ham
//
//  Anchor-based progress (no timers/tasks)
//

import Foundation
import Combine

/// Isolated ViewModel for cycle progress tracking
/// Uses monotonic uptime with an anchor to avoid timers and tasks
/// FT8ViewModel is the single source of truth for mode (isFT4)
@MainActor
final class ProgressViewModel: ObservableObject {
    
    // MARK: - Private Properties
    
    private var anchorUptime: TimeInterval
    private var cancellables = Set<AnyCancellable>()
    
    /// Static cycle lengths (derived from FT8ViewModel mode)
    private static let ft8CycleLength: Double = 15.0
    private static let ft4CycleLength: Double = 7.5
    private static let realignmentThresholdSeconds: Double = 0.4
    
    // MARK: - Initialization
    
    init() {
        self.anchorUptime = Self.computeAlignedAnchorUptime(cycleLength: Self.ft8CycleLength)
        observeClockChanges()
    }
    
    // MARK: - Public API
    
    func resetCycle() {
        anchorUptime = ProcessInfo.processInfo.systemUptime
    }

    static func cycleLengthForMode(isFT4: Bool) -> Double {
        isFT4 ? ft4CycleLength : ft8CycleLength
    }
    
    func cycleProgress(isFT4: Bool) -> Double {
        let cycleLength = Self.cycleLengthForMode(isFT4: isFT4)
        let uptime = ProcessInfo.processInfo.systemUptime
        let wallClock = Date().timeIntervalSince1970
        let uptimePhase = (uptime - anchorUptime).truncatingRemainder(dividingBy: cycleLength)
        let wallClockPhase = wallClock.truncatingRemainder(dividingBy: cycleLength)

        if Self.circularDistance(
            lhs: uptimePhase,
            rhs: wallClockPhase,
            modulo: cycleLength
        ) > Self.realignmentThresholdSeconds {
            realignAnchor(cycleLength: cycleLength)
            let realignedElapsed = ProcessInfo.processInfo.systemUptime - anchorUptime
            return realignedElapsed.truncatingRemainder(dividingBy: cycleLength) / cycleLength
        }

        return uptimePhase / cycleLength
    }

    private static func computeAlignedAnchorUptime(cycleLength: Double) -> TimeInterval {
        let uptime = ProcessInfo.processInfo.systemUptime
        let wallClock = Date().timeIntervalSince1970
        let offsetInCycle = wallClock.truncatingRemainder(dividingBy: cycleLength)
        // Anchor so progress aligns to real-time cycle boundaries.
        return uptime - offsetInCycle
    }

    private static func circularDistance(lhs: Double, rhs: Double, modulo: Double) -> Double {
        let distance = abs(lhs - rhs)
        return min(distance, modulo - distance)
    }

    /// Re-align anchor for computation of next progress cycle
    private func realignAnchor(cycleLength: Double) {
        anchorUptime = Self.computeAlignedAnchorUptime(cycleLength: cycleLength)
    }

    /// Force reset anchor when clock changes; will be recalculated next progress query
    private func resetAnchorOnClockChange() {
        anchorUptime = ProcessInfo.processInfo.systemUptime
    }

    private func observeClockChanges() {
        let notificationNames: [Notification.Name] = [
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
            .NSCalendarDayChanged
        ]

        for name in notificationNames {
            NotificationCenter.default
                .publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.resetAnchorOnClockChange()
                }
                .store(in: &cancellables)
        }
    }
}