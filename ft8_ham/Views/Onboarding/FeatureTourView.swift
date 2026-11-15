//
//  FeatureTourView.swift
//  ft_ham
//
//  The feature slides that used to open the onboarding. They are now an
//  optional tour, opened from Configuration > Tutorials.
//

import SwiftUI

struct FeatureTourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Slide: Identifiable {
        let id: Int
        let image: String
        let color: Color
        let title: LocalizedStringKey
        let lines: [(LocalizedStringKey, Bool)]
    }

    /// Each line is a text key and whether it is shown in bold.
    private let slides: [Slide] = [
        Slide(id: 0, image: "wave.3.right", color: .orange, title: "onb_title_rx",
              lines: [("onb_rx_ft8_explainer", true), ("onb_rx_text1", false), ("onb_rx_text2", false)]),
        Slide(id: 1, image: "waveform", color: .cyan, title: "onb_title_waterfall",
              lines: [("onb_waterfall_text1", false), ("onb_waterfall_text2", false)]),
        Slide(id: 2, image: "arrowshape.turn.up.left.fill", color: .mint, title: "onb_title_reply",
              lines: [("onb_reply_text1", false), ("onb_reply_text2", false)]),
        Slide(id: 3, image: "text.bubble.fill", color: .teal, title: "onb_title_views",
              lines: [("onb_views_condensed", true), ("onb_views_condensed_desc", false),
                      ("onb_views_separated", true), ("onb_views_separated_desc", false),
                      ("onb_views_vertical", true), ("onb_views_vertical_desc", false)]),
        Slide(id: 4, image: "map.fill", color: .purple, title: "onb_title_map",
              lines: [("onb_map_text1", false), ("onb_map_text2", false)]),
        Slide(id: 5, image: "paperplane.fill", color: .red, title: "onb_title_tx",
              lines: [("onb_tx_text1", false), ("onb_tx_text2", false)]),
        Slide(id: 6, image: "book.fill", color: .brown, title: "onb_title_logbook",
              lines: [("onb_logbook_text1", false), ("onb_logbook_text2", false), ("onb_logbook_text3", false)]),
        Slide(id: 7, image: "gearshape.fill", color: .purple, title: "onb_title_autosequencing",
              lines: [("onb_autosequencing_text1", false), ("onb_autosequencing_text2", false),
                      ("onb_autosequencing_text3", false)])
    ]

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(slides) { slide in
                    slideView(slide).tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle("onb_feature_tour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func slideView(_ slide: Slide) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: slide.image)
                    .font(.system(size: 80))
                    .foregroundStyle(slide.color)
                    .padding(.top, 32)
                    .accessibilityHidden(true)

                Text(slide.title)
                    .font(.largeTitle)
                    .bold()
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 8) {
                    ForEach(slide.lines.indices, id: \.self) { index in
                        let line = slide.lines[index]
                        Text(line.0).bold(line.1)
                    }
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 64)
        }
    }
}

#Preview {
    FeatureTourView()
}
