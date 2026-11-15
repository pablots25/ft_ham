//
//  OnboardingView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/12/25.
//

import SwiftUI
import CoreLocation
import AVFoundation

/// First-run onboarding in four button-driven steps: welcome and terms,
/// station, audio and ready. The full feature slides live in
/// `FeatureTourView`, reachable from Configuration > Tutorials.
struct OnboardingView: View {
    /// Called right before the onboarding marks itself complete, so the
    /// caller knows whether to start RX.
    var onFinish: (OnboardingExit) -> Void = { _ in }

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasCompletedInitialPermissionFlow") private var hasCompletedInitialPermissionFlow: Bool = false
    @AppStorage("hasAcceptedTerms") private var hasAcceptedTerms: Bool = false
    @State private var step: OnboardingStep = .welcome
    @StateObject private var locationRequester = LocationPermissionRequester()

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeStep(onContinue: acceptTermsAndAdvance)
                case .station:
                    OnboardingStationStep(locationRequester: locationRequester, onContinue: advance)
                case .audio:
                    OnboardingAudioStep(onContinue: advance)
                case .ready:
                    OnboardingReadyStep(onSetUpStation: { go(to: .station) }, onFinish: finish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                .combined(with: .opacity))
            .id(step)
        }
    }

    // MARK: - Header

    /// Back button and "Step 2 of 4". The welcome step has neither, since
    /// the terms must be accepted before going on.
    private var header: some View {
        HStack {
            if let previous = OnboardingStep(rawValue: step.rawValue - 1), step != .welcome {
                Button {
                    go(to: previous)
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
            }
            Spacer()
            Text("onb_step_progress \(step.number) \(OnboardingStep.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.updatesFrequently)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(minHeight: 44)
    }

    // MARK: - Navigation

    private func acceptTermsAndAdvance() {
        if !hasAcceptedTerms {
            AnalyticsManager.shared.grantAnalyticsConsent()
            AnalyticsManager.shared.logTermsAccepted()
            hasAcceptedTerms = true
        }
        advance()
    }

    private func advance() {
        guard let next = step.next else { return }
        go(to: next)
    }

    private func go(to target: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.3)) { step = target }
    }

    private func finish(_ exit: OnboardingExit) {
        onFinish(exit)
        AnalyticsManager.shared.logOnboardingCompleted()
        hasCompletedInitialPermissionFlow = true
        hasCompletedOnboarding = true
    }
}

// MARK: - Shared layout

/// Scrollable step body with its buttons pinned at the bottom, so large text
/// sizes never push the buttons off screen.
private struct OnboardingStepLayout<Content: View, Actions: View>: View {
    let image: String
    let color: Color
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: image)
                        .font(.system(size: 72))
                        .foregroundStyle(color)
                        .padding(.top, 24)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.largeTitle)
                        .bold()
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    content
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 12) {
                actions
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }
}

/// An SF Symbol and a sentence, used by the welcome and audio steps.
private struct OnboardingRow: View {
    let image: String
    let color: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: image)
                .foregroundStyle(color)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PrimaryButton: View {
    let title: LocalizedStringKey
    let color: Color
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView().controlSize(.small) }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .controlSize(.large)
        .disabled(isLoading)
    }
}

// MARK: - Step 1: Welcome

private struct OnboardingWelcomeStep: View {
    var onContinue: () -> Void

    @State private var showTermsSafari = false
    @State private var showPrivacySafari = false

