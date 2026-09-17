//
//  RootUIState.swift
//  ft_ham
//
//  Small observable objects owned by FT8ViewModel that expose only the state
//  needed near the root of the view tree. Views observing these objects are not
//  invalidated by the (very frequent) publishes of the full FT8ViewModel.
//

import Foundation
import Combine

/// State read by `ContentView` and the app root: toast banner, whether the
/// station is configured, and the current mode (for the header progress bar).
@MainActor
final class RootUIState: ObservableObject {
    @Published var toast: ToastMessage?
    /// Presents the free-text TX sheet. It lives here, not in
    /// `TransmissionButtonsBar`, because that bar re-renders on every view
    /// model publish — a sheet anchored inside it is torn down and
    /// re-presented while you type.
    @Published var showFreeTextSheet: Bool = false
    @Published var settingsLoaded: Bool = false
    @Published var isFT4: Bool = false
}

/// State backing the "Confirm QSO logging" alert. Observed only by
/// `QSOLogConfirmationModifier`, which sits above `ContentView`.
@MainActor
final class QSOLogPrompt: ObservableObject {
    @Published var showConfirmQSOAlert: Bool = false
    @Published var pendingQSOToLog: LogEntry?
    @Published var pendingQSOIsUnconfirmed: Bool = false
}
