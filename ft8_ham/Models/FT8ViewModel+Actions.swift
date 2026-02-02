//
//  FT8ViewModel+Actions.swift
//  ft_ham
//
//  Created by Pablo Turrion on 12/1/26.
//

import Foundation
import UIKit

extension FT8ViewModel {
    
    // MARK: - TX Loop Management
    @MainActor
    func stopCurrentTX() {
        txLogger.log(.info, "Stopping current TX...")
        audioManager.stopPlayback()
        
        isTransmitting = false
        invalidatePendingTX(reason: "Manual stopCurrentTX")
        
        if transmitLoopActive {
            transmitLoopActive = false
            appLogger.log(.info, "Auto TX stopped by user")
        }
    }
    
    @MainActor
    func toggleTransmit() {
        transmitLoopActive.toggle()
        
        if transmitLoopActive {
            appLogger.log(.info, "Auto TX enabled")
            if qsoManager.qsoState == .idle {
                qsoManager.startCallingCQ()
            }
            invalidatePendingTX(reason: "TX enabled")
            if sequencerTask == nil {
                startSequencer()
            }
        } else {
            qsoManager.resetQSO()
            selectedMessageIndex = 0
            appLogger.log(.info, "Auto TX disabled")
        }
    }
    
    // MARK: - Mode Switching
    @MainActor
    func switchModeWhileRX(isFT4 newMode: Bool) {
        rxLogger.log(.info, "Switching mode from \(isFT4 ? "FT4" : "FT8") to \(newMode ? "FT4" : "FT8")...")
        
        stopSequencer()
        
        Task { @MainActor in
             try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
             
             self.isFT4 = newMode
             self.waterfallVM.mode = newMode ? .ft4 : .ft8
             self.waterfallVM.resyncNextTimestampFromNow()
             
             self.startSequencer()
        }
    }
        
    func generateADIFExport() -> URL? {
        appLogger.info("User requested ADIF export")
        AnalyticsManager.shared.logADIFExport(qsoCount: qsoList.count)
        return logbookManager.saveToADIF(qsoList)
    }

}
