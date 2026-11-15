//
//  GuidanceCoordinator.swift
//  ft_ham
//
//  Puts the first-run tutorials in a queue so they never pile up on each
//  other or on top of a launch prompt.
//
//  Order on a first launch:
//    1. Onboarding, terms, What's New (full-screen covers)
//    2. "Callsign and Locator not configured" alert
//    3. Messages Guide sheet (first time TX/RX is shown)
//    4. Tutorials, one at a time, on the tab that is on screen
//    5. Rating, sharing, donation and Premium prompts
//
//  `ContentView` reports steps 1–3 and 5 through `setBlocked(_:)`. A
//  tutorial is only granted when none of them is on screen or about to be.
//

import Foundation

/// The coach-mark overlays the app shows once.
enum AppTutorial: String, CaseIterable {
    /// "Swipe a message to reply", over the TX/RX message lists.
    case slideToReply
    /// What each waterfall toolbar button does.
    case waterfallButtons

    /// The `@AppStorage` key that records the tutorial as seen.
    var seenKey: String {
        switch self {
        case .slideToReply: return "hasSeenSlideToReplyTutorial"
        case .waterfallButtons: return "hasSeenFloatingButtonTutorial"
        }
    }
}

@MainActor
final class GuidanceCoordinator: ObservableObject {

    static let shared = GuidanceCoordinator()

    /// Lets a dismissing alert, sheet or cover finish its animation, and gives
    /// a launch prompt that is about to appear the time to report itself,
    /// before a tutorial takes the screen.
    nonisolated static let settleDelay: Duration = .milliseconds(800)

    /// The tutorial that may be on screen now, if any.
    @Published private(set) var activeTutorial: AppTutorial?

    /// `true` while a launch prompt, sheet or alert is on screen or due.
    private(set) var isBlocked = true

    /// Tutorials whose view is on screen and wants to show them, oldest first.
    private var waiting: [AppTutorial] = []

    private var grantTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let settleDelay: Duration

    init(defaults: UserDefaults = .standard, settleDelay: Duration = GuidanceCoordinator.settleDelay) {
        self.defaults = defaults
        self.settleDelay = settleDelay
    }

    /// `true` when no tutorial is on screen.
    var isIdle: Bool { activeTutorial == nil }

    // MARK: - Inputs

    /// Reported by `ContentView`: a launch prompt, the settings alert, the
    /// Messages Guide or an in-app prompt is on screen or about to be.
    func setBlocked(_ blocked: Bool) {
        guard blocked != isBlocked else { return }
        isBlocked = blocked
        if blocked {
            // A prompt that comes up takes precedence. The tutorial is shown
            // again once the screen is free, because its view still waits.
            grantTask?.cancel()
            activeTutorial = nil
        } else {
            scheduleGrant()
        }
    }

    /// A view that can show `tutorial` came on screen.
    func request(_ tutorial: AppTutorial) {
        guard !hasSeen(tutorial) else { return }
        if !waiting.contains(tutorial) { waiting.append(tutorial) }
        scheduleGrant()
    }

    /// The view left the screen, or no longer can show it (e.g. RX stopped).
    func withdraw(_ tutorial: AppTutorial) {
        waiting.removeAll { $0 == tutorial }
        if activeTutorial == tutorial {
            activeTutorial = nil
            scheduleGrant()
        }
    }

    /// The user dismissed the tutorial: it is not shown again.
    func finish(_ tutorial: AppTutorial) {
        defaults.set(true, forKey: tutorial.seenKey)
        withdraw(tutorial)
    }

    // MARK: - Decision

    /// Which tutorial to show next. Pure, for unit tests.
    nonisolated static func nextTutorial(
        active: AppTutorial?,
        waiting: [AppTutorial],
        isBlocked: Bool,
        hasSeen: (AppTutorial) -> Bool
    ) -> AppTutorial? {
        if let active { return active }
        guard !isBlocked else { return nil }
        return waiting.first { !hasSeen($0) }
    }

    private func hasSeen(_ tutorial: AppTutorial) -> Bool {
        defaults.bool(forKey: tutorial.seenKey)
    }

    private func scheduleGrant() {
        grantTask?.cancel()
        grantTask = Task { @MainActor [weak self] in
            guard let delay = self?.settleDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.grantIfPossible()
        }
    }

    private func grantIfPossible() {
        // Drop tutorials marked as seen elsewhere (e.g. the waterfall's
        // frequency button also marks its tutorial as seen).
        waiting.removeAll { hasSeen($0) }
        let next = Self.nextTutorial(
            active: activeTutorial,
            waiting: waiting,
            isBlocked: isBlocked,
            hasSeen: hasSeen
        )
        if next != activeTutorial { activeTutorial = next }
    }
}
