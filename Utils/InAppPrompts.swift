//
//  InAppPrompts.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 4/1/26.
//

import SwiftUI
import StoreKit

/// InAppPrompts manages in-app notifications for sharing and rating the app using SwiftUI-native components
@MainActor
final class InAppPrompts: ObservableObject {
    static let shared = InAppPrompts()
    private let appLogger = AppLogger(category: "PROMPTS")
    
    // MARK: - UserDefaults keys
    fileprivate enum Keys { // Cambiado a fileprivate para que sea accesible desde closures
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
    
    // MARK: - Session flags
    private var hasPresentedPromptThisSession = false
    
    // MARK: - Published state for SwiftUI
    @Published var showRateAlert = false
    @Published var shareItem: ShareItem? // Envolvemos URL en un Identifiable struct
    
    /// Wrapper for ShareSheet item
    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    private init() {}
    
    /// Call this on app launch
    func checkPrompts() {
        guard !hasPresentedPromptThisSession else { return }
        
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: Keys.appLaunches) + 1
        defaults.set(launches, forKey: Keys.appLaunches)
        
        appLogger.debug("App Launch Count: \(launches)")
        
        // MARK: Rate Prompt Logic
        let rateShown = defaults.bool(forKey: Keys.hasShownRatePrompt)
        let ratePostponed = defaults.integer(forKey: Keys.postponedRatePrompt)
        
        if !rateShown && ((ratePostponed == 0 && launches == rateThreshold) ||
                          (ratePostponed > 0 && launches - ratePostponed >= reminderDelay)) {
            hasPresentedPromptThisSession = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                showRateAlert = true
            }
            return
        }
        
        // MARK: Share Prompt Logic
        let shareShown = defaults.bool(forKey: Keys.hasShownSharePrompt)
        let sharePostponed = defaults.integer(forKey: Keys.postponedSharePrompt)
        
        if !shareShown && ((sharePostponed == 0 && launches == shareThreshold) ||
                           (sharePostponed > 0 && launches - sharePostponed >= reminderDelay)) {
            hasPresentedPromptThisSession = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let url = URL(string: "https://apps.apple.com/app/id6755367558") { // Replace with your App Store ID
                    shareItem = ShareItem(url: url)
                }
            }
        }
    }
    
    // MARK: - Rate action
    func requestRate() {
        let defaults = UserDefaults.standard
        Task { @MainActor in
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                AppStore.requestReview(in: scene)
            }
            defaults.set(true, forKey: Keys.hasShownRatePrompt)
        }
    }
    
    // MARK: - Share action
    func postponeShare() {
        let defaults = UserDefaults.standard
        defaults.set(UserDefaults.standard.integer(forKey: Keys.appLaunches), forKey: Keys.postponedSharePrompt)
    }
    
    func postponeRate() {
        let defaults = UserDefaults.standard
        defaults.set(UserDefaults.standard.integer(forKey: Keys.appLaunches), forKey: Keys.postponedRatePrompt)
    }
}

// MARK: - SwiftUI View Modifier to handle alerts
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
            .sheet(item: $prompts.shareItem) { shareItem in
                ShareSheet(url: shareItem.url) {
                    // Mark as shown after share sheet completes
                    UserDefaults.standard.set(true, forKey: InAppPrompts.Keys.hasShownSharePrompt)
                }
            }
    }
}

// MARK: - Helper for ShareSheet in SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Extension for easy usage
extension View {
    func inAppPrompts() -> some View {
        self.modifier(InAppPromptsViewModifier())
    }
}
