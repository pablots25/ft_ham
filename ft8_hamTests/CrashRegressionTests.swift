// CrashRegressionTests.swift
// ft8_hamTests
//
// Regression tests for fatal crashes reported by Crashlytics and fixed on
// bugfix/crashlytics-fatal-crashes. Each test reproduces the mechanism of a
// production crash and asserts the app-level defence holds.
//
//   1. a315fe8f — AudioManager.playAudio: -[AVAudioPlayerNode play] raised
//      NSException "player did not see an IO cycle" when TX started while the
//      app was backgrounded (engine not rendering). Defence: engine-state
//      guards + ObjCExceptionCatcher around play().
//
//   2. da54de2d — kiss_fft kf_work EXC_BAD_ACCESS: monitor_process used stack
//      VLAs sized by nfft (~120 KB at 48 kHz), overflowing the 512 KB stack of
//      Swift-concurrency worker threads. Defence: heap-allocated scratch
//      buffers in monitor_init (local ft8_lib patch).
//
//   3. fe741015 — SwiftUI List out-of-bounds scrollTo: structural fix in
//      MessageListView (scroll deferred to the next runloop turn); the SwiftUI
//      internals involved are not reachable from unit tests.

import XCTest
import AVFoundation
@testable import ft8_ham

final class CrashRegressionTests: XCTestCase {

    // MARK: - ObjCExceptionCatcher contract

    func test_catcher_returnsNormallyWhenNoExceptionIsRaised() {
        var executed = false
        XCTAssertNoThrow(try ObjCExceptionCatcher.catchException { executed = true })
        XCTAssertTrue(executed)
    }

    func test_catcher_convertsNSExceptionIntoSwiftError() {
        XCTAssertThrowsError(try ObjCExceptionCatcher.catchException {
            NSException(name: .internalInconsistencyException,
                        reason: "synthetic test exception",
                        userInfo: nil).raise()
        }) { error in
            XCTAssertTrue(error.localizedDescription.contains("synthetic test exception"),
                          "The NSException reason must be preserved in the NSError")
        }
    }

    // MARK: - Crash 1: AVAudioPlayerNode.play() without a running engine

    /// AVFoundation raises NSExceptions from play() when the node/engine is in
    /// an invalid state. An unattached node throws deterministically ("required
    /// condition is false: _engine != nil") — the same uncatchable-from-Swift
    /// mechanism as the production "player did not see an IO cycle" crash. The
    /// catcher must convert it into a recoverable error.
    func test_playerNodePlay_onUnattachedNode_isCaughtAsErrorNotCrash() {
        let node = AVAudioPlayerNode()

        XCTAssertThrowsError(try ObjCExceptionCatcher.catchException { node.play() },
                             "play() on an unattached node must surface as a Swift error")
    }

    /// The production state (engine attached but not rendering) does not throw
    /// deterministically in the simulator; what matters is that the guarded
    /// call can never escape as an uncaught NSException. Reaching the end of
    /// this test proves containment either way.
    func test_playerNodePlay_withoutRunningEngine_isContained() {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 12_000, channels: 1))
        // Engine deliberately NOT started — same state as TX in background.

        _ = try? ObjCExceptionCatcher.catchException { node.play() }
        node.stop()
    }

    // MARK: - Crash 3: FT8 decode on a small-stack thread

    /// Reproduces Crashlytics issue da54de2d: decodeBufferUsingMonitor ran on a
    /// Swift-concurrency cooperative thread (512 KB stack) and overflowed it via
    /// monitor_process stack VLAs at high sample rates. Running the decode on a
    /// thread with the same stack size must complete without crashing.
    func test_decodeBufferUsingMonitor_onCooperativePoolSizedStack_doesNotOverflow() {
        let sampleRate = 48_000.0
        // A full FT8 slot of silence — enough blocks to drive monitor_process
        // through its FFT loop many times.
        let nSamples = Int(sampleRate * 13.0)
        let audioData = Data(count: nSamples * MemoryLayout<Float>.size)

        let finished = expectation(description: "decode completed without crashing")

        let thread = Thread {
            let engine = ft8_Engine()
            _ = engine.decodeBuffer(usingMonitor: audioData,
                                    sampleRate: sampleRate,
                                    isFT4: false)
            finished.fulfill()
        }
        // Match the stack budget of Swift-concurrency worker threads.
        thread.stackSize = 512 * 1024
        thread.start()

        wait(for: [finished], timeout: 60)
    }

    /// Same defence at the highest sample rate iOS hardware reports (96 kHz):
    /// nfft doubles, which is the configuration most likely to overflow.
    func test_decodeBufferUsingMonitor_at96kHz_onSmallStack_doesNotOverflow() {
        let sampleRate = 96_000.0
        let nSamples = Int(sampleRate * 13.0)
        let audioData = Data(count: nSamples * MemoryLayout<Float>.size)

        let finished = expectation(description: "96 kHz decode completed without crashing")

        let thread = Thread {
            let engine = ft8_Engine()
            _ = engine.decodeBuffer(usingMonitor: audioData,
                                    sampleRate: sampleRate,
                                    isFT4: false)
            finished.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()

        wait(for: [finished], timeout: 60)
    }
}
