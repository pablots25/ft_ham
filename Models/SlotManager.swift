//
//  SlotManager.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 15/12/25.
//

import Foundation

struct SlotInfo: Sendable {
    let startTime: Date
    let slotIndex: Int
    let isEven: Bool
    let isFT4: Bool
}

actor SlotManager {
    
    // MARK: - Time Bases
    private let monotonicClock = ContinuousClock()
    
    // MARK: - Hybrid Timing (Fix for Problem #1)
    
    /// Tracks the relationship between wall clock and monotonic clock
    private struct TimeAnchor: Sendable {
        let wallClock: Date
        let monotonicInstant: ContinuousClock.Instant
        
        init(wallClock: Date, monotonicInstant: ContinuousClock.Instant) {
            self.wallClock = wallClock
            self.monotonicInstant = monotonicInstant
        }
    }
    
    private var anchor: TimeAnchor?
    private let maxDriftBeforeReanchor: Double = 0.5  // seconds
    
    // MARK: - Jitter Protection
    
    /// Minimum safe distance (seconds) from a slot boundary to allow scheduling.
    /// If we are closer than this to the NEXT boundary, we skip an entire slot.
    private let boundaryJitterThreshold: Double = 0.05
    
    // MARK: - Core Logic
    
    /// Returns information about the NEXT slot boundary suitable for transmission
    /// Always returns a slot in the future to prevent runaway loops
    func getNextSlot(from referenceDate: Date = Date(), isFT4: Bool) -> SlotInfo {
        let cycleDuration: Double = isFT4 ? 7.5 : 15.0
        let absoluteTime = referenceDate.timeIntervalSince1970
        
        // Calculate current slot
        let currentSlotIndex = floor(absoluteTime / cycleDuration)
        let currentSlotStart = currentSlotIndex * cycleDuration
        let elapsedInSlot = absoluteTime - currentSlotStart
        
        // Time remaining until the next boundary
        let timeToNextBoundary = cycleDuration - elapsedInSlot
        
        let targetSlotIndex: Int
        
        // MARK: - Boundary Jitter Protection (Explicit)
        //
        // If we are extremely close to the next boundary, scheduling that slot
        // can cause double triggers or late TX starts.
        // In that case, we skip one full slot ahead.
        if timeToNextBoundary < boundaryJitterThreshold {
            targetSlotIndex = Int(currentSlotIndex) + 2
            AppLogger.shared.debug(
                "[SlotManager] Skipping boundary due to jitter protection " +
                "(timeToNextBoundary=\(String(format: "%.3f", timeToNextBoundary))s)"
            )
        } else {
            // MARK: - Original Logic (Preserved)
            
            // Determine which slot to return
            // If we're very early in the current slot (< 100ms), we can still use it
            // Otherwise, return the next slot
            if elapsedInSlot < 0.1 {
                // Just started this slot, we can use it
                targetSlotIndex = Int(currentSlotIndex)
            } else {
                // Too far into current slot, return next
                targetSlotIndex = Int(currentSlotIndex) + 1
            }
        }
        
        let targetStart = Double(targetSlotIndex) * cycleDuration
        let info = SlotInfo(
            startTime: Date(timeIntervalSince1970: targetStart),
            slotIndex: targetSlotIndex,
            isEven: targetSlotIndex % 2 == 0,
            isFT4: isFT4
        )
        
        AppLogger.shared.debug("[SlotManager] Next slot: \(info.slotIndex) starts at \(info.startTime)")
        return info
    }
    
    /// Returns slot info for a specific point in time (doesn't have to be a boundary)
    func getSlotInfo(at date: Date, isFT4: Bool) -> SlotInfo {
        let cycleDuration: Double = isFT4 ? 7.5 : 15.0
        let absoluteTime = date.timeIntervalSince1970
        let slotIndex = Int(floor(absoluteTime / cycleDuration))
        let slotStart = Double(slotIndex) * cycleDuration
        
        return SlotInfo(
            startTime: Date(timeIntervalSince1970: slotStart),
            slotIndex: slotIndex,
            isEven: slotIndex % 2 == 0,
            isFT4: isFT4
        )
    }

    /// High precision wait with hybrid timing approach (Fix for Problem #1)
    /// Uses monotonic clock for stability while staying synchronized with wall clock
    func wait(until targetWallClock: Date) async throws {
        let now = Date()
        let nowInstant = ContinuousClock.now
        
        // Establish anchor if needed
        if anchor == nil {
            anchor = TimeAnchor(wallClock: now, monotonicInstant: nowInstant)
        }
        
        // Calculate target instant from anchor
        let elapsedWall = targetWallClock.timeIntervalSince(anchor!.wallClock)
        let targetInstant = anchor!.monotonicInstant + .seconds(elapsedWall)
        
        // Sleep using monotonic clock for stability
        try await monotonicClock.sleep(until: targetInstant)
        
        // Verify we didn't drift too much
        let actualWallClock = Date()
        let drift = actualWallClock.timeIntervalSince(targetWallClock)
        
        if abs(drift) > maxDriftBeforeReanchor {
            // Re-anchor due to significant drift (likely NTP adjustment)
            anchor = TimeAnchor(wallClock: actualWallClock, monotonicInstant: ContinuousClock.now)
            AppLogger.shared.log(.warning, "[SlotManager] Re-anchored due to drift: \(String(format: "%.3f", drift))s")
        }
    }
    
    /// Manually reset the time anchor (useful for testing or after long suspend)
    func resetAnchor() {
        anchor = nil
    }
}
