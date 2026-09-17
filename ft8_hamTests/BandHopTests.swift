//
//  BandHopTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
import Combine
@testable import ft8_ham

// MARK: - Mock

@MainActor
final class MockBandHopScheduler: BandHopSchedulerProtocol {
    @Published var state: BandHopState = .stopped
    let hopSubject = PassthroughSubject<String, Never>()

    private(set) var startCalls: [(schedule: BandHopSchedule, startingAt: String?)] = []
    private(set) var stopCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var skipCount = 0

    var statePublisher: AnyPublisher<BandHopState, Never> { $state.eraseToAnyPublisher() }
    var hopRequests: AnyPublisher<String, Never> { hopSubject.eraseToAnyPublisher() }

    func start(schedule: BandHopSchedule, startingAt bandRaw: String?) {
        startCalls.append((schedule, bandRaw))
        state = .dwelling(bandRaw: bandRaw ?? schedule.steps.first?.bandRaw ?? "", until: Date().addingTimeInterval(600))
    }
    func stop() { stopCount += 1; state = .stopped }
    func pause() {
        if case .dwelling(let band, let until) = state {
            pauseCount += 1
            state = .paused(bandRaw: band, remaining: until.timeIntervalSinceNow)
        }
    }
    func resume() {
        if case .paused(let band, let remaining) = state {
            resumeCount += 1
            state = .dwelling(bandRaw: band, until: Date().addingTimeInterval(remaining))
        }
    }
    func skipToNext() { skipCount += 1 }
}

// MARK: - Schedule

final class BandHopScheduleTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "BandHopScheduleTests")!
        defaults.removePersistentDomain(forName: "BandHopScheduleTests")
    }

    func test_nextIndex_wrapsAndHandlesEmpty() {
        let s = BandHopSchedule(steps: [
            BandHopStep(bandRaw: "20m", dwellMinutes: 5),
            BandHopStep(bandRaw: "40m", dwellMinutes: 5),
            BandHopStep(bandRaw: "15m", dwellMinutes: 5),
        ])
        XCTAssertEqual(s.nextIndex(after: 0), 1)
        XCTAssertEqual(s.nextIndex(after: 2), 0)
        XCTAssertNil(BandHopSchedule().nextIndex(after: 0))
        XCTAssertEqual(s.index(ofBand: "40m"), 1)
        XCTAssertNil(s.index(ofBand: "80m"))
    }

    func test_dwellMinutes_isClampedToAtLeastOne() {
        XCTAssertEqual(BandHopStep(bandRaw: "20m", dwellMinutes: 0).dwellMinutes, 1)
    }

    func test_saveAndLoad_roundTrip() {
        let s = BandHopSchedule(steps: [BandHopStep(bandRaw: "20m", dwellMinutes: 7)])
        s.save(to: defaults)
        XCTAssertEqual(BandHopSchedule.load(from: defaults), s)
        XCTAssertNotNil(defaults.data(forKey: BandHopSchedule.storageKey))
    }

    func test_load_missingOrCorrupt_isEmpty() {
        XCTAssertTrue(BandHopSchedule.load(from: defaults).isEmpty)
        defaults.set(Data("junk".utf8), forKey: BandHopSchedule.storageKey)
        XCTAssertTrue(BandHopSchedule.load(from: defaults).isEmpty)
    }
}

// MARK: - View model integration

@MainActor
final class BandHopViewModelTests: XCTestCase {

    private var viewModel: FT8ViewModel!
    private var scheduler: MockBandHopScheduler!
    private var savedSchedule: Data?
    private var savedEnabled: Any?
    private var savedCatEnabled: Any?

