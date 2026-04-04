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
import AppTrackingTransparency

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasCompletedInitialPermissionFlow") private var hasCompletedInitialPermissionFlow: Bool = false
    @State private var currentPage = 0
    @StateObject private var locationRequester = LocationPermissionRequester()
    @State private var permissionInProgress = false
    
    private let contentPageCount = 11
    
    private var permissionSteps: [InitialPermissionStep] {
        var steps: [InitialPermissionStep] = [.location, .notifications, .microphone]
        if let desc = Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription") as? String,
           !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            steps.append(.tracking)
        }
        return steps
    }
    
    private var finishPageIndex: Int { contentPageCount + permissionSteps.count }
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
        } else if index < finishPageIndex {
            permissionPage(for: permissionSteps[index - contentPageCount])
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
        case 9:
            
            onboardingPage(image: "person.crop.circle.badge.checkmark", color: .indigo, title: "onb_title_station") {
                VStack(spacing: 8) {
                    Text("onb_station_text1")
                    Text("onb_station_text2")
                }
            }
        case 10:
            onboardingPage(
                image: "play.circle.fill",
                color: .orange,
                title: "onb_gstarted_title"
            ) {
                FirstRunChecklistView(isEmbedded: true)
                    .padding(.top, 4)
            }
        default:
            EmptyView()
        }
    }
    
    // MARK: - Permission Pages
    //
    // These pages explain WHY the permission is needed.
    // Tapping "Continue" fires the real iOS system permission dialog.
    // Tapping "Not Now" skips the OS dialog and advances without requesting.
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
                
                // "Not Now" skips the OS dialog for this step.
                Button("Not Now") {
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
        case .tracking:
            guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { break }
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        
        advancePage()
    }
    
    private func advancePage() {
        withAnimation {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }
}

#Preview("OnboardingView") {
    OnboardingView()
}
