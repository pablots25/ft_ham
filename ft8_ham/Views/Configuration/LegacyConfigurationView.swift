//
//  LegacyConfigurationView.swift
//  ft_ham
//
//  Created by GitHub Copilot on 04/04/26.
//

import SwiftUI

struct LegacyConfigurationView: View {
	@EnvironmentObject private var viewModel: FT8ViewModel
	@EnvironmentObject private var premiumManager: PremiumManager
	@Binding var shouldScrollToDonations: Bool

	@State private var showHelp = false
	@State private var showSupport = false
	@State private var showPremium = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 28) {
				section("Station") {
					StationSettingsContent()
				}

				section("Radio") {
					RadioSettingsContent()
				}

				section("Behavior") {
					BehaviorSettingsContent()
				}

				section("Interface") {
					InterfaceSettingsContent()
				}

				#if canImport(FTHamPremium)
				section("CAT Control") {
					if premiumManager.isPremiumUnlocked {
						NavigationLink {
							CatSettingsView(initialFrequencyMHz: viewModel.catDialFrequencyMHz)
								.padding(.horizontal)
						} label: {
							Label("Open CAT settings", systemImage: "dot.radiowaves.left.and.right")
						}
					} else {
						Button {
							showPremium = true
						} label: {
							HStack {
								Label("Open CAT settings", systemImage: "dot.radiowaves.left.and.right")
								Spacer()
								Image(systemName: "lock.fill")
									.font(.caption)
									.foregroundStyle(.tertiary)
							}
						}
						.foregroundStyle(.secondary)
					}
				}
				#endif

				#if DEBUG
				section("Debug") {
					NavigationLink {
						DebugSettingsView()
							.padding(.horizontal)
					} label: {
						Label("Toggles", systemImage: "ladybug")
					}

					Button {
						showSupport = true
					} label: {
						Label("Support FT HAM", systemImage: "heart")
					}
				}
				#endif

				section("Support") {
					Button {
						showHelp = true
					} label: {
						Label("Getting Started", systemImage: "book")
					}

					Button {
						showPremium = true
					} label: {
						Label("Become Premium", systemImage: "star")
					}

					Button {
						showSupport = true
					} label: {
						Label("Support FT HAM", systemImage: "heart")
					}

					Button {
						if let url = URL(string: "mailto:ftham@turrion.dev?subject=FT8%20Ham%20App%20Feedback") {
							UIApplication.shared.open(url)
						}
					} label: {
						Label("Send Feedback", systemImage: "envelope")
					}
				}

				section("Legal") {
					NavigationLink {
						LegalAndPrivacyView()
							.padding(.horizontal)
					} label: {
						Label("Legal & Licenses", systemImage: "hand.raised")
					}
				}

				versionFooter
			}
			.padding(.horizontal)
			.padding(.bottom, 20)
		}
		.navigationTitle("Configuration")
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $showSupport) {
			NavigationStack {
				SupportView()
					.navigationTitle("Support FT HAM")
					.navigationBarTitleDisplayMode(.inline)
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button("Done") { showSupport = false }
						}
					}
			}
			.presentationDetents([.medium])
		}
		.sheet(isPresented: $showPremium) {
			NavigationStack {
				PremiumPaywallView(source: "configuration")
					.navigationTitle("Become Premium")
					.navigationBarTitleDisplayMode(.inline)
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button("Done") { showPremium = false }
						}
					}
			}
			.presentationDetents([.large])
		}
		.sheet(isPresented: $showHelp) {
			SafariView(url: URL(string: "https://ftham.turrion.dev/#getting-started")!)
				.ignoresSafeArea()
		}
		.onChange(of: shouldScrollToDonations) { shouldScroll in
			if shouldScroll {
				showSupport = true
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					shouldScrollToDonations = false
				}
			}
		}
	}

	private var versionFooter: some View {
		VStack(spacing: 4) {
			if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
			   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
				Text(String(format: String(localized: "Version %@ (Build %@)"), version, build))
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity)
		.multilineTextAlignment(.center)
		.padding(.top, 8)
	}

	private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(title)
				.font(.title3.weight(.semibold))
			content()
		}
	}
}

#Preview {
	NavigationStack {
		LegacyConfigurationView(shouldScrollToDonations: .constant(false))
			.environmentObject(FT8ViewModel(
				txMessages: PreviewMocks.txMessages,
				rxMessages: PreviewMocks.rxMessages
			))
			.environmentObject(FeatureFlagManager.shared)
	}
}
