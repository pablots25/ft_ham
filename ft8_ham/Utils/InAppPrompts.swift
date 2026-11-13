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
    private let remoteConfig = RemoteConfigProvider()
    
    // MARK: - Cached Prompt Config
    private var promptConfig: PromptConfig { remoteConfig.getPromptConfig() }

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
        static let rateQSOCount = "rateQSOCount"
    }

    // MARK: - Rate Threshold (from Firebase JSON config)
    private var rateThreshold: Int { promptConfig.prompts.rate.threshold }
    private var isRatePromptEnabled: Bool { promptConfig.prompts.rate.enabled }

    // MARK: - Share Threshold (from Firebase JSON config)
    private var shareThreshold: Int { promptConfig.prompts.share.threshold }
    private var isSharePromptEnabled: Bool { promptConfig.prompts.share.enabled }

    // MARK: - Common Settings (from Firebase JSON config)
    private var promptProbabilityPercent: Int { promptConfig.prompts.common.probability }
    private var reminderDelay: Int { promptConfig.prompts.common.reminderDelay }

    // MARK: - Donation Settings (from Firebase JSON config)
    private var donationQSOThreshold: Int { promptConfig.prompts.donation.qsoThreshold }
    private var donationADIFThreshold: Int { promptConfig.prompts.donation.adifThreshold }
    private var donationTXThreshold: Int { promptConfig.prompts.donation.txThreshold }
    private var isDonationPromptEnabled: Bool { promptConfig.prompts.donation.enabled }
    private var donationProbabilityPercent: Int { promptConfig.prompts.common.donationProbability }
    private var donationCooldownLaunches: Int { promptConfig.prompts.common.donationCooldown }

    // MARK: - Session state
    private var hasPresentedPromptThisSession = false
    private var lastDonationTriggerSource = "unknown"

    // MARK: - Published state for SwiftUI
    @Published var showPreShareAlert = false
    @Published var shareItem: ShareItem?
    @Published var showDonationAlert = false
    @Published var shouldNavigateToDonations = false
    /// Milestone that is asking a free user about Premium (`premiumMoments`).
    @Published var premiumMomentAlert: PremiumMoment?
    /// Milestone whose "See Premium" opened the paywall.
    @Published var premiumMomentPaywall: PremiumMoment?

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
            isRatePromptEnabled &&
            !rateShown &&
            ((ratePostponed == 0 && launches == rateThreshold) ||
             (ratePostponed > 0 && launches - ratePostponed >= reminderDelay))

        if shouldShowRate {
            let roll = Int.random(in: 1...100)
            guard roll <= promptProbabilityPercent else {
                appLogger.debug("Rate prompt skipped (roll=\(roll))")
                return
            }

            hasPresentedPromptThisSession = true

            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self.requestRate(trigger: .launches)
                }
            }
            return
        }

        // MARK: - Share logic
        let shareShown = defaults.bool(forKey: Keys.hasShownSharePrompt)
        let sharePostponed = defaults.integer(forKey: Keys.postponedSharePrompt)

        let shouldShowShare =
            isSharePromptEnabled &&
            !shareShown &&
            ((sharePostponed == 0 && launches == shareThreshold) ||
             (sharePostponed > 0 && launches - sharePostponed >= reminderDelay))

        if shouldShowShare {
            let roll = Int.random(in: 1...100)
            guard roll <= promptProbabilityPercent else {
                appLogger.debug("Share prompt skipped (roll=\(roll))")
                return
            }

            hasPresentedPromptThisSession = true

            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                showPreShareAlert = true
            }
        }
    }

    // MARK: - Donation triggers
    func recordQSOLogged() {
        if requestReviewAfterQSOIfDue() { return }
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

        var analyticsSource: String {
            switch self {
            case .qsoLogged:
                return "qso"
            case .adifExport:
                return "adif"
            case .txStarted:
                return "tx"
            }
        }

        var premiumMoment: PremiumMoment {
            switch self {
            case .qsoLogged: return .qsoLogged
            case .adifExport: return .adifExport
            case .txStarted: return .txStarted
            }
        }
    }

    // MARK: - Rate after QSO

    /// Counts the logged QSO and, with `rateAfterQSO` on, asks for a rating
    /// once the threshold is reached. Returns whether it asked, so the same
    /// QSO does not also raise a milestone prompt.
    private func requestReviewAfterQSOIfDue() -> Bool {
        let defaults = UserDefaults.standard
        let qsoCount = defaults.integer(forKey: Keys.rateQSOCount) + 1
        defaults.set(qsoCount, forKey: Keys.rateQSOCount)

        guard PromptMomentPolicy.shouldRequestReviewAfterQSO(
            flagEnabled: FeatureFlagManager.shared.isEnabled(.rateAfterQSO),
            ratePromptEnabled: isRatePromptEnabled,
            alreadyRequested: defaults.bool(forKey: Keys.hasShownRatePrompt),
            presentedThisSession: hasPresentedPromptThisSession,
            qsoCount: qsoCount
        ) else { return false }

        appLogger.debug("Requesting review after QSO #\(qsoCount)")
        hasPresentedPromptThisSession = true
        Task {
            // Let the QSO confirmation settle before the system sheet.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            requestRate(trigger: .qso)
        }
        return true
    }

    private func recordDonationTrigger(_ trigger: DonationTrigger) {
        if FeatureFlagManager.shared.isEnabled(.premiumMoments) {
            recordPremiumMoment(trigger)
            return
        }
        guard isDonationPromptEnabled else { return }
        guard FeatureFlagManager.shared.isEnabled(.donationsEnabled) else {
            logDonationPromptSkipped(trigger: trigger, reason: "donations_disabled")
            return
        }
        guard !hasPresentedPromptThisSession else {
            logDonationPromptSkipped(trigger: trigger, reason: "prompt_presented_this_session")
            return
        }
        guard shareItem == nil else {
            logDonationPromptSkipped(trigger: trigger, reason: "share_sheet_active")
            return
        }
        
        // Skip if user has already donated
        Task {
            let hasDonated = await ProductManager.hasMadeAnyPurchase()
            guard !hasDonated else {
                appLogger.debug("Donation prompt skipped - user has already donated")
                logDonationPromptSkipped(trigger: trigger, reason: "already_donated")
                return
            }
            
            await processDonationTrigger(trigger)
        }
    }

    /// `premiumMoments` path: free users get a Premium prompt about the
    /// feature behind this milestone. Thresholds, cooldown and probability
    /// are the donation ones from the prompt config. Tip prompts stay off
    /// while the flag is on, since tips no longer unlock anything.
    private func recordPremiumMoment(_ trigger: DonationTrigger) {
        guard FeatureFlagManager.shared.isEnabled(.premiumMoments) else { return }
        if let reason = PromptMomentPolicy.premiumMomentSkipReason(
            isPremium: PremiumManager.shared.isPremiumUnlocked,
            presentedThisSession: hasPresentedPromptThisSession,
            shareSheetActive: shareItem != nil
        ) {
            logPremiumMomentSkipped(trigger: trigger, reason: reason)
            return
        }

        Task {
            await processDonationTrigger(trigger, offeringPremium: true)
        }
    }

    private func logPremiumMomentSkipped(
        trigger: DonationTrigger,
        reason: PremiumMomentSkipReason,
        roll: Int? = nil
    ) {
        AnalyticsManager.shared.logPremiumMomentSkipped(
            trigger.premiumMoment,
            reason: reason,
            appLaunches: UserDefaults.standard.integer(forKey: Keys.appLaunches),
            roll: roll
        )
    }

    private func logDonationPromptSkipped(trigger: DonationTrigger, reason: String, roll: Int? = nil) {
        let launches = UserDefaults.standard.integer(forKey: Keys.appLaunches)
        AnalyticsManager.shared.logDonationPromptSkipped(
            triggerSource: trigger.analyticsSource,
            reason: reason,
            appLaunches: launches,
            roll: roll
        )
    }
    
    private func processDonationTrigger(_ trigger: DonationTrigger, offeringPremium: Bool = false) async {
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: Keys.appLaunches)
        let lastPromptLaunch = defaults.integer(forKey: Keys.donationLastPromptLaunch)

        if launches - lastPromptLaunch < donationCooldownLaunches {
            if offeringPremium {
                logPremiumMomentSkipped(trigger: trigger, reason: .cooldown)
            } else {
                logDonationPromptSkipped(trigger: trigger, reason: "cooldown")
            }
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
            appLogger.debug("Milestone prompt skipped (roll=\(roll))")
            if offeringPremium {
                logPremiumMomentSkipped(trigger: trigger, reason: .probabilityRoll, roll: roll)
            } else {
                logDonationPromptSkipped(trigger: trigger, reason: "probability_roll", roll: roll)
            }
            return
        }

        hasPresentedPromptThisSession = true
        lastDonationTriggerSource = trigger.analyticsSource
        defaults.set(launches, forKey: Keys.donationLastPromptLaunch)

        if offeringPremium {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            AnalyticsManager.shared.logPremiumMomentShown(
                trigger.premiumMoment,
                appLaunches: launches
            )
            premiumMomentAlert = trigger.premiumMoment
            return
        }

        AnalyticsManager.shared.logDonationPromptShown(
            triggerSource: trigger.analyticsSource,
            appLaunches: launches
        )

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run {
            showDonationAlert = true
        }
    }

    // MARK: - Rate actions
    func requestRate(trigger: RatePromptTrigger) {
        let defaults = UserDefaults.standard
        AnalyticsManager.shared.logRatePromptShown(trigger: trigger)
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
        AnalyticsManager.shared.logSharePromptPostponed()
        defaults.set(defaults.integer(forKey: Keys.appLaunches),
                     forKey: Keys.postponedSharePrompt)
    }

    // MARK: - Donation actions
    func openDonation() {
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: Keys.appLaunches)
        defaults.set(launches, forKey: Keys.donationLastPromptLaunch)
        AnalyticsManager.shared.logDonationPromptConfirmed(
            triggerSource: lastDonationTriggerSource,
            appLaunches: launches
        )
        showDonationAlert = false
        shouldNavigateToDonations = true
    }

    // MARK: - Premium moment actions
    func openPremiumMoment(_ moment: PremiumMoment) {
        AnalyticsManager.shared.logPremiumMomentConfirmed(
            moment,
            appLaunches: UserDefaults.standard.integer(forKey: Keys.appLaunches)
        )
        premiumMomentAlert = nil
        premiumMomentPaywall = moment
    }

    func postponePremiumMoment(_ moment: PremiumMoment) {
        AnalyticsManager.shared.logPremiumMomentPostponed(
            moment,
            appLaunches: UserDefaults.standard.integer(forKey: Keys.appLaunches)
        )
        premiumMomentAlert = nil
    }

    func postponeDonation() {
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: Keys.appLaunches)
        AnalyticsManager.shared.logDonationPromptPostponed(
            triggerSource: lastDonationTriggerSource,
            appLaunches: launches
        )
        defaults.set(launches, forKey: Keys.donationLastPromptLaunch)
        showDonationAlert = false
    }
}

