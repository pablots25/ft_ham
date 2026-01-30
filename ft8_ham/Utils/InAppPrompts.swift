//
//  InAppPrompts.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 4/1/26.
//

import SwiftUI
import StoreKit
import UIKit

/// InAppPrompts manages in-app notifications for sharing and rating the app
@MainActor
final class InAppPrompts: ObservableObject {

    static let shared = InAppPrompts()
    private let appLogger = AppLogger(category: "PROMPTS")

    // MARK: - UserDefaults keys
    fileprivate enum Keys {
        static let appLaunches = "appLaunches"
        static let hasShownSharePrompt = "hasShownSharePrompt"
        static let hasShownRatePrompt = "hasShownRatePrompt"
        static let postponedSharePrompt = "postponedSharePrompt"
        static let postponedRatePrompt = "postponedRatePrompt"
    }

    // MARK: - Thresholds
    private let shareThreshold = 6
    private let rateThreshold = 4
    private let reminderDelay = 10

    // MARK: - Session state
    private var hasPresentedPromptThisSession = false

    // MARK: - Published state for SwiftUI
    @Published var showRateAlert = false
    @Published var shareItem: ShareItem?

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private init() {
        observeAppLifecycle()
    }

    // MARK: - Lifecycle handling
    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc
    private func handleDidEnterBackground() {
        appLogger.debug("Resetting prompt session state")
        hasPresentedPromptThisSession = false
    }

    // MARK: - Public API
    func checkPrompts() {
        guard !hasPresentedPromptThisSession else { return }

        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: Keys.appLaunches) + 1
        defaults.set(launches, forKey: Keys.appLaunches)

        appLogger.debug("App launch count: \(launches)")

        // MARK: - Rate logic
        let rateShown = defaults.bool(forKey: Keys.hasShownRatePrompt)
        let ratePostponed = defaults.integer(forKey: Keys.postponedRatePrompt)

        let shouldShowRate =
            !rateShown &&
            ((ratePostponed == 0 && launches == rateThreshold) ||
             (ratePostponed > 0 && launches - ratePostponed >= reminderDelay))

        if shouldShowRate {
            hasPresentedPromptThisSession = true

            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                showRateAlert = true
            }
            return
        }

        // MARK: - Share logic
        let shareShown = defaults.bool(forKey: Keys.hasShownSharePrompt)
        let sharePostponed = defaults.integer(forKey: Keys.postponedSharePrompt)

        let shouldShowShare =
            !shareShown &&
            ((sharePostponed == 0 && launches == shareThreshold) ||
             (sharePostponed > 0 && launches - sharePostponed >= reminderDelay))

        if shouldShowShare {
            hasPresentedPromptThisSession = true

            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let url = URL(string: "https://apps.apple.com/app/id6755367558") {
                    shareItem = ShareItem(url: url)
                }
            }
        }
    }

    // MARK: - Rate actions
    func requestRate() {
        let defaults = UserDefaults.standard
        AnalyticsManager.shared.logRateConfirmed()

        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: scene)
        }

        defaults.set(true, forKey: Keys.hasShownRatePrompt)
    }

    func postponeRate() {
        let defaults = UserDefaults.standard
        AnalyticsManager.shared.logRatePostponed()

        defaults.set(defaults.integer(forKey: Keys.appLaunches),
                     forKey: Keys.postponedRatePrompt)
    }

    // MARK: - Share actions
    func markShareCompleted() {
        AnalyticsManager.shared.logShareCompleted()
        UserDefaults.standard.set(true, forKey: Keys.hasShownSharePrompt)
    }

    func postponeShare() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Keys.appLaunches),
                     forKey: Keys.postponedSharePrompt)
    }
}

// MARK: - SwiftUI Modifier
struct InAppPromptsViewModifier: ViewModifier {

    @ObservedObject var prompts = InAppPrompts.shared

    func body(content: Content) -> some View {
        content
            .alert("Enjoying FT-Ham?", isPresented: $prompts.showRateAlert) {
                Button("Rate") {
                    prompts.requestRate()
                }
                Button("Not now", role: .cancel) {
                    prompts.postponeRate()
                }
            } message: {
                Text("Give us 5 stars if you like it!")
            }
            .sheet(item: $prompts.shareItem) { item in
                ShareSheet(url: item.url) {
                    prompts.markShareCompleted()
                }
            }
    }
}

// MARK: - ShareSheet helper
struct ShareSheet: UIViewControllerRepresentable {

    let url: URL
    let completion: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            if completed {
                completion?()
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Convenience
extension View {
    func inAppPrompts() -> some View {
        modifier(InAppPromptsViewModifier())
    }
}