    override func setUp() async throws {
        try await super.setUp()
        savedSchedule = UserDefaults.standard.data(forKey: BandHopSchedule.storageKey)
        savedEnabled = UserDefaults.standard.object(forKey: "bandHopEnabled")
        savedCatEnabled = UserDefaults.standard.object(forKey: "catEnabled")
        UserDefaults.standard.removeObject(forKey: "bandHopEnabled")
        UserDefaults.standard.removeObject(forKey: "catEnabled")

        scheduler = MockBandHopScheduler()
        viewModel = FT8ViewModel(audioManager: MockAudioManager(), engine: MockMessageDecoder())
        viewModel.bandHopScheduler = scheduler
        viewModel.bandHopGate = { true }
        viewModel.setupBandHopObserver()
        viewModel.selectedBand = .band20m
        BandHopSchedule(steps: [
            BandHopStep(bandRaw: "20m", dwellMinutes: 5),
            BandHopStep(bandRaw: "40m", dwellMinutes: 5),
        ]).save()
    }

    override func tearDown() async throws {
        viewModel.stopBandHopping()
        viewModel.catEnabled = false
        if let savedCatEnabled { UserDefaults.standard.set(savedCatEnabled, forKey: "catEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "catEnabled") }
        if let savedSchedule { UserDefaults.standard.set(savedSchedule, forKey: BandHopSchedule.storageKey) }
        else { UserDefaults.standard.removeObject(forKey: BandHopSchedule.storageKey) }
        if let savedEnabled { UserDefaults.standard.set(savedEnabled, forKey: "bandHopEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "bandHopEnabled") }
        viewModel = nil
        try await super.tearDown()
    }

    private func armHopping() {
        viewModel.catEnabled = true
        viewModel.bandHopEnabled = true
    }

    func test_enable_withoutCAT_doesNotStart() {
        viewModel.catEnabled = false
        viewModel.bandHopEnabled = true
        XCTAssertTrue(scheduler.startCalls.isEmpty)
    }

    func test_enable_withCAT_startsOnCurrentBand() {
        armHopping()
        XCTAssertEqual(scheduler.startCalls.count, 1)
        XCTAssertEqual(scheduler.startCalls.first?.startingAt, "20m")
        XCTAssertEqual(scheduler.startCalls.first?.schedule.steps.count, 2)
    }

    func test_flagOff_neverStarts() {
        viewModel.bandHopGate = { false }
        armHopping()
        XCTAssertTrue(scheduler.startCalls.isEmpty)
        viewModel.applyBandHop(to: "40m")
        XCTAssertEqual(viewModel.selectedBand, .band20m)
    }

    func test_disable_orCATOff_stopsScheduler() {
        armHopping()
        viewModel.bandHopEnabled = false
        XCTAssertGreaterThanOrEqual(scheduler.stopCount, 1)

        viewModel.bandHopEnabled = true
        let stops = scheduler.stopCount
        viewModel.catEnabled = false
        XCTAssertGreaterThan(scheduler.stopCount, stops)
    }

    func test_applyBandHop_ignoredWhenNotListening() {
        armHopping()
        viewModel.applyBandHop(to: "40m")
        XCTAssertEqual(viewModel.selectedBand, .band20m, "no sequencer running → no hop")
    }

    func test_applyBandHop_ignoresUnknownBand() {
        armHopping()
        viewModel.isSequencerRunning = true
        viewModel.applyBandHop(to: "nope")
        XCTAssertEqual(viewModel.selectedBand, .band20m)
    }

    func test_hopRequest_pausesWhileQSOOngoing() async {
        armHopping()
        XCTAssertEqual(scheduler.state.currentBandRaw, "20m")

        viewModel.qsoManager.startReply(to: FT8Message(text: "CQ K1ABC FN42", mode: .ft8), myCallsign: "EA4IQL", myLocator: "IN80")
        XCTAssertTrue(viewModel.qsoManager.isQSOOngoing())
        await Task.yield()
        if case .paused = scheduler.state {} else {
            XCTFail("expected paused, got \(scheduler.state)")
        }

        viewModel.qsoManager.resetQSO()
        await Task.yield()
        if case .dwelling = scheduler.state {} else {
            XCTFail("expected dwelling after QSO reset, got \(scheduler.state)")
        }
    }

    func test_bandHopState_mirrorsScheduler() async {
        armHopping()
        await Task.yield()
        XCTAssertEqual(viewModel.bandHopState.currentBandRaw, "20m")
        viewModel.stopBandHopping()
        await Task.yield()
        XCTAssertEqual(viewModel.bandHopState, .stopped)
    }
}
