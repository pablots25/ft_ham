// AudioManagerGainTests.swift
// ft8_hamTests
//
// Tests for AudioManager gain clamping (minGain=0.1, maxGain=2.0)
// and for MockAudioManager publisher + call-tracking behaviour.
//
// AudioManager is initialised with isTestMode:true to prevent any
// AVAudioEngine or AVAudioSession access (see README_TESTING.md).

import XCTest
import Combine
@testable import ft8_ham

/// Tests for `AudioManager.setInputGain(_:)` clamping behaviour in test mode.
final class AudioManagerGainClampingTests: XCTestCase {

    private var sut: AudioManager!

    override func setUp() {
        super.setUp()
        // isTestMode skips all audio engine initialisation — safe in XCTest
        sut = AudioManager(
            waterfallFFTSize: 512,
            sampleRate: 12000,
            initialGain: 1.0,
            isTestMode: true
        )
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Clamping — below minimum

    func test_setInputGain_belowMinimum_isClampedTo0_1() {
        sut.setInputGain(0.05)
        XCTAssertEqual(sut.getCurrentInputGain(), 0.1, accuracy: 1e-9,
                       "Gain below 0.1 must be clamped to 0.1")
    }

    func test_setInputGain_zero_isClampedTo0_1() {
        sut.setInputGain(0.0)
        XCTAssertEqual(sut.getCurrentInputGain(), 0.1, accuracy: 1e-9)
    }

    func test_setInputGain_negative_isClampedTo0_1() {
        sut.setInputGain(-5.0)
        XCTAssertEqual(sut.getCurrentInputGain(), 0.1, accuracy: 1e-9)
    }

    // MARK: - Clamping — above maximum

    func test_setInputGain_aboveMaximum_isClampedTo2_0() {
        sut.setInputGain(3.0)
        XCTAssertEqual(sut.getCurrentInputGain(), 2.0, accuracy: 1e-9,
                       "Gain above 2.0 must be clamped to 2.0")
    }

    func test_setInputGain_largeValue_isClampedTo2_0() {
        sut.setInputGain(100.0)
        XCTAssertEqual(sut.getCurrentInputGain(), 2.0, accuracy: 1e-9)
    }

    // MARK: - Valid range passthrough

    func test_setInputGain_minimum_isPreserved() {
        sut.setInputGain(0.1)
        XCTAssertEqual(sut.getCurrentInputGain(), 0.1, accuracy: 1e-9)
    }

    func test_setInputGain_maximum_isPreserved() {
        sut.setInputGain(2.0)
        XCTAssertEqual(sut.getCurrentInputGain(), 2.0, accuracy: 1e-9)
    }

    func test_setInputGain_midRange_isPreserved() {
        sut.setInputGain(1.0)
        XCTAssertEqual(sut.getCurrentInputGain(), 1.0, accuracy: 1e-9)
    }

    func test_setInputGain_0_5_isPreserved() {
        sut.setInputGain(0.5)
        XCTAssertEqual(sut.getCurrentInputGain(), 0.5, accuracy: 1e-9)
    }

    // MARK: - initialGain respects clamping

    func test_init_initialGainBelowMinimum_isClampedTo0_1() {
        let mgr = AudioManager(waterfallFFTSize: 512, sampleRate: 12000, initialGain: 0.0, isTestMode: true)
        XCTAssertEqual(mgr.getCurrentInputGain(), 0.1, accuracy: 1e-9)
    }

    func test_init_initialGainAboveMaximum_isClampedTo2_0() {
        let mgr = AudioManager(waterfallFFTSize: 512, sampleRate: 12000, initialGain: 5.0, isTestMode: true)
        XCTAssertEqual(mgr.getCurrentInputGain(), 2.0, accuracy: 1e-9)
    }

    func test_init_initialGainInRange_isPreserved() {
        let mgr = AudioManager(waterfallFFTSize: 512, sampleRate: 12000, initialGain: 0.7, isTestMode: true)
        XCTAssertEqual(mgr.getCurrentInputGain(), 0.7, accuracy: 1e-9)
    }
}

// MARK: -

/// Tests for `MockAudioManager` — verifies publisher behaviour and call-count tracking
/// used by tests that inject mocks into FT8ViewModel or other components.
final class MockAudioManagerTests: XCTestCase {

