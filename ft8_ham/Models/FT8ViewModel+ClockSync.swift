//
//  FT8ViewModel+ClockSync.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import Combine

// MARK: - Clock sync integration
//
// `SlotManager.wait(until:)` anchors the corrected wall clock to the
// monotonic clock once and sleeps on the latter. When the SNTP offset
// changes, that anchor is stale by exactly the change, so the next wait
// would land early or late and log a spurious "re-anchored due to drift".
// Resetting the anchor (once the current TX, if any, has finished) makes the
// next slot boundary come from the fresh corrected clock.

extension FT8ViewModel {

    @MainActor
    func setupClockSyncObserver() {
        ClockSyncManager.shared.$offset
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newOffset in
                self?.handleClockOffsetChanged(to: newOffset)
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func handleClockOffsetChanged(to newOffset: TimeInterval) {
        Task { [weak self] in
            guard let self else { return }
            // Never move the slot grid under an ongoing transmission.
            while self.isTransmitting {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            await self.slotManager.resetAnchor()
            self.appLogger.info(
                "Clock offset now \(String(format: "%+.3f", newOffset))s; slot anchor reset"
            )
        }
    }
}
