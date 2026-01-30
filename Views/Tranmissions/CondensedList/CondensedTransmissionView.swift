//
//  CondensedTransmissionView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

struct CondensedTransmissionView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    @AppStorage("hasSeenSlideToReplyTutorial") private var hasSeenTutorial: Bool = false
    @State private var showTutorial: Bool = false
    @State private var columnFrame: CGRect = .zero

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
                        text: "Swipe any message to automatically reply in the frequency used."
                    ) {
                        hasSeenTutorial = true
                        showTutorial = false
                    }
                }
            }
            .coordinateSpace(name: "CondensedTransmissionSpace")
        }
        .onAppear {
            if !hasSeenTutorial {
                showTutorial = true
            }
        }
    }

    // MARK: - Layouts

    private func portraitLayout() -> some View {
        VStack(spacing: 10) {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]

            LazyVGrid(columns: columns, spacing: 12) {
                StatusView().gridCellColumns(2)
                ClockView().gridCellColumns(2)
            }
            .padding(.horizontal)

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
                    title: "Received",
                    messages: viewModel.receivedMessages,
                    clearAction: viewModel.clearReceived,
                    allowReply: true
                )
                .frame(height: geo.size.height * 0.55)

                Divider()

                messagesColumn(
                    title: "Transmitted",
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
                messagesColumn(
                    title: "Received",
                    messages: viewModel.receivedMessages,
                    clearAction: viewModel.clearReceived,
                    allowReply: true
                )

                Divider()

                messagesColumn(
                    title: "Transmitted",
                    messages: viewModel.transmittedMessages,
                    clearAction: viewModel.clearTransmitted,
                    allowReply: false
                )
            }
        }
    }

    private func messagesColumn(
        title: LocalizedStringKey,
        messages: [FT8Message],
        clearAction: @escaping () -> Void,
        allowReply: Bool = false
    ) -> some View {
        ZStack {
            VStack(alignment: .center) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Button(String(localized: "Clear"), action: clearAction)
                        .disabled(messages.isEmpty)
                }
                .padding(.bottom, 2)
                if !hasSeenTutorial, allowReply {
                    CondensedMsgListView(
                        messages: [PreviewMocks.rxMessages.first!],
                        allowReply: allowReply
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    columnFrame = proxy.frame(in: .named("CondensedTransmissionSpace"))
                                }
                                .onChange(of: proxy.size) {
                                    columnFrame = proxy.frame(in: .named("CondensedTransmissionSpace"))
                                }
                        }
                    )
                } else {
                    CondensedMsgListView(messages: messages, allowReply: allowReply)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
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