    private var sut: MockAudioManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = MockAudioManager()
        cancellables = []
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func test_initialState_isListeningIsFalse() {
        XCTAssertFalse(sut.isListening)
    }

    func test_initialState_isPlayingIsFalse() {
        XCTAssertFalse(sut.isPlaying)
    }

    func test_initialState_callCountsAreZero() {
        XCTAssertEqual(sut.startMicInputCallCount, 0)
        XCTAssertEqual(sut.stopMicInputCallCount, 0)
        XCTAssertEqual(sut.playAudioCallCount, 0)
        XCTAssertEqual(sut.stopPlaybackCallCount, 0)
    }

    // MARK: - startMicInput / stopMicInput

    @MainActor
    func test_startMicInput_incrementsCallCount() {
        sut.startMicInput()
        XCTAssertEqual(sut.startMicInputCallCount, 1)
    }

    @MainActor
    func test_startMicInput_setsIsListeningTrue() {
        sut.startMicInput()
        XCTAssertTrue(sut.isListening)
    }

    @MainActor
    func test_stopMicInput_setsIsListeningFalse() {
        sut.startMicInput()
        sut.stopMicInput()
        XCTAssertFalse(sut.isListening)
        XCTAssertEqual(sut.stopMicInputCallCount, 1)
    }

    // MARK: - playAudio / stopPlayback

    func test_playAudio_incrementsCallCount() {
        sut.playAudio(Data(repeating: 0, count: 512))
        XCTAssertEqual(sut.playAudioCallCount, 1)
    }

    func test_playAudio_storesLastPlayedData() {
        let data = Data([0x01, 0x02, 0x03])
        sut.playAudio(data)
        XCTAssertEqual(sut.lastPlayedAudioData, data)
    }

    func test_playAudio_setsIsPlayingTrue() {
        sut.playAudio(Data(repeating: 0, count: 64))
        XCTAssertTrue(sut.isPlaying)
    }

    func test_stopPlayback_setsIsPlayingFalse() {
        sut.playAudio(Data(repeating: 0, count: 64))
        sut.stopPlayback()
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(sut.stopPlaybackCallCount, 1)
    }

    // MARK: - audioSamplesPublisher

    func test_simulateAudioSamples_publisherFiresWithCorrectPayload() {
        let expected: [Float] = [0.1, 0.2, 0.3, 0.4]
        var received: [Float] = []
        let expectation = expectation(description: "audioSamplesPublisher fires")

        sut.audioSamplesPublisher
            .sink { samples in
                received = samples
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.simulateAudioSamples(expected)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(received, expected)
    }

    // MARK: - clippingPublisher

    func test_simulateClipping_true_publisherFiresTrue() {
        var receivedValue: Bool?
        let expectation = expectation(description: "clippingPublisher fires")

        sut.clippingPublisher
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.simulateClipping(true)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedValue, true)
    }

    func test_simulateClipping_false_publisherFiresFalse() {
        var receivedValue: Bool?
        let expectation = expectation(description: "clippingPublisher fires false")

        sut.clippingPublisher
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.simulateClipping(false)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedValue, false)
    }

    // MARK: - audioErrorPublisher

    func test_simulateError_publisherFiresWithMessage() {
        let expectedMessage = "Test audio error"
        var receivedMessage: String?
        let expectation = expectation(description: "audioErrorPublisher fires")

        sut.audioErrorPublisher
            .sink { msg in
                receivedMessage = msg
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.simulateError(expectedMessage)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedMessage, expectedMessage)
    }

    // MARK: - rxStatusPublisher via startMicInput/stopMicInput

    @MainActor
    func test_startMicInput_rxStatusPublisherFiresTrue() {
        var received: Bool?
        let expectation = expectation(description: "rxStatusPublisher true")

        sut.rxStatusPublisher
            .sink { status in
                received = status
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.startMicInput()
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(received, true)
    }

    // MARK: - Gain passthrough

    func test_setInputGain_storesValue() {
        sut.setInputGain(1.5)
        XCTAssertEqual(sut.getCurrentInputGain(), 1.5, accuracy: 1e-9)
    }
}
