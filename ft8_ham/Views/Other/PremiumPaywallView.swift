//
//  PremiumPaywallView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 02/04/26.
//

import StoreKit
import SwiftUI

/// Typed source for paywall analytics. Use `.feature` when a specific locked
/// feature triggered the paywall; use `.screen` for navigation-level triggers.
enum PaywallSource {
    case feature(PremiumFeature)
    case screen(String)

    var analyticsValue: String {
        switch self {
        case .feature(let f): return f.analyticsSource
        case .screen(let s): return s
        }
    }
}

/// Premium paywall modal view
struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var premiumManager: PremiumManager
    @ObservedObject private var flags = FeatureFlagManager.shared

    let source: PaywallSource

    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPurchaseSuccess = false
    @State private var showRestoreSuccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        headerView
                        featuresView

                        if let product = premiumManager.premiumProduct {
                            purchaseSection(product: product)
                        } else if premiumManager.productLoadState == .failed {
                            loadFailedSection
                        } else {
                            ProgressView("Loading...")
                                .frame(height: 100)
                        }

                        restoreButton
                        donorNote
                        disclaimerView
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("FT Ham Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("paywall_close")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("🎉 Welcome to Premium!", isPresented: $showPurchaseSuccess) {
                Button("Let's Go") { dismiss() }
            } message: {
                Text("All premium features are now unlocked. Thank you for your support!")
            }
            .alert("✅ Restored Successfully", isPresented: $showRestoreSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your premium purchase has been restored.")
            }
        }
        .task {
            await premiumManager.fetchPremiumProduct()
        }
        .onAppear {
            AnalyticsManager.shared.logPremiumPaywallShown(source: source.analyticsValue)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white, .green)

            Text("Unlock Premium Features")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                Text("One payment. Forever")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("For all your devices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Features

    private var featuresView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(PaywallBenefit.visible { flags.isEnabled($0) }) { benefit in
                FeatureRow(
                    icon: benefit.icon,
                    iconColor: benefit.color,
                    title: benefit.title,
                    description: benefit.summary
                )
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Purchase Section

    private func purchaseSection(product: Product) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(product.displayPrice)
                    .font(.system(size: 48, weight: .bold))

                Text("One-time payment • No subscription")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)

            Button {
                Task { await handlePurchase() }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "lock.open.fill")
                        Text("Unlock Premium Now")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(isPurchasing || isRestoring)
        }
        .padding(.horizontal)
    }

    // MARK: - Load Failure

    /// Shown when the App Store does not return the premium product, so the
    /// paywall never sits on an endless spinner.
    private var loadFailedSection: some View {
        VStack(spacing: 12) {
            Text("Couldn't load the price. Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await premiumManager.fetchPremiumProduct() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .accessibilityIdentifier("paywall_retry")
        }
        .frame(minHeight: 100)
        .padding(.horizontal)
    }

    // MARK: - Restore Button

    /// Secondary to the purchase button but still a full-width button, so
    /// users who already bought premium find it without hunting.
    private var restoreButton: some View {
        Button {
            Task { await handleRestore() }
        } label: {
            HStack {
                if isRestoring {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("Restore Purchase")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.green)
        .controlSize(.large)
        .padding(.horizontal)
        .disabled(isPurchasing || isRestoring)
        .accessibilityIdentifier("paywall_restore")
    }

    // MARK: - Past Donors

    /// Tips never unlock premium, and 1.2.x tips cannot be seen by the app, so
    /// past donors ask by email and get an offer code instead.
    private var donorNote: some View {
        VStack(spacing: 6) {
            Text("💛 Thank You, Donors")
                .font(.subheadline.bold())
            // A String, not a key, so the address is not turned into a second link.
            Text(String(localized: "If you donated in an earlier version, write to ftham@turrion.dev and we will send you a code for free Premium."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(PaywallDonorNote.email, destination: PaywallDonorNote.mailURL)
                .font(.footnote.weight(.semibold))
                .tint(.green)
                .accessibilityIdentifier("paywall_donor_email")
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding()
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Disclaimer

    private var disclaimerView: some View {
        VStack(spacing: 6) {
            Text("Payment charged to your Apple ID")
            Text("Purchase is tied to your Apple ID across all devices")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.bottom, 20)
    }
    
    // MARK: - Actions
    
    private func handlePurchase() async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            try await premiumManager.purchasePremium()
            showPurchaseSuccess = true
        } catch PremiumError.userCancelled {
            // User cancelled - no error needed
            return
        } catch PremiumError.pending {
            errorMessage = "Your purchase is awaiting approval. You'll get access once it's approved."
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func handleRestore() async {
        isRestoring = true
        defer { isRestoring = false }
        
        do {
            try await premiumManager.restorePurchases()
            showRestoreSuccess = true
        } catch StoreKitError.userCancelled {
            // User cancelled the Apple Account sign-in - no error needed
            return
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Benefits

/// A paywall row grouping related premium features, so the sheet lists a few
/// benefits instead of one row per feature. Every `PremiumFeature` belongs to
/// exactly one group.
struct PaywallBenefit: Identifiable {
    let title: String
    let icon: String
    let color: Color
    var features: [PremiumFeature]
    /// Perks that are not gated features, listed after the feature names.
    var extras: [String] = []

    var id: String { title }

    /// Feature names and extras as a localized list, e.g. "A, B and C".
    var summary: String {
        (features.map(\.displayName) + extras).formatted(.list(type: .and))
    }

    static let all: [PaywallBenefit] = [
        PaywallBenefit(
            title: String(localized: "Radio Control"),
            icon: "slider.horizontal.3",
            color: .orange,
            features: [.catControl, .bandHopping]
        ),
        PaywallBenefit(
            title: String(localized: "Logbook Sync"),
            icon: "arrow.triangle.2.circlepath",
            color: .teal,
            features: [.qrzLogbook, .lotwSync, .eqslSync, .iCloudSync]
        ),
        PaywallBenefit(
            title: String(localized: "Insights"),
            icon: "chart.bar.fill",
            color: .purple,
            features: [.pskReporter, .statistics, .presence]
        ),
        PaywallBenefit(
            title: String(localized: "Extras"),
            icon: "sparkles",
            color: .pink,
            features: [.iPadDashboard]
        ),
    ]

    /// The benefits a buyer can actually reach: features whose remote flag is
    /// off are left out, and a benefit with nothing left is dropped.
    static func visible(isEnabled: (FeatureFlag) -> Bool) -> [PaywallBenefit] {
        all.compactMap { benefit in
            var filtered = benefit
            filtered.features = benefit.features.filter { feature in
                feature.featureFlag.map(isEnabled) ?? true
            }
            return filtered.features.isEmpty && filtered.extras.isEmpty ? nil : filtered
        }
    }
}

// MARK: - Past Donors

/// Where past donors ask for their free Premium offer code.
enum PaywallDonorNote {
    static let email = "ftham@turrion.dev"
    static let subject = "Premium code for a past donation"

    static var mailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url!
    }
}

// MARK: - Feature Row Component

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 35)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Premium Paywall") {
    PremiumPaywallView(source: .screen("preview"))
        .environmentObject(PremiumManager.shared)
}
