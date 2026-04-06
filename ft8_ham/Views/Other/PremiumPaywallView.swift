//
//  PremiumPaywallView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 02/04/26.
//

import StoreKit
import SwiftUI

/// Premium paywall modal view
struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var premiumManager: PremiumManager

    let source: String // Track where the paywall was shown from

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
                        } else {
                            ProgressView("Loading...")
                                .frame(height: 100)
                        }

                        restoreButton
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
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("🎉 Welcome to Premium!", isPresented: $showPurchaseSuccess) {
                Button("Let's Go!") { dismiss() }
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
            AnalyticsManager.shared.logPremiumPaywallShown(source: source)
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
            FeatureRow(
                icon: "rectangle.split.3x1",
                iconColor: .blue,
                title: "iPad Dashboard",
                description: "Multitask with a layout optimized for iPad"
            )
            FeatureRow(
                icon: "chart.bar.fill",
                iconColor: .purple,
                title: "PSK Reporter integration",
                description: "Check in real-time where your signals are being received by others"
            )
            FeatureRow(
                icon: "slider.horizontal.3",
                iconColor: .orange,
                title: "CAT Control",
                description: "Control your radio over the internet with CAT via UDP - No USB yet"
            )
            FeatureRow(
                icon: "envelope.circle.fill",
                iconColor: .blue,
                title: "Priority Support",
                description: "Direct email support for technical questions"
            )
            FeatureRow(
                icon: "sparkles",
                iconColor: .pink,
                title: "Future Features",
                description: "Get all upcoming premium features at no extra cost"
            )
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

    // MARK: - Restore Button

    private var restoreButton: some View {
        Button {
            Task { await handleRestore() }
        } label: {
            if isRestoring {
                ProgressView()
            } else {
                Text("Restore Purchase")
            }
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .disabled(isPurchasing || isRestoring)
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
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
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
    PremiumPaywallView(
        source: "preview"
    )
    .environmentObject(PremiumManager.shared)
}
