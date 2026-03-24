//
//  TransmissionView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

struct TransmissionView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    @State private var dummyIsSettingFrequency: Bool = false
    @State private var columnFrame: CGRect = .zero
    @AppStorage("hasSeenSlideToReplyTutorial") private var hasSeenTutorial: Bool = false
    @AppStorage("hasSeenMessageColumnTutorial") private var hasSeenColumnTutorial: Bool = false
    @State private var showTutorial: Bool = false
    @State private var columnTutorialStep: Int = 0

    @AppStorage("showOnlyInvolved")
    private var showOnlyInvolved: Bool = false

    private var needsTutorial: Bool {
        !hasSeenTutorial || !hasSeenColumnTutorial
    }

    var body: some View {
        GeometryReader { geo in
            // Detect landscape normally, force portrait on iPad
            let isLandscape = (UIDevice.current.userInterfaceIdiom == .pad) ? false : (geo.size.width > geo.size.height)


            ZStack {
                Group {
                    if isLandscape {
                        landscapeLayout(width: geo.size.width)
                    } else {
                        portraitLayout()
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isLandscape)
                .frame(width: geo.size.width, height: geo.size.height)

                if showTutorial {
                    let isColumnStep = !hasSeenColumnTutorial && columnTutorialStep < 2
                    let tutorialText: String = isColumnStep
                        ? (columnTutorialStep == 0
                            ? String(localized: "tutorial_columns_step1")
                            : String(localized: "tutorial_columns_step2"))
                        : String(localized: "Swipe any message to automatically reply in the frequency used.")

                    TutorialOverlay(
                        highlightedFrame: adjustedTutorialFrame,
                        text: tutorialText
                    ) {
                        if !hasSeenColumnTutorial && columnTutorialStep < 2 {
                            columnTutorialStep += 1
                        } else {
                            if !hasSeenColumnTutorial { hasSeenColumnTutorial = true }
                            hasSeenTutorial = true
                            showTutorial = false
                        }
                    }
                }
            }
            .coordinateSpace(name: "TransmissionSpace")
        }
        .onAppear {
            showTutorial = needsTutorial
        }
    }
}

// MARK: - Layouts

private extension TransmissionView {
    // MARK: - Tutorial frame adjustment
    
    private var adjustedTutorialFrame: CGRect {
        guard columnFrame != .zero else { return .zero }
        
        return CGRect(
            x: columnFrame.minX,
            y: columnFrame.minY,
            width: columnFrame.width,
            height: columnFrame.height / 1.2
        )
    }
    
    func portraitLayout() -> some View {
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
            
            //            WaterfallView(
            //                viewModel: viewModel.waterfallVM,
            //                ft8ViewModel: viewModel,
            //                isSettingFrequency: $dummyIsSettingFrequency
            //            )
            //            .frame(height: 80)
            //            .padding(.horizontal, 25)
            
            VStack {
                QSOStatusView()
                //                DXInfoFields()
                MessageSelector()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 10)
        }
    }
    
    func landscapeLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            controlPanel
                .frame(width: width * 0.45)
            Divider()
            
            messagesSection
                .frame(width: width * 0.55)
                .padding(.horizontal)
                .padding(.trailing)
        }
    }
    
    var controlPanel: some View {
        VStack(spacing: 20) {
            TransmissionButtonsBar()
            Divider()
            QSOStatusView().padding(.horizontal)
            //            DXInfoFields().padding(.horizontal)
            MessageSelector().padding(.horizontal)
        }
    }
    
    var messagesSection: some View {
        HStack(alignment: .top, spacing: 12) {
            let receivedFiltered = showOnlyInvolved
            ? viewModel.receivedMessages.filter { $0.forMe || $0.isTX }
            : viewModel.receivedMessages
            
            let txFiltered = showOnlyInvolved
            ? viewModel.transmittedMessages.filter { $0.forMe || $0.isTX }
            : viewModel.transmittedMessages
            
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
                clearAction: viewModel.clearTransmitted
            )
        }
    }
    
    func messagesColumn(
        section: TransmissionSection,
        messages: [FT8Message],
        clearAction: @escaping () -> Void,
        allowReply: Bool = false
    ) -> some View {
        ZStack {
            VStack(alignment: .center) {
                HStack(spacing: 10){
                    Text(section.localizedName)
                        .font(.headline)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Button(String(localized: "Clear"), action: clearAction)
                        .disabled(messages.isEmpty)
                    
                    if(allowReply){
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showOnlyInvolved.toggle()
                            }
                        } label: {
                            Image(systemName: showOnlyInvolved
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(showOnlyInvolved ? .primary : .secondary)
                            .accessibilityLabel("Filter messages")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                
                if showTutorial, allowReply {
                    MessageListView(
                        messages: tutorialSampleMessages(from: messages),
                        allowReply: allowReply,
                        showOnlyInvolved: $showOnlyInvolved
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    columnFrame = proxy.frame(in: .named("TransmissionSpace"))
                                }
                                .onChange(of: proxy.size) { _ in
                                    columnFrame = proxy.frame(in: .named("TransmissionSpace"))
                                }
                        }
                    )
                } else {
                    MessageListView(
                        messages: messages,
                        allowReply: allowReply,
                        showOnlyInvolved: $showOnlyInvolved
                    )
                }
            }
            
        }.frame(maxWidth: .infinity)
            .padding(.bottom, 2)
    }

    func tutorialSampleMessages(from messages: [FT8Message]) -> [FT8Message] {
        if let previewSample = PreviewMocks.rxMessages.first {
            return [previewSample]
        }

        if let firstLiveMessage = messages.first {
            return [firstLiveMessage]
        }

        return []
    }
}

#Preview("TransmissionView") {
    TransmissionView()
        .environmentObject(
            FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            )
        )
}
