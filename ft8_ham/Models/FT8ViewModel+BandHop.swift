//
//  FT8ViewModel+BandHop.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import Combine

// MARK: - Autonomous band hopping (premium, behind `enableBandHopping`)
//
// The scheduler only counts down; the view model decides whether a hop is
// applied. A hop goes through `selectedBand`, whose setter already pushes the
// new dial frequency to the rig over CAT.

extension FT8ViewModel {

    /// Feature flag + entitlement; injectable so tests can force it on.
    var isBandHoppingAllowed: Bool {
        bandHopGate()
    }

    static func defaultBandHopGate() -> Bool {
        FeatureFlagManager.shared.isEnabled(.enableBandHopping) && PremiumManager.shared.isPremiumUnlocked
    }

    @MainActor
    func setupBandHopObserver() {
        bandHopCancellables.removeAll()

        bandHopScheduler.hopRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] band in self?.applyBandHop(to: band) }
            .store(in: &bandHopCancellables)

        bandHopScheduler.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.bandHopState = state }
            .store(in: &bandHopCancellables)

        // Freeze the countdown while a QSO is running or we are on the air.
        qsoManager.$qsoState
            .map { _ in () }
            .merge(with: $isTransmitting.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncBandHopPause() }
            .store(in: &bandHopCancellables)

        // The premium settings view flips `bandHopEnabled` / the schedule in
        // UserDefaults directly, which does not run this object's didSet.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcileBandHopping() }
            .store(in: &bandHopCancellables)
    }

    /// Starts or stops the scheduler so it matches the current settings.
    @MainActor
    func reconcileBandHopping() {
        let shouldRun = bandHopEnabled && isBandHoppingAllowed && catEnabled
        let schedule = BandHopSchedule.load()

        guard shouldRun, !schedule.isEmpty else {
            stopBandHopping()
            return
        }
        // Restart only when the rotation itself changed.
        if bandHopState != .stopped, schedule == activeBandHopSchedule { return }
        activeBandHopSchedule = schedule
        bandHopScheduler.start(schedule: schedule, startingAt: selectedBand.rawValue)
        syncBandHopPause()
    }

    @MainActor
    func startBandHoppingIfNeeded() {
        reconcileBandHopping()
    }

    @MainActor
    func stopBandHopping() {
        activeBandHopSchedule = nil
        bandHopScheduler.stop()
    }

    @MainActor
    func skipToNextBand() {
        bandHopScheduler.skipToNext()
    }

    /// Applies a hop requested by the scheduler, unless something makes it
    /// unsafe right now (the rotation keeps counting either way).
    @MainActor
    func applyBandHop(to bandRaw: String) {
        guard bandHopEnabled, isBandHoppingAllowed else { return }
        guard catEnabled, catController.isConnected else {
            appLogger.warning("Band hop to \(bandRaw) skipped: CAT not connected")
            return
        }
        guard isSequencerRunning, !isTransmitting, !qsoManager.isQSOOngoing() else {
            appLogger.info("Band hop to \(bandRaw) skipped: busy")
            return
        }
        guard let band = FT8Message.Band(rawValue: bandRaw), band != .custom, band != .unknown,
              band.frequency(for: isFT4 ? .ft4 : .ft8) != nil else {
            appLogger.warning("Band hop skipped: '\(bandRaw)' has no dial frequency")
            return
        }
        guard band != selectedBand else { return }

        selectedBand = band
        clearRXBuffer()
        appLogger.info("Band hop → \(band.rawValue)")
        toast = .info(String(format: String(localized: "Hopped to %@"), band.rawValue))
    }

    @MainActor
    private func syncBandHopPause() {
        guard bandHopState != .stopped else { return }
        if qsoManager.isQSOOngoing() || isTransmitting {
            bandHopScheduler.pause()
        } else {
            bandHopScheduler.resume()
        }
    }
}
