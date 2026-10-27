//
//  DeviceVolumeMonitor.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/10/26.
//

import AVFoundation
import Combine

// MARK: - TX volume hint

/// Decides when the TX settings should remind the user to turn the device
/// volume up. The TX output gain only scales the samples, the device volume is
/// applied after it, so a turned down volume keeps the audio too quiet for a
/// radio's VOX however high the gain slider goes.
enum TXVolumeHint {
    /// `outputVolume` is quantized to the volume button steps (1/16), so
    /// anything short of the top step counts as turned down.
    static let fullVolumeThreshold: Float = 0.99

    static func shouldShow(forVolume volume: Float) -> Bool {
        guard volume.isFinite else { return false }
        return volume < fullVolumeThreshold
    }
}

// MARK: - Device volume monitor

/// Publishes the device media volume for the current audio route and follows
/// changes made with the volume buttons or Control Center.
@MainActor
final class DeviceVolumeMonitor: ObservableObject {
    @Published private(set) var volume: Float

    private var observation: NSKeyValueObservation?

    init(session: AVAudioSession = .sharedInstance()) {
        volume = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let newVolume = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.volume = newVolume
            }
        }
    }

    var showsLowVolumeHint: Bool {
        TXVolumeHint.shouldShow(forVolume: volume)
    }
}
