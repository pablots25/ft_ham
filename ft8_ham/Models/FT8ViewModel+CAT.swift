//
//  FT8ViewModel+CAT.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//

import Foundation

extension FT8ViewModel {

    @MainActor
    func setCatPTT(_ enabled: Bool, reason: String) {
        guard catEnabled, catPTTEnabled else { return }
        let host = catHost.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard let port = catPortValue(), !host.isEmpty else { return }

        Task {
            let response = await catController.setPTT(enabled: enabled, host: host, port: port)
            if !response.success {
                appLogger.warning("CAT PTT failed (\(reason)): \(response.errorMessage ?? "unknown")")
            }
        }
    }

    @MainActor
    func sendCatFrequency(reason: String) {
        guard catEnabled, catSyncFrequency else { return }
        let host = catHost.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard let port = catPortValue(), !host.isEmpty else { return }
        guard let dialHz = catDialFrequencyHz() else { return }

        Task {
            let response = await catController.setFrequency(frequency: dialHz, host: host, port: port)
            if !response.success {
                appLogger.warning("CAT frequency failed (\(reason)): \(response.errorMessage ?? "unknown")")
            }
        }
    }

    @MainActor
    func scheduleCatFrequencyUpdate(reason: String) {
        guard catEnabled, catSyncFrequency else { return }
        catFrequencyUpdateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.sendCatFrequency(reason: reason)
        }
        catFrequencyUpdateWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    @MainActor
    var catDialFrequencyMHz: Double? {
        guard let hz = catDialFrequencyHz() else { return nil }
        return Double(hz) / 1_000_000.0
    }

    @MainActor
    private func catDialFrequencyHz() -> Int64? {
        let mode: FT8Message.FT8MessageMode = isFT4 ? .ft4 : .ft8
        guard let baseHz = selectedBand.frequency(for: mode) else { return nil }
        let offset = catApplyAudioOffset ? frequency : 0
        return Int64((baseHz + offset).rounded())
    }

    private func catPortValue() -> UInt16? {
        guard catPort > 0, catPort <= 65_535 else { return nil }
        return UInt16(catPort)
    }
}
