//
//  WaterfallView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/11/25.
//

import SwiftUI

struct WaterfallView: View {
    @ObservedObject var viewModel: WaterfallViewModel
    @ObservedObject var ft8ViewModel: FT8ViewModel
    @ObservedObject private var overlayState: WaterfallOverlayState
    @EnvironmentObject private var flags: FeatureFlagManager

    @Binding var isSettingFrequency: Bool

    @State private var cursorX: CGFloat? = nil
    @State private var cursorFrequency: Double = 0
    /// Hides the cursor a while after the finger lifts.
    @State private var cursorTimeout: Task<Void, Never>?
    @State private var touchStart: (time: Date, location: CGPoint)?
    @State private var lastTouch: CGPoint = .zero
    @State private var longPressTask: Task<Void, Never>?
    @State private var longPressFired = false
    /// Where and when the previous tap ended, to recognize a double tap.
    @State private var lastTapEnd: (time: Date, location: CGPoint)?

    @AppStorage("waterfallTapToReply") private var tapToReply = true
    @AppStorage("replyTapGesture") private var replyTapGesture: ReplyTapGesture = .single

    /// A touch that moves less than this is a tap (or a long press).
    private static let tapSlop: CGFloat = 8
    private static let longPressSeconds: TimeInterval = 0.5
    /// A second tap within this time (and `tapSlop * 2`) counts as a double tap.
    private static let doubleTapSeconds: TimeInterval = 0.35
    private static let cursorLinger: TimeInterval = 8
    /// A tap this close to a decoded signal lands exactly on it.
    private static let snapToleranceHz = 40.0

    init(viewModel: WaterfallViewModel, ft8ViewModel: FT8ViewModel, isSettingFrequency: Binding<Bool>) {
        self.viewModel = viewModel
        self.ft8ViewModel = ft8ViewModel
        self.overlayState = viewModel.overlayState
        self._isSettingFrequency = isSettingFrequency
    }

