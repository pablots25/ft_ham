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
        // Record send time before the async call so polling is suppressed immediately
        lastCatSendDate = Date()
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

    // MARK: - Frequency Polling (Radio → App)

    /// Called once during app init to kick off polling and pre-warm the connection if already configured.
    @MainActor
    func startCatFrequencyPollingIfNeeded() {
        guard catEnabled else { return }
        connectCatController()
        if catSyncFrequency {
            startCatFrequencyPolling()
        }
    }

    /// Opens the persistent CAT connection using the current host/port settings.
    @MainActor
    func connectCatController() {
        let host = catHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = catPortValue(), !host.isEmpty else { return }
        catController.connect(host: host, port: port)
    }

    /// Starts a 2-second repeating timer that polls the rig frequency and syncs the app.
    @MainActor
    func startCatFrequencyPolling() {
        stopCatFrequencyPolling()
        guard catEnabled, catSyncFrequency else { return }
        catPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollCatFrequency()
        }
        appLogger.debug("CAT frequency polling started (2s interval)")
    }

    @MainActor
    func stopCatFrequencyPolling() {
        catPollingTimer?.invalidate()
        catPollingTimer = nil
    }

    /// Queries the rig frequency and updates the app if the radio was tuned externally.
    @MainActor
    private func pollCatFrequency() {
        guard catEnabled, catSyncFrequency, !isTransmitting else { return }
        // Suppress poll for 1.5 s after the app sent a frequency to avoid echoing it back
        if let sendDate = lastCatSendDate, Date().timeIntervalSince(sendDate) < 1.5 { return }

        let host = catHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = catPortValue(), !host.isEmpty else { return }

        Task {
            let response = await catController.getFrequency(host: host, port: port)
            guard response.success,
                  let polledHz = Int64(response.response.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            await MainActor.run { [weak self] in
                self?.applyPolledFrequency(polledHz)
            }
        }
    }

    /// Applies a frequency polled from the rig to the app's band/frequency state.
    @MainActor
    private func applyPolledFrequency(_ polledHz: Int64) {
        // Remove audio offset if it was added on send, to get the true dial frequency
        let audioOffsetHz: Int64 = catApplyAudioOffset ? Int64(frequency.rounded()) : 0
        let baseDialHz = polledHz - audioOffsetHz

        // Determine current known dial Hz for comparison
        let mode: FT8Message.FT8MessageMode = isFT4 ? .ft4 : .ft8
        let currentDialHz: Int64
        if selectedBand == .custom {
            currentDialHz = Int64(customDialFrequencyHz.rounded())
        } else if let known = selectedBand.frequency(for: mode) {
            currentDialHz = Int64(known.rounded())
        } else {
            currentDialHz = Int64(customDialFrequencyHz.rounded())
        }

        // Only react when the rig has moved by more than 10 Hz (filters VFO noise / rounding)
        guard abs(baseDialHz - currentDialHz) > 10 else { return }

        appLogger.info("CAT poll: rig=\(polledHz) Hz, app=\(currentDialHz) Hz — updating app")

        // Guard so updating selectedBand/customDialFrequencyHz doesn't re-send to the rig
        isCatPollingUpdate = true
        defer { isCatPollingUpdate = false }

        let detectedBand = FT8Message.Band.fromFrequency(Double(baseDialHz))
        if detectedBand != .unknown,
           let bandFreq = detectedBand.frequency(for: mode),
           abs(Int64(bandFreq.rounded()) - baseDialHz) < 200 {
            // Radio is at a standard FT8/FT4 dial frequency — switch to that band
            selectedBand = detectedBand
        } else {
            // Non-standard or unknown band — remember exact frequency via Custom
            customDialFrequencyHz = Double(baseDialHz)
            selectedBand = .custom
        }
    }
}
