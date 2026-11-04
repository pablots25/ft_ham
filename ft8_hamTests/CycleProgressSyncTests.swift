//
//  CycleProgressSyncTests.swift
//  ft_hamTests
//
//  Regression tests for slot progress bar drift:
//  - ProgressViewModel reads the SNTP-corrected AppClock, the clock
//    SlotManager schedules on, instead of the raw system clock.
//  - CycleProgressBarView skips its drift check when there is no
//    presentation layer instead of reading a full bar and restarting.
//  - A resync token forces one restart (used when the app becomes active).
//

import XCTest
@testable import ft8_ham

@MainActor
final class CycleProgressSyncTests: XCTestCase {

    private var savedOffset: TimeInterval = 0

    override func setUp() {
        super.setUp()
        savedOffset = AppClock.shared.offset
    }

    override func tearDown() {
        AppClock.shared.offset = savedOffset
        super.tearDown()
    }

    // MARK: - Phase math

    func testPhaseAtSlotStartIsZero() {
        let date = Date(timeIntervalSince1970: 1_800_000_000) // multiple of 15
        XCTAssertEqual(ProgressViewModel.phase(at: date, cycleLength: 15), 0, accuracy: 1e-9)
    }

    func testPhaseMidSlotFT8() {
        let date = Date(timeIntervalSince1970: 1_800_000_000 + 7.5)
        XCTAssertEqual(ProgressViewModel.phase(at: date, cycleLength: 15), 0.5, accuracy: 1e-9)
    }

    func testPhaseFT4UsesSevenAndAHalfSecondSlots() {
        let date = Date(timeIntervalSince1970: 1_800_000_000 + 7.5 + 3.75)
        XCTAssertEqual(ProgressViewModel.phase(at: date, cycleLength: 7.5), 0.5, accuracy: 1e-9)
    }

    func testPhaseAlwaysInUnitRange() {
        for t in stride(from: 0.0, to: 60.0, by: 0.37) {
            let phase = ProgressViewModel.phase(at: Date(timeIntervalSince1970: 1_800_000_000 + t), cycleLength: 15)
            XCTAssertGreaterThanOrEqual(phase, 0)
            XCTAssertLessThan(phase, 1)
        }
    }

    func testPhaseWithZeroCycleLengthIsZero() {
        XCTAssertEqual(ProgressViewModel.phase(at: Date(), cycleLength: 0), 0)
    }

    // MARK: - Clock source

    func testCycleProgressFollowsInjectedClock() {
        let fixed = Date(timeIntervalSince1970: 1_800_000_000 + 3)
        let vm = ProgressViewModel(now: { fixed })
        XCTAssertEqual(vm.cycleProgress(isFT4: false), 3.0 / 15.0, accuracy: 1e-9)
        XCTAssertEqual(vm.cycleProgress(isFT4: true), 3.0 / 7.5, accuracy: 1e-9)
    }

    func testDefaultClockIsAppClockWithSNTPOffset() {
        // An offset of half a slot moves the phase by 0.5 compared to the
        // raw system clock. Reading Date() would ignore it.
        AppClock.shared.offset = 7.5
        let vm = ProgressViewModel()
        let expected = ProgressViewModel.phase(at: AppClock.now(), cycleLength: 15)
        let rawPhase = ProgressViewModel.phase(at: Date(), cycleLength: 15)
        let progress = vm.cycleProgress(isFT4: false)

        XCTAssertLessThan(circularDistance(progress, expected), 0.01)
        XCTAssertGreaterThan(circularDistance(progress, rawPhase), 0.4)
    }

    func testRepeatedReadsDoNotJumpBackwardsWithinASlot() {
        var t = 1_800_000_000.0
        let vm = ProgressViewModel(now: { Date(timeIntervalSince1970: t) })
        var previous = vm.cycleProgress(isFT4: false)
        for _ in 0..<14 {
            t += 1
            let next = vm.cycleProgress(isFT4: false)
            XCTAssertGreaterThan(next, previous)
            previous = next
        }
    }

    // MARK: - Drift check

    func testNoPresentationLayerSkipsDriftCheck() {
        XCTAssertFalse(CycleProgressBarView.needsRestart(shownPhase: nil, targetPhase: 0.2, tolerance: 0.03))
    }

    func testDriftWithinToleranceDoesNotRestart() {
        XCTAssertFalse(CycleProgressBarView.needsRestart(shownPhase: 0.50, targetPhase: 0.52, tolerance: 0.03))
    }

    func testDriftBeyondToleranceRestarts() {
        XCTAssertTrue(CycleProgressBarView.needsRestart(shownPhase: 0.50, targetPhase: 0.60, tolerance: 0.03))
    }

    // MARK: - View sync

    /// Width the running animation started from, in points. Core Animation
    /// hands back copies, so the animation itself cannot be compared by identity.
    private func startWidth(of view: CycleProgressBarView) -> Double? {
        guard
            let group = view.layer.sublayers?.last?.animation(forKey: "cycle") as? CAAnimationGroup,
            let first = group.animations?.first as? CABasicAnimation
        else { return nil }
        return (first.fromValue as? NSNumber)?.doubleValue
    }

    func testSyncWithoutPresentationLayerKeepsAnimation() {
        // Never added to a window, so the fill has no presentation layer,
        // just like a bar that is off screen or on another tab.
        let view = CycleProgressBarView(frame: CGRect(x: 0, y: 0, width: 200, height: 4))
        view.layoutIfNeeded()
        view.sync(progress: 0.2, cycleLength: 15)
        let before = startWidth(of: view)
        XCTAssertNotNil(before)

        // The model width reads full here. A sync must not take that as
        // drift and restart the animation.
        view.sync(progress: 0.27, cycleLength: 15)
        XCTAssertEqual(startWidth(of: view), before)
    }

    func testResyncTokenForcesRestart() {
        let view = CycleProgressBarView(frame: CGRect(x: 0, y: 0, width: 200, height: 4))
        view.layoutIfNeeded()
        view.sync(progress: 0.2, cycleLength: 15, resyncToken: 0)

        view.sync(progress: 0.5, cycleLength: 15, resyncToken: 1)
        XCTAssertEqual(startWidth(of: view) ?? -1, 100, accuracy: 0.001)
    }

    func testCycleLengthChangeRestartsAtProgress() {
        let view = CycleProgressBarView(frame: CGRect(x: 0, y: 0, width: 200, height: 4))
        view.layoutIfNeeded()
        view.sync(progress: 0.25, cycleLength: 7.5)
        XCTAssertEqual(startWidth(of: view) ?? -1, 50, accuracy: 0.001)
    }

    private func circularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 1 - d)
    }
}