    var body: some View {
        OnboardingStepLayout(image: "antenna.radiowaves.left.and.right", color: .blue, title: "onb_title_welcome") {
            Text("onb_welcome_text")
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                OnboardingRow(image: "waveform", color: .orange, text: "onb_highlight_decode")
                OnboardingRow(image: "arrowshape.turn.up.left.fill", color: .mint, text: "onb_highlight_reply")
                OnboardingRow(image: "book.fill", color: .brown, text: "onb_highlight_log")
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text("onb_terms_notice")
                    .foregroundStyle(.secondary)
                // Tinted like links, so they read as tappable.
                HStack(spacing: 16) {
                    Button("Terms of Use") { showTermsSafari = true }
                    Button("Privacy Policy") { showPrivacySafari = true }
                }
                Text("FT Ham collects anonymous usage statistics with Firebase Analytics to improve the app. You can turn this off in Configuration, under Legal & Licenses. Optional services such as QRZ, LoTW, eQSL and PSK Reporter only receive data after you turn them on.")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
        } actions: {
            PrimaryButton(title: "onb_get_started", color: .blue, action: onContinue)
        }
        .sheet(isPresented: $showTermsSafari) {
            SafariView(url: URL(string: "https://ftham.turrion.dev/terms")!)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPrivacySafari) {
            SafariView(url: URL(string: "https://ftham.turrion.dev/privacy")!)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Step 2: Station

/// Asks for the callsign and locator with the same fields and validation as
/// the Station settings screen. Both are optional here: the launch alert in
/// `ContentView` still points to Configuration when they are missing.
private struct OnboardingStationStep: View {
    @ObservedObject var locationRequester: LocationPermissionRequester
    var onContinue: () -> Void

    @AppStorage("callsign") private var callsign = ""
    @AppStorage("locator") private var locator = ""
    @AppStorage("stationCallsignIsElevenMeter") private var isElevenMeter = false
    @AppStorage(CompoundCallsign.freeTextOptInKey) private var isFreeText = false

    @State private var callsignText = ""
    @State private var locatorText = ""
    @State private var validCallsign = false
    @State private var validLocator = false
    @State private var isLocating = false
    @State private var locationFailed = false

    var body: some View {
        OnboardingStepLayout(image: "person.crop.circle.badge.checkmark", color: .indigo, title: "onb_title_station") {
            Text("onb_station_text2")
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                CallsignFieldView(
                    callsignText: $callsignText,
                    validCallsign: $validCallsign,
                    isElevenMeterEnabled: isElevenMeter,
                    isFreeTextEnabled: isFreeText,
                    onCommit: commitCallsign
                )

                Toggle(isOn: $isElevenMeter) {
                    Text("11 m / CB callsign")
                }
                .onChange(of: isElevenMeter) { _ in commitCallsign() }

                Toggle(isOn: $isFreeText) {
                    Text("Free-text callsign")
                }
                .onChange(of: isFreeText) { _ in commitCallsign() }

                LocatorFieldView(
                    locatorText: $locatorText,
                    validLocator: $validLocator,
                    onCommit: commitLocator
                )

                Button {
                    Task { await fillLocatorFromLocation() }
                } label: {
                    HStack(spacing: 8) {
                        if isLocating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text("onb_use_my_location")
                    }
                }
                .disabled(isLocating)

                if locationFailed {
                    Text("onb_location_failed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text("You can skip this and add them later in the Configuration tab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } actions: {
            PrimaryButton(title: "Continue", color: .indigo) {
                commitCallsign()
                commitLocator()
                onContinue()
            }
            Button("Not now", action: onContinue)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            callsignText = callsign
            locatorText = locator
            validCallsign = isValidStationCallsign(
                callsign, allowElevenMeter: isElevenMeter, allowFreeText: isFreeText
            )
            validLocator = isValidLocator(locator)
        }
        // Once location is allowed, the GPS auto locator can fill the stored
        // locator by itself. Show it while the field is still empty.
        .onChange(of: locator) { newValue in
            guard locatorText.isEmpty, isValidLocator(newValue) else { return }
            locatorText = newValue
            validLocator = true
        }
    }

    /// Stores the callsign when it passes the Station settings validation.
    private func commitCallsign() {
        let text = callsignText.uppercased()
        callsignText = text
        validCallsign = isValidStationCallsign(
            text, allowElevenMeter: isElevenMeter, allowFreeText: isFreeText
        )
        if validCallsign { callsign = text }
    }

    /// Stores the 4-character grid when valid, trimmed like Station settings.
    private func commitLocator() {
        var text = locatorText.uppercased()
        text.removeAll(where: { $0.isWhitespace })
        if text.count > 4 { text = String(text.prefix(4)) }
        locatorText = text
        validLocator = isValidLocator(text)
        if validLocator { locator = text }
    }

    @MainActor
    private func fillLocatorFromLocation() async {
        isLocating = true
        locationFailed = false
        defer { isLocating = false }

        guard let location = await locationRequester.requestCurrentLocation(),
              let grid = OnboardingStation.locator(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
              ) else {
            locationFailed = true
            return
        }
        locatorText = grid
        commitLocator()
    }
}

// MARK: - Step 3: Audio

/// What You Need, then the microphone permission.
private struct OnboardingAudioStep: View {
    var onContinue: () -> Void

    @State private var isRequesting = false

    var body: some View {
        OnboardingStepLayout(image: "cable.connector", color: .green, title: "onb_title_equipment") {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingRow(image: "radio", color: .green, text: "onb_equipment_radio")
                OnboardingRow(image: "cable.connector.horizontal", color: .green, text: "onb_equipment_interface")
                OnboardingRow(image: "mic.fill", color: .green, text: "onb_equipment_microphone")
                Text("onb_equipment_license")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                Text(InitialPermissionStep.microphone.bodyText)
                Text(InitialPermissionStep.microphone.impactText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        } actions: {
            PrimaryButton(title: "onb_allow_microphone", color: .green, isLoading: isRequesting) {
                Task { await requestMicrophoneAndContinue() }
            }
            Button("Not now", action: onContinue)
                .foregroundStyle(.secondary)
                .disabled(isRequesting)
        }
    }

    @MainActor
    private func requestMicrophoneAndContinue() async {
        isRequesting = true
        defer { isRequesting = false }
        if #available(iOS 17, *) {
            _ = await AVAudioApplication.requestRecordPermission()
        } else {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { _ in continuation.resume() }
            }
        }
        onContinue()
    }
}

// MARK: - Step 4: Ready

private struct OnboardingReadyStep: View {
    var onSetUpStation: () -> Void
    var onFinish: (OnboardingExit) -> Void

    @AppStorage("callsign") private var callsign = ""
    @AppStorage("locator") private var locator = ""

    private var stationReady: Bool {
        OnboardingStation.isReady(callsign: callsign, locator: locator)
    }

    var body: some View {
        OnboardingStepLayout(image: "checkmark.seal.fill", color: .green, title: "onb_finish_title") {
            Text(stationReady ? "onb_finish_text" : "onb_finish_station_missing")
                .multilineTextAlignment(.center)

            FirstRunChecklistView(isEmbedded: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            if stationReady {
                PrimaryButton(title: "onb_start_receiving", color: .green) { onFinish(.startReceiving) }
            } else {
                PrimaryButton(title: "onb_set_up_station", color: .indigo, action: onSetUpStation)
            }
            Button("onb_explore_first") { onFinish(.explore) }
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("OnboardingView") {
    OnboardingView()
}
