//
//  SeparatedTransmissionDashboardView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//

import SwiftUI

/// Consolidated dashboard view combining all transmission controls and messages
/// Designed for use within the iPad Dashboard layout
struct SeparatedTransmissionDashboardView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @AppStorage("rxFilterModeSeparated") private var filterMode: Int = 0
    @State private var showLegend: Bool = false

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            Group {
                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
            .padding(LayoutConstants.standardPadding)
        }
    }

    private var portraitLayout: some View {
        VStack(spacing: LayoutConstants.standardSpacing) {
            TransmissionButtonsBar()

            messagesRow

            footerRow
        }
    }

    private var landscapeLayout: some View {
        VStack(spacing: LayoutConstants.standardSpacing) {
            TransmissionButtonsBar()
            
            messagesRow
            
            HStack(spacing: LayoutConstants.standardSpacing) {
                QSOStatusView()
                MessageSelector()
            }
        }
    }

    private var messagesRow: some View {
        HStack(alignment: .top, spacing: LayoutConstants.standardSpacing) {
            messagesColumn(
                title: String(localized: "Received"),
                messages: viewModel.receivedMessages,
                clearAction: viewModel.clearReceived,
                showFilter: true
            )

            Divider()

            messagesColumn(
                title: String(localized: "Transmitted"),
                messages: viewModel.transmittedMessages,
                clearAction: viewModel.clearTransmitted,
                showFilter: false
            )
        }
    }

    private var footerRow: some View {
        HStack {
            QSOStatusView()

            MessageSelector()
        }
    }
    
    @ViewBuilder
    private func messagesColumn(
        title: String,
        messages: [FT8Message],
        clearAction: @escaping () -> Void,
        showFilter: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Button(String(localized: "Clear"), action: clearAction)
                    .disabled(messages.isEmpty)

                Spacer()

                if showFilter {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filterMode = (filterMode + 1) % 3
                        }
                    } label: {
                        Image(systemName: filterMode == 0
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            filterMode == 0 ? .secondary :
                            filterMode == 1 ? .primary : Color.accentColor
                        )
                        .accessibilityLabel(
                            filterMode == 0 ? "Show all messages" :
                            filterMode == 1 ? "Show mine" : "Show mine and CQ"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !showFilter {
                    Button {
                        showLegend.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showLegend) {
                        MessageColorLegendView()
                    }
                }
            }
            .padding(.horizontal, LayoutConstants.compactPadding)
            .padding(.vertical, 4)
            
            SeparatedMsgListView(
                messages: messages,
                allowReply: showFilter,
                filterMode: $filterMode
            )
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let viewModel = FT8ViewModel(
        txMessages: PreviewMocks.txMessages,
        rxMessages: PreviewMocks.rxMessages
    )
    
    viewModel.callsign = "EA4IQL"
    viewModel.locator = "IN80"
    
    return SeparatedTransmissionDashboardView()
        .environmentObject(viewModel)
        .padding()
}