    /// Everything the renderer's overlay depends on. Rows themselves never
    /// come through SwiftUI: the view model pushes them straight to the
    /// render view (see `WaterfallRenderView`).
    private var overlayStyle: WaterfallOverlayStyle {
        WaterfallOverlayStyle(
            minDisplayHz: Double(viewModel.config.minDisplayFrequency),
            maxDisplayHz: Double(viewModel.config.maxDisplayFrequency),
            txFrequency: ft8ViewModel.frequency,
            isFT4: ft8ViewModel.isFT4,
            showOverlay: overlayState.showOverlay,
            showTimestamps: overlayState.showTimestamps,
            showVerticalLabels: overlayState.showVerticalLabels,
            showFrequencyTicks: overlayState.showFrequencyTicks,
            showFrequencyMarker: overlayState.showFrequencyMarker
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                WaterfallRenderRepresentable(viewModel: viewModel, style: overlayStyle)

                if !viewModel.hasData {
                    Text("Waiting for audio data...")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let cx = cursorX {
                    FrequencyCursorView(x: cx, frequency: cursorFrequency, height: geo.size.height)
                        .zIndex(1)
                }
            }
            .onAppear { syncSlotContextFlag() }
            .onChange(of: flags.values) { _ in syncSlotContextFlag() }
            .contentShape(Rectangle())
            .gesture(
                // One gesture, three outcomes: a drag shows the cursor (and,
                // in adjust mode, moves the TX frequency with it); a tap on a
                // label replies (when enabled, honoring the reply gesture),
                // otherwise it sets the TX frequency where it landed, snapped
                // to a decoded signal nearby; holding on a label always replies.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let w = max(geo.size.width, 1)
                        let x = min(max(value.location.x, 0), w)

                        lastTouch = value.location
                        if touchStart == nil {
                            touchStart = (Date(), value.location)
                            longPressFired = false
                            if !isSettingFrequency { armLongPress(in: geo.size) }
                        }
                        cursorTimeout?.cancel()
                        cursorX = x
                        cursorFrequency = viewModel.frequencyAtPixel(x: x, width: w)

                        if isSettingFrequency {
                            // Keep the whole signal inside the decoder's passband
                            // even when the finger runs past the band edges.
                            ft8ViewModel.frequency = cursorFrequency.clamped(
                                to: WaterfallViewModel.txFrequencyRange(isFT4: ft8ViewModel.isFT4)
                            )
                        } else if let start = touchStart, distance(start.location, value.location) > Self.tapSlop {
                            longPressTask?.cancel()   // it became a drag
                        }
                    }
                    .onEnded { value in
                        defer { touchStart = nil }
                        longPressTask?.cancel()
                        let moved = touchStart.map { distance($0.location, value.location) } ?? .infinity
                        if isSettingFrequency {
                            isSettingFrequency = false
                        } else if !longPressFired, moved <= Self.tapSlop {
                            handleTap(at: value.location, in: geo.size)
                        }
                        lingerCursor()
                    }
            )
        }
    }

    /// The slot stripe and greyed-out transmit rows live behind a feature
    /// flag; the model is told about it rather than reading it itself.
    private func syncSlotContextFlag() {
        let enabled = flags.isEnabled(.waterfallSlotContext)
        if viewModel.slotContextEnabled != enabled {
            viewModel.slotContextEnabled = enabled
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// DragGesture reports nothing while the finger is still, so the long
    /// press is timed here and checked against the last known position.
    private func armLongPress(in size: CGSize) {
        longPressTask?.cancel()
        longPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.longPressSeconds * 1_000_000_000))
            guard !Task.isCancelled, let start = touchStart,
                  distance(start.location, lastTouch) <= Self.tapSlop else { return }
            longPressFired = true
            replyToLabel(at: lastTouch, in: size)
        }
    }

    /// Keeps the cursor where the finger left it for a few seconds.
    private func lingerCursor() {
        cursorTimeout?.cancel()
        cursorTimeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.cursorLinger * 1_000_000_000))
            guard !Task.isCancelled else { return }
            cursorX = nil
        }
    }

    /// A tap sets the TX frequency, snapping to the nearest decoded signal
    /// still on screen so the finger does not have to hit a 50 Hz slot.
    private func setTXFrequency(fromTapAt x: CGFloat, width: CGFloat) {
        let tapped = viewModel.frequencyAtPixel(x: x, width: width)
        let snapped = viewModel.nearestLabelFrequency(
            to: tapped, toleranceHz: Self.snapToleranceHz, withinRows: viewModel.height
        )
        let target = (snapped ?? tapped)
            .rounded()
            .clamped(to: WaterfallViewModel.txFrequencyRange(isFT4: ft8ViewModel.isFT4))
        guard target != ft8ViewModel.frequency else { return }
        ft8ViewModel.frequency = target
        cursorX = viewModel.xPosition(for: target, in: width)
        cursorFrequency = target
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ft8ViewModel.toast = .info(String(localized: "TX frequency set to \(Int(target)) Hz"), duration: 2)
    }

    /// Routes a plain tap to a reply or a TX frequency change.
    private func handleTap(at point: CGPoint, in size: CGSize) {
        let now = Date()
        let isSecondTap = lastTapEnd.map {
            now.timeIntervalSince($0.time) <= Self.doubleTapSeconds
                && distance($0.location, point) <= Self.tapSlop * 2
        } ?? false
        let outcome = WaterfallTapRouter.outcome(
            tapToReply: tapToReply,
            gesture: replyTapGesture,
            isSecondTap: isSecondTap,
            hasReplyableLabel: tapToReply && replyableMessage(at: point, in: size) != nil
        )
        switch outcome {
        case .reply:
            replyToLabel(at: point, in: size)
        case .setFrequency:
            let w = max(size.width, 1)
            setTXFrequency(fromTapAt: min(max(point.x, 0), w), width: w)
        }
        lastTapEnd = (now, point)
    }

    /// The replyable decoded message whose label sits under `point`, if any.
    private func replyableMessage(at point: CGPoint, in size: CGSize) -> FT8Message? {
        let hz = viewModel.frequencyAtPixel(x: point.x, width: max(size.width, 1))
        let rowFromTop = Int(point.y / WaterfallRenderView.pointsPerRow)
        guard
            let placed = viewModel.placedLabel(nearHz: hz, rowFromTop: rowFromTop, toleranceHz: Self.snapToleranceHz),
            let id = placed.label.messageID,
            let message = ft8ViewModel.receivedMessages.last(where: { $0.id == id }),
            message.allowsReply, !message.isTX
        else { return nil }
        return message
    }

    /// Replies to the decoded message whose label is under `point`, as a tap
    /// on the message list would. Holding a label always lands here,
    /// whatever the tap-to-reply setting says.
    /// - Returns: Whether a reply was started.
    @discardableResult
    private func replyToLabel(at point: CGPoint, in size: CGSize) -> Bool {
        guard let message = replyableMessage(at: point, in: size) else { return false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        ft8ViewModel.reply(to: message)
        return true
    }
}

struct FrequencyCursorView: View {
    let x: CGFloat
    let frequency: Double
    let height: CGFloat // waterfall height
    let labelOffset: CGFloat = 40 // pixels below top
    let labelPadding: CGFloat = 4 // padding inside label

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.yellow.opacity(0.8))
                .frame(width: 1, height: height)
                .position(x: x, y: height / 2)

            GeometryReader { geo in
                let labelWidth: CGFloat = 60
                let adjustedX = min(x + 35, geo.size.width - labelWidth - labelPadding)

                Text(String(format: "%.0f Hz", frequency))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(labelPadding)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.yellow)
                    .cornerRadius(4)
                    .position(x: adjustedX, y: labelOffset)
            }
        }
    }
}