// MARK: - SwiftUI Modifier
struct InAppPromptsViewModifier: ViewModifier {

    @StateObject var prompts = InAppPrompts.shared

    func body(content: Content) -> some View {
        content
            // MARK: - Rate Prompt (goes directly to App Store, no UI alert)
            // Triggered in checkPrompts() via requestRate()
            
            // MARK: - Share Prompt (second priority)
            .alert("Do you like FT Ham? ❤️", isPresented: $prompts.showPreShareAlert) {
                Button("Yes!") {
                    prompts.confirmLikesApp()
                }
                Button("Not really", role: .cancel) {
                    prompts.postponeShare()
                }
            } message: {
                Text("Share it with your fellow hams and friends! 📣")
            }
            .sheet(item: $prompts.shareItem) { item in
                ShareSheet(url: item.url) {
                    prompts.markShareCompleted()
                }
            }
            
            // MARK: - Donation Prompt (third priority)
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
            // Note: Donation navigation is handled by ContentView switching to Configuration tab

            // MARK: - Premium moment (replaces the tip prompt with `premiumMoments`)
            .alert(
                prompts.premiumMomentAlert?.title ?? "",
                isPresented: Binding(
                    get: { prompts.premiumMomentAlert != nil },
                    set: { if !$0 { prompts.premiumMomentAlert = nil } }
                ),
                presenting: prompts.premiumMomentAlert
            ) { moment in
                Button("See Premium") {
                    prompts.openPremiumMoment(moment)
                }
                Button("Not now", role: .cancel) {
                    prompts.postponePremiumMoment(moment)
                }
            } message: { moment in
                Text(moment.message)
            }
            .sheet(item: $prompts.premiumMomentPaywall) { moment in
                // This modifier sits outside the app's environmentObject
                // chain, so the paywall gets the manager explicitly.
                PremiumPaywallView(source: moment.paywallSource)
                    .environmentObject(PremiumManager.shared)
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
