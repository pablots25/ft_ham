//
//  OnboardingView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/12/25.
//

import SwiftUI
import CoreLocation
import UserNotifications
import AVFoundation

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasCompletedInitialPermissionFlow") private var hasCompletedInitialPermissionFlow: Bool = false
    @AppStorage("hasAcceptedTerms") private var hasAcceptedTerms: Bool = false
    @State private var currentPage = 0
    @StateObject private var locationRequester = LocationPermissionRequester()
    @State private var permissionInProgress = false
    @State private var showTermsSafari = false
    @State private var showPrivacySafari = false
    
    private let contentPageCount = 9
    // After content pages: 1 terms page + 1 station page + permission pages + 1 finish page
    private var permissionSteps: [InitialPermissionStep] {
        [.location, .notifications, .microphone]
    }
    
    private var termsPageIndex: Int { contentPageCount }
    private var stationPageIndex: Int { contentPageCount + 1 }
    private var firstPermissionPageIndex: Int { stationPageIndex + 1 }
    private var finishPageIndex: Int { firstPermissionPageIndex + permissionSteps.count }
    private var totalPages: Int { finishPageIndex + 1 }
    
    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                ForEach(0..<totalPages, id: \.self) { index in
                    pageContent(for: index)
                        .tag(index)
                        .padding(.top, 50)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            
            VStack {
                HStack {
                    Spacer()
                    if currentPage < contentPageCount {
                        Button("Skip") {
                            withAnimation { currentPage = contentPageCount }
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Page Router
    @ViewBuilder
    private func pageContent(for index: Int) -> some View {
        if index < contentPageCount {
            contentPage(for: index)
        } else if index == termsPageIndex {
            termsPage()
        } else if index == stationPageIndex {
            OnboardingStationStep(onContinue: advancePage)
        } else if index < finishPageIndex {
            permissionPage(for: permissionSteps[index - firstPermissionPageIndex])
        } else {
            finishPage()
        }
    }
    
    @ViewBuilder
    private func contentPage(for index: Int) -> some View {
        switch index {
        case 0:
            onboardingPage(image: "antenna.radiowaves.left.and.right", color: .blue, title: "onb_title_welcome") {
                Text("onb_welcome_text")
            }
        case 1:
            onboardingPage(image: "wave.3.right", color: .orange, title: "onb_title_rx") {
                VStack(spacing: 8) {
                    Text("onb_rx_ft8_explainer")
                        .bold()
                    Text("onb_rx_text1")
                    Text("onb_rx_text2")
                }
            }
        case 2:
            onboardingPage(image: "waveform", color: .cyan, title: "onb_title_waterfall") {
                VStack(spacing: 8) {
                    Text("onb_waterfall_text1")
                    Text("onb_waterfall_text2")
                }
            }
        case 3:
            onboardingPage(image: "arrowshape.turn.up.left.fill", color: .mint, title: "onb_title_reply") {
                VStack(spacing: 8) {
                    Text("onb_reply_text1")
                    Text("onb_reply_text2")
                }
            }
        case 4:
            onboardingPage(image: "text.bubble.fill", color: .teal, title: "onb_title_views") {
                VStack(spacing: 8) {
                    Text("onb_views_condensed").bold()
                    Text("onb_views_condensed_desc")
                    Text("onb_views_separated").bold()
                    Text("onb_views_separated_desc")
                    Text("onb_views_vertical").bold()
                    Text("onb_views_vertical_desc")
                }
            }
        case 5:
            onboardingPage(image: "map.fill", color: .purple, title: "onb_title_map") {
                VStack(spacing: 8) {
                    Text("onb_map_text1")
                    Text("onb_map_text2")
                }
            }
        case 6:
            onboardingPage(image: "paperplane.fill", color: .red, title: "onb_title_tx") {
                VStack(spacing: 8) {
                    Text("onb_tx_text1")
                    Text("onb_tx_text2")
                }
            }
        case 7:
            onboardingPage(image: "book.fill", color: .brown, title: "onb_title_logbook") {
                VStack(spacing: 8) {
                    Text("onb_logbook_text1")
                    Text("onb_logbook_text2")
                    Text("onb_logbook_text3")
                }
            }
        case 8:
            onboardingPage(image: "gearshape.fill", color: .purple, title: "onb_title_autosequencing") {
                VStack(spacing: 8) {
                    Text("onb_autosequencing_text1")
                    Text("onb_autosequencing_text2")
                    Text("onb_autosequencing_text3")
                }
            }
        default:
            EmptyView()
        }
    }
    
    // MARK: - Terms Page
    private func termsPage() -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.plaintext.fill")
                .font(.system(size: 100))
                .foregroundStyle(.blue)

            Text("Terms & Privacy")
                .font(.largeTitle)
                .bold()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("By using FT Ham, you agree to the Terms of Use and End-User License Agreement (EULA).")
                        .multilineTextAlignment(.leading)

                    Text("Please review the full documents:")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Terms of Use") { showTermsSafari = true }
                        Button("Privacy Policy") { showPrivacySafari = true }
                    }
                    .foregroundStyle(.blue)
                    .sheet(isPresented: $showTermsSafari) {
                        SafariView(url: URL(string: "https://ftham.turrion.dev/terms")!)
                            .ignoresSafeArea()
                    }
                    .sheet(isPresented: $showPrivacySafari) {
                        SafariView(url: URL(string: "https://ftham.turrion.dev/privacy")!)
                            .ignoresSafeArea()
                    }

                    Divider()

                    Text("Anonymous usage metrics may be collected via Firebase Analytics to improve the app. No personally identifiable information (PII) is collected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                acceptTermsAndAdvance()
            } label: {
                Text("I Accept")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    private func acceptTermsAndAdvance() {
        if !hasAcceptedTerms {
            AnalyticsManager.shared.grantAnalyticsConsent()
            AnalyticsManager.shared.logTermsAccepted()
            hasAcceptedTerms = true
        }
        advancePage()
    }

    // MARK: - Permission Pages
    //
    // These pages explain WHY the permission is needed.
    // Tapping "Continue" fires the real iOS system permission dialog.
    // Tapping "Not now" skips the OS dialog and advances without requesting.
    @ViewBuilder
    private func permissionPage(for step: InitialPermissionStep) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: step.iconName)
                .font(.system(size: 100))
                .foregroundStyle(step.pageColor)
            
            Text(step.title)
                .font(.largeTitle)
                .bold()
            
            VStack(spacing: 10) {
                Text(step.bodyText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Text(step.impactText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                // Tapping "Continue" shows the iOS system permission dialog.
                Button {
                    Task { @MainActor in
                        await requestAndAdvance(step: step)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if permissionInProgress {
                            ProgressView().controlSize(.small)
                        }
                        Text("Continue")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(step.pageColor)
                .controlSize(.large)
                .disabled(permissionInProgress)
                
                // "Not now" skips the OS dialog for this step.
                Button("Not now") {
                    advancePage()
                }
                .foregroundStyle(.secondary)
                .disabled(permissionInProgress)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
    
    // MARK: - Generic UI Components
    private func onboardingPage<Content: View>(
        image: String,
        color: Color,
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: image)
                .font(.system(size: 100))
                .foregroundStyle(color)
            
            Text(title)
                .font(.largeTitle)
                .bold()
            
            content()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            Text("onb_slide_continue")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 60)
        }
    }
    
    private func finishPage() -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 100))
                .foregroundStyle(.green)
            
            Text("onb_finish_title")
                .font(.largeTitle)
                .bold()
            
            Text("onb_finish_text")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                // Accept terms if the user swiped past the terms page
                if !hasAcceptedTerms {
                    AnalyticsManager.shared.grantAnalyticsConsent()
                    AnalyticsManager.shared.logTermsAccepted()
                    hasAcceptedTerms = true
                }
                AnalyticsManager.shared.logOnboardingCompleted()
                hasCompletedInitialPermissionFlow = true
                hasCompletedOnboarding = true
            } label: {
                Text("onb_finish_button")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - Permission request helpers
    
    @MainActor
    private func requestAndAdvance(step: InitialPermissionStep) async {
        permissionInProgress = true
        defer { permissionInProgress = false }
        
        switch step {
        case .location:
            _ = await locationRequester.requestWhenInUseAuthorization()
        case .notifications:
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        case .microphone:
            if #available(iOS 17, *) {
                _ = await AVAudioApplication.requestRecordPermission()
            } else {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    AVAudioSession.sharedInstance().requestRecordPermission { _ in c.resume() }
                }
            }
        }
        
        advancePage()
    }
    
    private func advancePage() {
        withAnimation {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }
}

// MARK: - Station Step

/// Asks for the callsign and locator with the same fields and validation as
/// the Station settings screen. Both are optional here: the launch alert in
/// `ContentView` still points to Configuration when they are missing.
private struct OnboardingStationStep: View {
    var onContinue: () -> Void

    @AppStorage("callsign") private var callsign = ""
    @AppStorage("locator") private var locator = ""
    @AppStorage("stationCallsignIsElevenMeter") private var isElevenMeter = false

    @State private var callsignText = ""
    @State private var locatorText = ""
    @State private var validCallsign = false
    @State private var validLocator = false

    var body: some View {
        VStack(spacing: 24) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 100))
                        .foregroundStyle(.indigo)
                        .padding(.top, 40)

                    Text("onb_title_station")
                        .font(.largeTitle)
                        .bold()

                    Text("onb_station_text2")
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 16) {
                        CallsignFieldView(
                            callsignText: $callsignText,
                            validCallsign: $validCallsign,
                            isElevenMeterEnabled: isElevenMeter,
                            onCommit: commitCallsign
                        )

                        Toggle(isOn: $isElevenMeter) {
                            Text("11 m / CB callsign")
                        }
                        .onChange(of: isElevenMeter) { _ in commitCallsign() }

                        LocatorFieldView(
                            locatorText: $locatorText,
                            validLocator: $validLocator,
                            onCommit: commitLocator
                        )
                    }

                    Text("You can skip this and add them later in the Configuration tab.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 12) {
                Button {
                    commitCallsign()
                    commitLocator()
                    onContinue()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)

                Button("Not now") {
                    onContinue()
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .onAppear {
            callsignText = callsign
            locatorText = locator
            validCallsign = isValidStationCallsign(callsign, allowElevenMeter: isElevenMeter)
            validLocator = isValidLocator(locator)
        }
    }

    /// Stores the callsign when it passes the Station settings validation.
    private func commitCallsign() {
        let text = callsignText.uppercased()
        callsignText = text
        validCallsign = isValidStationCallsign(text, allowElevenMeter: isElevenMeter)
        if validCallsign { callsign = text }
    }

    /// Stores the 4-character grid when valid, trimmed like Station settings.
    private func commitLocator() {
        var text = locatorText.uppercased()
        text.removeAll(where: { $0.isWhitespace })
        if text.count > 4 { text = String(text.prefix(4)) }
        locatorText = text
        if isValidLocator(text) { locator = text }
    }
}

#Preview("OnboardingView") {
    OnboardingView()
}
