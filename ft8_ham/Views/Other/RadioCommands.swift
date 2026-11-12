//
//  RadioCommands.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/11/26.
//

import Combine
import SwiftUI

// MARK: - Availability

/// Which radio commands can run right now. Mirrors the rules of
/// `TransmissionButtonsBar`, so a shortcut never does what its button would
/// refuse to do.
struct RadioCommandAvailability: Equatable {
    var settingsLoaded = false
    var isListening = false
    var isTransmitting = false
    var transmitLoopActive = false
    var freeTextLoopActive = false

    var canToggleRX: Bool { settingsLoaded }
    var canToggleAutoTX: Bool { settingsLoaded }
    var canStopTX: Bool { settingsLoaded && isTransmitting }
    var canStopAll: Bool {
        settingsLoaded && (isListening || isTransmitting || transmitLoopActive || freeTextLoopActive)
    }

    var rxTitle: LocalizedStringKey { isListening ? "Stop RX" : "Start RX" }
    var autoTXTitle: LocalizedStringKey { transmitLoopActive ? "Stop Auto TX" : "Start Auto TX" }
}

// MARK: - Model

/// Feeds the menu bar commands. It republishes only the few values the menu
/// shows, so the menu is not rebuilt on every decoded message.
@MainActor
final class RadioCommandsModel: ObservableObject {
    @Published private(set) var availability = RadioCommandAvailability()

    private weak var viewModel: FT8ViewModel?
    private var cancellable: AnyCancellable?

    /// Starts following the view model. Called once the window is up, so the
    /// view model is still created after Firebase is configured.
    func attach(to viewModel: FT8ViewModel) {
        guard self.viewModel !== viewModel else { return }
        self.viewModel = viewModel
        cancellable = Publishers.CombineLatest4(
            viewModel.rootState.$settingsLoaded,
            viewModel.$isListening,
            viewModel.$isTransmitting,
            viewModel.$transmitLoopActive
        )
        .combineLatest(viewModel.$freeTextLoopActive)
        .map { state, freeText in
            RadioCommandAvailability(
                settingsLoaded: state.0,
                isListening: state.1,
                isTransmitting: state.2,
                transmitLoopActive: state.3,
                freeTextLoopActive: freeText
            )
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.availability = $0 }
    }

    func toggleRX() {
        guard let viewModel, availability.canToggleRX else { return }
        if viewModel.isListening {
            Task { await viewModel.stopSequencer() }
        } else {
            viewModel.startSequencer()
        }
    }

    func toggleAutoTX() {
        guard availability.canToggleAutoTX else { return }
        viewModel?.toggleTransmit()
    }

    func stopTX() {
        guard availability.canStopTX else { return }
        viewModel?.stopCurrentTX()
    }

    func stopAll() {
        guard let viewModel, availability.canStopAll else { return }
        viewModel.stopCurrentTX()
        Task { await viewModel.stopSequencer() }
    }

    func open(_ tab: AppTab) {
        TabRouter.shared.open(tab)
    }
}

// MARK: - Commands

/// The Radio menu and tab shortcuts. On a Mac they appear in the menu bar, on
/// an iPad with a keyboard in the Command-key overlay.
struct RadioCommands: Commands {
    @ObservedObject var model: RadioCommandsModel

    var body: some Commands {
        CommandMenu("Radio") {
            let state = model.availability

            Button(state.rxTitle) { model.toggleRX() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!state.canToggleRX)

            Button(state.autoTXTitle) { model.toggleAutoTX() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!state.canToggleAutoTX)

            Divider()

            Button("Stop TX") { model.stopTX() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!state.canStopTX)

            Button("Stop all") { model.stopAll() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(!state.canStopAll)
        }

        CommandGroup(after: .sidebar) {
            Button("TX/RX") { model.open(.transmissions) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Waterfall") { model.open(.waterfall) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Map") { model.open(.map) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Logbook") { model.open(.logbook) }
                .keyboardShortcut("4", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Configuration") { model.open(.configuration) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}
