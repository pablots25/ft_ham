//
//  SeparatedTransmissionView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

struct SeparatedTransmissionView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    let section: TransmissionSection
    let allowReply: Bool

    @State private var columnFrame: CGRect = .zero
    @AppStorage("hasSeenSlideToReplyTutorial") private var hasSeenTutorial: Bool = false
    @State private var showTutorial: Bool = false

    @AppStorage("rxFilterModeSeparated")
    private var filterMode: Int = 0

    @State private var showLegend: Bool = false

    private var needsTutorial: Bool {
        !hasSeenTutorial
    }

    init(section: TransmissionSection, allowReply: Bool = false) {
        self.section = section
        self.allowReply = allowReply
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
            .coordinateSpace(name: "SeparatedTransmissionSpace")
        }
        .onAppear {
            showTutorial = allowReply && needsTutorial
        }
    }

    // MARK: - Tutorial frame adjustment

    private var adjustedTutorialFrame: CGRect {
        guard columnFrame != .zero else { return .zero }

        return CGRect(
            x: columnFrame.minX,
            y: columnFrame.minY,
            width: columnFrame.width,
            height: columnFrame.height / 2
        )
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

    // MARK: - Control Panel & Messages

    private var controlPanel: some View {
        VStack(spacing: 20) {
            TransmissionButtonsBar()
            Divider()
            QSOStatusView().padding(.horizontal)
//            DXInfoFields().padding(.horizontal)
            MessageSelector().padding(.horizontal)
        }
    }

    private var messagesSection: some View {
        HStack(alignment: .top, spacing: 12) {
            let baseMessages = allowReply ? viewModel.receivedMessages : viewModel.transmittedMessages
            let filtered: [FT8Message] = {
                switch filterMode {
                case 1: return baseMessages.filter { $0.forMe || $0.isTX }
                case 2: return baseMessages.filter { $0.forMe || $0.isTX || $0.msgType == .cq }
                default: return baseMessages
                }
            }()
            
            let clearAction = allowReply ? viewModel.clearReceived : viewModel.clearTransmitted
            
            messagesColumn(
                section: section,
                messages: filtered,
                clearAction: clearAction,
                allowReply: allowReply
            )
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
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    if showTutorial, allowReply {
                        SeparatedMsgListView(
                            messages: tutorialSampleMessages(from: messages),
                            allowReply: allowReply, filterMode: $filterMode
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        columnFrame = proxy.frame(in: .named("SeparatedTransmissionSpace"))
                                    }
                                    .modifier(SeparatedTransmissionView.SizeChangeModifier(proxy: proxy, update: { newFrame in
                                        columnFrame = newFrame
                                    }))
                            }
                        )
                    } else {
                        SeparatedMsgListView(messages: messages, allowReply: allowReply, filterMode: $filterMode)
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

#Preview("SeparatedTransmissionView") {
    SeparatedTransmissionView(section: .received, allowReply: true)
        .environmentObject(
            FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            )
        )
}

// MARK: - iOS 16+ Size Change Modifier
extension SeparatedTransmissionView {
    struct SizeChangeModifier: ViewModifier {
        let proxy: GeometryProxy
        let update: (CGRect) -> Void

        func body(content: Content) -> some View {
            if #available(iOS 17.0, *) {
                content
                    .onChange(of: proxy.size) { _ in
                        update(proxy.frame(in: .named("SeparatedTransmissionSpace")))
                    }
            } else {
                content
            }
        }
    }
}
