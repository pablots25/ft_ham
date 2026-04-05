//
//  CondensedTransmissionView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

struct CondensedTransmissionView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    @AppStorage("hasSeenSlideToReplyTutorial") private var hasSeenTutorial: Bool = false
    @State private var showTutorial: Bool = false
    @State private var columnFrame: CGRect = .zero

    @AppStorage("rxFilterMode")
    private var filterMode: Int = 0

    @State private var showLegend: Bool = false

    private var needsTutorial: Bool {
        !hasSeenTutorial
    }

    var body: some View {
        GeometryReader { geo in
            // Detect landscape normally, force portrait on iPad
            let isLandscape = (UIDevice.current.userInterfaceIdiom == .pad) ? false : (geo.size.width > geo.size.height)


            ZStack {
                Group {
                    if isLandscape {
                        landscapeLayout(height: geo.size.height)
                    } else {
                        portraitLayout()
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isLandscape)

                if showTutorial {
                    TutorialOverlay(
                        highlightedFrame: columnFrame,
                        text: String(localized: "tutorial_swipe_reply")
                    ) {
                        hasSeenTutorial = true
                        showTutorial = false
                    }
                }
            }
            .coordinateSpace(name: "CondensedTransmissionSpace")
        }
        .onAppear {
            showTutorial = needsTutorial
        }
    }

    // MARK: - Layouts

    private func portraitLayout() -> some View {
        VStack(spacing: 10) {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]

            if UIDevice.current.userInterfaceIdiom != .pad {
                LazyVGrid(columns: columns, spacing: 12) {
                    StatusView().gridCellColumns(2)
                    ClockView().gridCellColumns(2)
                }
                .padding(.horizontal)
            }

            TransmissionButtonsBar()
                .padding(.horizontal)
                .padding(.bottom)

            messagesSection
                .padding(.horizontal)

            VStack {
                QSOStatusView()
//                DXInfoFields()
                MessageSelector()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 10)
        }
    }

    private func landscapeLayout(height: CGFloat) -> some View {
        VStack {
            messagesSectionLandscape
                .padding(.bottom,0)
            
            Divider()
            
            controlPanel
                .padding(.vertical, 0)
        }
    }

    // MARK: - Control Panel & Messages

    private var controlPanel: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

        return LazyVGrid(columns: columns, spacing: 2) {
            TransmissionButtonsBar()
                .frame(maxWidth: .infinity)
                .padding(.leading,50)
                .multilineTextAlignment(.center)

            QSOStatusView()
                .frame(maxWidth: .infinity)
                .padding(.leading,30)
                .multilineTextAlignment(.center)
            
//            DXInfoFields()
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                .padding(.horizontal)

            MessageSelector()
                .frame(maxWidth: .infinity)
                .padding(.trailing,20)
        }
        .ignoresSafeArea()
    }

    private var messagesSection: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                messagesColumn(
                    section: .received,
                    messages: viewModel.receivedMessages,
                    clearAction: viewModel.clearReceived,
                    allowReply: true
                )
                .frame(height: geo.size.height * 0.55)

                Divider()

                messagesColumn(
                    section: .transmitted,
                    messages: viewModel.transmittedMessages,
                    clearAction: viewModel.clearTransmitted,
                    allowReply: false
                )
            }
        }
    }
    
    private var messagesSectionLandscape: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                let receivedFiltered: [FT8Message] = {
                    switch filterMode {
                    case 1: return viewModel.receivedMessages.filter { $0.forMe || $0.isTX }
                    case 2: return viewModel.receivedMessages.filter { $0.forMe || $0.isTX || $0.msgType == .cq }
                    default: return viewModel.receivedMessages
                    }
                }()
                
                let txFiltered: [FT8Message] = {
                    switch filterMode {
                    case 1: return viewModel.transmittedMessages.filter { $0.forMe || $0.isTX }
                    case 2: return viewModel.transmittedMessages.filter { $0.forMe || $0.isTX || $0.msgType == .cq }
                    default: return viewModel.transmittedMessages
                    }
                }()
                
                messagesColumn(
                    section: .received,
                    messages: receivedFiltered,
                    clearAction: viewModel.clearReceived,
                    allowReply: true
                )

                Divider()

                messagesColumn(
                    section: .transmitted,
                    messages: txFiltered,
                    clearAction: viewModel.clearTransmitted,
                    allowReply: false
                )
            }
        }
    }

    private func messagesColumn(
        section: TransmissionSection,
        messages: [FT8Message],
        clearAction: @escaping () -> Void,
        allowReply: Bool = false
    ) -> some View {
        ZStack {
            VStack(alignment: .center) {
                HStack {
                    Text(section.localizedName)
                        .font(.headline)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Button(String(localized: "Clear"), action: clearAction)
                                .disabled(messages.isEmpty)

                    Spacer()
                    
                    if(allowReply){
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
                .padding(.horizontal)
                .padding(.vertical, 6)
                if showTutorial, allowReply {
                    
                    CondensedMsgListView(
                        messages: tutorialSampleMessages(from: messages),
                        allowReply: allowReply,
                        filterMode: $filterMode
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    columnFrame = proxy.frame(in: .named("CondensedTransmissionSpace"))
                                }
                                .onChange(of: proxy.size) { _ in
                                    columnFrame = proxy.frame(in: .named("CondensedTransmissionSpace"))
                                }
                        }
                    )
                } else {
                    CondensedMsgListView(
                        messages: messages,
                        allowReply: allowReply,
                        filterMode: $filterMode
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    private func tutorialSampleMessages(from messages: [FT8Message]) -> [FT8Message] {
        if let previewSample = PreviewMocks.rxMessages.first {
            return [previewSample]
        }

        if let firstLiveMessage = messages.first {
            return [firstLiveMessage]
        }

        return []
    }
}

#Preview("CondensedTransmissionView") {
    CondensedTransmissionView()
        .environmentObject(
            FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            )
        )
}
