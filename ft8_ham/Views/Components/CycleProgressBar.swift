//
//  CycleProgressBar.swift
//  ft_ham
//
//  Created by Pablo Turrion on 22/9/26.
//

import SwiftUI
import UIKit

/// The slot progress bar, filled by Core Animation rather than by SwiftUI.
///
/// A SwiftUI `ProgressView` updated ten times a second with an animation
/// kept the display link running at 60 Hz for the whole session — about a
/// third of the main-thread time at idle. Here the fill is one linear
/// `CABasicAnimation` per cycle that the render server runs on its own;
/// the app only checks once a second that it is still in phase.
struct CycleProgressBar: UIViewRepresentable {
    /// 0…1, where the cycle is right now.
    let progress: Double
    /// Seconds per cycle (15 for FT8, 7.5 for FT4).
    let cycleLength: Double

    func makeUIView(context: Context) -> CycleProgressBarView {
        CycleProgressBarView()
    }

    func updateUIView(_ view: CycleProgressBarView, context: Context) {
        view.sync(progress: progress, cycleLength: cycleLength)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CycleProgressBarView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: CycleProgressBarView.height)
    }
}

final class CycleProgressBarView: UIView {
    static let height: CGFloat = 4

    private let track = CALayer()
    private let fill = CALayer()
    private var cycleLength: Double = 15
    /// How far out of phase the running animation may be before it is
    /// restarted; the sync runs once a second.
    private let tolerance: Double = 0.03

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        track.backgroundColor = UIColor.tertiarySystemFill.cgColor
        track.cornerRadius = Self.height / 2
        fill.backgroundColor = UIColor.systemGreen.cgColor
        fill.cornerRadius = Self.height / 2
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer.addSublayer(track)
        layer.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = CGRect(x: 0, y: (bounds.height - Self.height) / 2, width: bounds.width, height: Self.height)
        fill.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
        // The animation is in points; a new width needs a new one.
        restart(from: currentPhase())
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        track.backgroundColor = UIColor.tertiarySystemFill.cgColor
        fill.backgroundColor = UIColor.systemGreen.cgColor
    }

    /// Brings the animation in phase with `progress` if it has drifted (clock
    /// realignment, mode change, app resumed from the background).
    func sync(progress: Double, cycleLength: Double) {
        let lengthChanged = cycleLength != self.cycleLength
        self.cycleLength = cycleLength
        guard bounds.width > 0 else { return }
        let running = fill.animation(forKey: Self.animationKey) != nil
        if lengthChanged || !running || abs(currentPhase() - progress) > tolerance {
            restart(from: progress)
        }
    }

    private static let animationKey = "cycle"

    /// The fill's current fraction as the render server is showing it.
    private func currentPhase() -> Double {
        guard bounds.width > 0 else { return 0 }
        let shown = fill.presentation()?.bounds.width ?? fill.bounds.width
        return Double(shown / bounds.width)
    }

    /// One linear run to the end of this cycle, then a repeating full cycle.
    private func restart(from phase: Double) {
        let width = bounds.width
        guard width > 0, cycleLength > 0 else { return }
        let start = min(max(phase, 0), 1)

        fill.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.bounds = CGRect(x: 0, y: 0, width: width, height: Self.height)
        CATransaction.commit()

        let remaining = (1 - start) * cycleLength
        let first = CABasicAnimation(keyPath: "bounds.size.width")
        first.fromValue = start * width
        first.toValue = width
        first.duration = max(remaining, 0.001)
        first.timingFunction = CAMediaTimingFunction(name: .linear)

        let repeating = CABasicAnimation(keyPath: "bounds.size.width")
        repeating.fromValue = 0
        repeating.toValue = width
        repeating.duration = cycleLength
        repeating.beginTime = first.duration
        repeating.repeatCount = .infinity
        repeating.timingFunction = CAMediaTimingFunction(name: .linear)

        let group = CAAnimationGroup()
        group.animations = [first, repeating]
        // Core Animation clips a group to its duration and treats an infinite
        // one as the 0.25 s default, which froze the bar; a year is plenty.
        group.duration = 365 * 24 * 3600
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        fill.add(group, forKey: Self.animationKey)
    }
}
