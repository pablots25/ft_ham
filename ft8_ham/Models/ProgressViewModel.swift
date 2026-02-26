//
//  ProgressViewModel.swift
//  ft8_ham
//
//  Anchor-based progress (no timers/tasks)
//

import Foundation

/// Isolated ViewModel for cycle progress tracking
/// Uses monotonic uptime with an anchor to avoid timers and tasks
@MainActor
final class ProgressViewModel: ObservableObject {
    
    // MARK: - Public Properties
    
    private(set) var isFT4: Bool {
        didSet { currentCycleLength = isFT4 ? Self.ft4CycleLength : Self.ft8CycleLength }
    }
    
    // MARK: - Private Properties
    
    private var anchorUptime: TimeInterval
    private var currentCycleLength: Double
    
    /// Static cycle lengths
    private static let ft8CycleLength: Double = 15.0
    private static let ft4CycleLength: Double = 7.5
    
    // MARK: - Initialization
    
    init(isFT4: Bool = false) {
        self.isFT4 = isFT4
        self.currentCycleLength = isFT4 ? Self.ft4CycleLength : Self.ft8CycleLength
        self.anchorUptime = Self.computeAlignedAnchorUptime(cycleLength: currentCycleLength)
    }
    
    // MARK: - Public API
    
    func updateMode(isFT4: Bool) {
        guard self.isFT4 != isFT4 else { return }
        self.isFT4 = isFT4
        anchorUptime = Self.computeAlignedAnchorUptime(cycleLength: currentCycleLength)
    }
    
    func resetCycle() {
        anchorUptime = ProcessInfo.processInfo.systemUptime
    }
    
    func cycleProgress() -> Double {
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = uptime - anchorUptime
        return elapsed.truncatingRemainder(dividingBy: currentCycleLength) / currentCycleLength
    }

    private static func computeAlignedAnchorUptime(cycleLength: Double) -> TimeInterval {
        let uptime = ProcessInfo.processInfo.systemUptime
        let wallClock = Date().timeIntervalSince1970
        let offsetInCycle = wallClock.truncatingRemainder(dividingBy: cycleLength)
        // Anchor so progress aligns to real-time cycle boundaries.
        return uptime - offsetInCycle
    }
}