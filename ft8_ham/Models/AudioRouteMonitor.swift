//
//  AudioRouteMonitor.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/11/26.
//

import AVFoundation
import Combine

/// Publishes the names of the audio input and output in use and follows
/// route changes. On a Mac the app always uses the system default devices,
/// so showing them tells the operator whether the radio interface is the one
/// selected in System Settings.
@MainActor
final class AudioRouteMonitor: ObservableObject {
    @Published private(set) var inputName: String?
    @Published private(set) var outputName: String?

    private let session: AVAudioSession
    private var cancellable: AnyCancellable?

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        refresh()
        cancellable = NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification, object: session)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let route = session.currentRoute
        inputName = Self.displayName(for: route.inputs.map(\.portName))
        outputName = Self.displayName(for: route.outputs.map(\.portName))
    }

    /// Joins the port names of one direction, or `nil` when there is none.
    nonisolated static func displayName(for portNames: [String]) -> String? {
        let names = portNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}
