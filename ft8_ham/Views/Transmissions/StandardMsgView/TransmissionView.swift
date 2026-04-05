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
    @State private var showTutorial: Bool = false

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
                        landscapeLayout(width: geo.size.width)
                    } else {
                        portraitLayout()
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isLandscape)
                .frame(width: geo.size.width, height: geo.size.height)

                if showTutorial {
                    TutorialOverlay(
                        highlightedFrame: adjustedTutorialFrame,
                        text: String(localized: "tutorial_swipe_reply")
                    ) {
                        hasSeenTutorial = true
                        showTutorial = false
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
                    
                    if allowReply {
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

                    if !allowReply {
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
                .padding(.vertical, 6)
                
                if showTutorial, allowReply {
                    MessageListView(
                        messages: tutorialSampleMessages(from: messages),
                        allowReply: allowReply,
                        filterMode: $filterMode
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
                        filterMode: $filterMode
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
