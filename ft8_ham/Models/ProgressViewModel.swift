//
//  ProgressViewModel.swift
//  ft8_ham
//
//  Created for CPU optimization on 26/02/26.
//  Isolates cycleProgress updates to reduce AttributeGraph overhead
//

import Combine
import Foundation

/// Isolated ViewModel for cycle progress tracking
/// Prevents cycleProgress updates from triggering full view hierarchy recomputation
@MainActor
final class ProgressViewModel: ObservableObject {
    
    @Published private(set) var cycleProgress: Double = 0
    
    private var progressTimerCancellable: AnyCancellable?
    private var isFT4: Bool
    
    init(isFT4: Bool = false) {
        self.isFT4 = isFT4
    }
    
    func updateMode(isFT4: Bool) {
        guard self.isFT4 != isFT4 else { return }
        self.isFT4 = isFT4
        // Timer will pick up new cycle length automatically
    }
    
    func start() {
        progressTimerCancellable?.cancel()
        
        // Reduced from 0.05s (20 Hz) to 0.2s (5 Hz) to reduce CPU usage
        // Progress bar updates are smooth enough at 5 Hz
        progressTimerCancellable = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                let calendar = Calendar.current
                let seconds = calendar.component(.second, from: now)
                let nanoseconds = calendar.component(.nanosecond, from: now)
                
                let cycleLength = self.isFT4 ? 7.5 : 15.0
                let totalSeconds = Double(seconds) + Double(nanoseconds) / 1_000_000_000
                let slotProgress = totalSeconds.truncatingRemainder(dividingBy: cycleLength) / cycleLength
                self.cycleProgress = slotProgress
            }
    }
    
    func stop() {
        progressTimerCancellable?.cancel()
        progressTimerCancellable = nil
        cycleProgress = 0
    }
}
