//
//  InAppPrompts.swift
//  ft_ham
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
        static let donationQSOCount = "donationQSOCount"
        static let donationADIFCount = "donationADIFCount"
        static let donationTXCount = "donationTXCount"
        static let donationLastPromptLaunch = "donationLastPromptLaunch"
    }

    // MARK: - Thresholds
    private let shareThreshold = 6
    private let rateThreshold = 4
    private let reminderDelay = 10
    private let donationQSOThreshold = 10
    private let donationADIFThreshold = 2
    private let donationTXThreshold = 20
    private let donationProbabilityPercent = 25
    private let donationCooldownLaunches = 20

    // MARK: - Session state
    private var hasPresentedPromptThisSession = false

    // MARK: - Published state for SwiftUI
    @Published var showRateAlert = false
    @Published var showPreShareAlert = false
    @Published var shareItem: ShareItem?
    @Published var showDonationAlert = false
    @Published var showDonationSheet = false

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
                await MainActor.run {
                    self.requestRate()
                }
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
                showPreShareAlert = true
            }
        }
    }

    // MARK: - Donation triggers
    func recordQSOLogged() {
        recordDonationTrigger(.qsoLogged)
    }

    func recordADIFExport() {
        recordDonationTrigger(.adifExport)
    }

    func recordTXStarted() {
        recordDonationTrigger(.txStarted)
    }

    private enum DonationTrigger {
        case qsoLogged
        case adifExport
        case txStarted
    }

    private func recordDonationTrigger(_ trigger: DonationTrigger) {
        guard !hasPresentedPromptThisSession else { return }
        guard !showRateAlert, shareItem == nil else { return }
        
        // Skip if user has already donated
        Task {
            let hasDonated = await ProductManager.hasMadeAnyPurchase()
            guard !hasDonated else {
                appLogger.debug("Donation prompt skipped - user has already donated")
                return
            }
            
            await processDonationTrigger(trigger)
        }
    }
    
    private func processDonationTrigger(_ trigger: DonationTrigger) async {
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: Keys.appLaunches)
        let lastPromptLaunch = defaults.integer(forKey: Keys.donationLastPromptLaunch)

        if launches - lastPromptLaunch < donationCooldownLaunches {
            return
        }

        let (countKey, threshold): (String, Int) = {
            switch trigger {
            case .qsoLogged:
                return (Keys.donationQSOCount, donationQSOThreshold)
            case .adifExport:
                return (Keys.donationADIFCount, donationADIFThreshold)
            case .txStarted:
                return (Keys.donationTXCount, donationTXThreshold)
            }
        }()

        let newCount = defaults.integer(forKey: countKey) + 1
        defaults.set(newCount, forKey: countKey)

        guard newCount >= threshold else { return }

        let roll = Int.random(in: 1...100)
        defaults.set(0, forKey: countKey)

        guard roll <= donationProbabilityPercent else {
            appLogger.debug("Donation prompt skipped (roll=\(roll))")
            return
        }

        hasPresentedPromptThisSession = true
        defaults.set(launches, forKey: Keys.donationLastPromptLaunch)

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run {
            showDonationAlert = true
        }
    }

    // MARK: - Rate actions
    func requestRate() {
        let defaults = UserDefaults.standard
        AnalyticsManager.shared.logRateConfirmed()

        if #available(iOS 16.0, *) {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                AppStore.requestReview(in: scene)
            }
        } else {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
            }
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
    func confirmLikesApp() {
        AnalyticsManager.shared.logSharePromptShown()
        if let url = URL(string: "https://apps.apple.com/app/id6755367558") {
            shareItem = ShareItem(url: url)
        }
    }
    
    func markShareCompleted() {
        AnalyticsManager.shared.logShareCompleted()
        UserDefaults.standard.set(true, forKey: Keys.hasShownSharePrompt)
    }

    func postponeShare() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Keys.appLaunches),
                     forKey: Keys.postponedSharePrompt)
    }

    // MARK: - Donation actions
    func openDonation() {
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: Keys.appLaunches)
        defaults.set(launches, forKey: Keys.donationLastPromptLaunch)
        showDonationAlert = false
        showDonationSheet = true
    }

    func postponeDonation() {
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: Keys.appLaunches)
        defaults.set(launches, forKey: Keys.donationLastPromptLaunch)
        showDonationAlert = false
    }
}

// MARK: - SwiftUI Modifier
struct InAppPromptsViewModifier: ViewModifier {

    @ObservedObject var prompts = InAppPrompts.shared

    func body(content: Content) -> some View {
        content
            .alert("Enjoying FT-Ham? ⭐️", isPresented: $prompts.showRateAlert) {
                Button("Rate") {
                    prompts.requestRate()
                }
                Button("Not now", role: .cancel) {
                    prompts.postponeRate()
                }
            } message: {
                Text("Please give us 5 stars if you like it. Your feedback helps us improve!")
            }
            .alert("Do you like FT-Ham? ❤️", isPresented: $prompts.showPreShareAlert) {
                Button("Yes!") {
                    prompts.confirmLikesApp()
                }
                Button("Not really", role: .cancel) {
                    prompts.postponeShare()
                }
            } message: {
                Text("Share it with your fellow hams and friends! 📣")
            }
            .alert("Do you like FT-Ham?", isPresented: $prompts.showPreShareAlert) {
                Button("Yes!") {
                    prompts.confirmLikesApp()
                }
                Button("Not really", role: .cancel) {
                    prompts.postponeShare()
                }
            } message: {
                Text("We'd love to hear your feedback!")
            }
            .alert("Do you like FT-Ham?", isPresented: $prompts.showPreShareAlert) {
                Button("Yes!") {
                    prompts.confirmLikesApp()
                }
                Button("Not really", role: .cancel) {
                    prompts.postponeShare()
                }
            } message: {
                Text("We'd love to hear your feedback!")
            }
            .sheet(item: $prompts.shareItem) { item in
                ShareSheet(url: item.url) {
                    prompts.markShareCompleted()
                }
            }
            .alert("Support FT HAM?", isPresented: $prompts.showDonationAlert) {
                Button("Support") {
                    prompts.openDonation()
                }
                Button("Not now", role: .cancel) {
                    prompts.postponeDonation()
                }
            } message: {
                Text("Optional tips help maintain the app. The app works the same without donating.")
            }
            .sheet(isPresented: $prompts.showDonationSheet) {
                NavigationStack {
                    SupportView()
                        .navigationTitle("Support FT HAM")
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
