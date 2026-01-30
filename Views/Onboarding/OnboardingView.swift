//
//  OnboardingView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 9/12/25.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var currentPage = 0
    private let totalPages = 11

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
                    if currentPage < totalPages - 1 {
                        Button("Skip") {
                            hasCompletedOnboarding = true
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
        switch index {
        case 0:
            onboardingPage(image: "antenna.radiowaves.left.and.right", color: .blue, title: "onb_title_welcome") {
                Text("onb_welcome_text")
            }
        case 1:
            onboardingPage(image: "wave.3.right", color: .orange, title: "onb_title_rx") {
                VStack(spacing: 8) {
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
            onboardingPage(image: "person.crop.circle.badge.checkmark", color: .indigo, title: "onb_title_station") {
                VStack(spacing: 8) {
                    Text("onb_station_text1")
                    Text("onb_station_text2")
                }
            }
        case 8: // AutoSequencing
            onboardingPage(image: "gearshape.fill", color: .purple, title: "onb_title_autosequencing") {
                VStack(spacing: 8) {
                    Text("onb_autosequencing_text1")
                    Text("onb_autosequencing_text2")
                    Text("onb_autosequencing_text3")
                }
            }
        case 9: // Logbook
            onboardingPage(image: "book.fill", color: .brown, title: "onb_title_logbook") {
                VStack(spacing: 8) {
                    Text("onb_logbook_text1")
                    Text("onb_logbook_text2")
                    Text("onb_logbook_text3")
                }
            }
        case 10:
            finishPage()
        default:
            EmptyView()
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
                .symbolEffect(.bounce, options: .speed(0.05))
            
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
                .symbolEffect(.bounce)
            
            Text("onb_finish_title")
                .font(.largeTitle)
                .bold()
            
            Text("onb_finish_text")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
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
}

#Preview("OnboardingView") {
    OnboardingView()
}
