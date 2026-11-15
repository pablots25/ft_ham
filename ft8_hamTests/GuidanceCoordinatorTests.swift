//
//  GuidanceCoordinatorTests.swift
//  ft_ham
//
//  First-run tutorials must never pile up on each other or on a launch
//  prompt: one at a time, only once the screen is free.
//

import XCTest
@testable import ft8_ham

// MARK: - Decision

final class GuidanceCoordinatorDecisionTests: XCTestCase {

    private let neverSeen: (AppTutorial) -> Bool = { _ in false }

    func test_nothingIsShownWhileBlocked() {
        XCTAssertNil(GuidanceCoordinator.nextTutorial(
            active: nil, waiting: [.slideToReply], isBlocked: true, hasSeen: neverSeen))
    }

    func test_oldestWaitingTutorialGoesFirst() {
        XCTAssertEqual(GuidanceCoordinator.nextTutorial(
            active: nil, waiting: [.waterfallButtons, .slideToReply], isBlocked: false, hasSeen: neverSeen),
            .waterfallButtons)
    }

    /// The tutorial on screen keeps its turn: a second one never stacks on it.
    func test_activeTutorialKeepsItsTurn() {
        XCTAssertEqual(GuidanceCoordinator.nextTutorial(
            active: .slideToReply, waiting: [.waterfallButtons, .slideToReply], isBlocked: false, hasSeen: neverSeen),
            .slideToReply)
    }

    func test_seenTutorialsAreSkipped() {
        XCTAssertEqual(GuidanceCoordinator.nextTutorial(
            active: nil, waiting: [.slideToReply, .waterfallButtons], isBlocked: false,
            hasSeen: { $0 == .slideToReply }),
            .waterfallButtons)
    }

    func test_seenKeysMatchTheExistingStorage() {
        // Users who dismissed a tutorial before this change must not see it again.
        XCTAssertEqual(AppTutorial.slideToReply.seenKey, "hasSeenSlideToReplyTutorial")
        XCTAssertEqual(AppTutorial.waterfallButtons.seenKey, "hasSeenFloatingButtonTutorial")
    }
}

// MARK: - Sequencing

@MainActor
final class GuidanceCoordinatorSequencingTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "GuidanceCoordinatorSequencingTests"
    private var sut: GuidanceCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        sut = GuidanceCoordinator(defaults: defaults, settleDelay: .zero)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        try await super.tearDown()
    }

    /// Lets the coordinator's deferred grant run.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    /// The reported case: the slide-to-reply tutorial came up together with
    /// the "Callsign and Locator not configured" alert.
    func test_tutorialWaitsForLaunchPrompts() async {
        sut.request(.slideToReply)
        await settle()
        XCTAssertNil(sut.activeTutorial, "Starts blocked until ContentView reports a free screen")

        sut.setBlocked(false)
        await settle()
        XCTAssertEqual(sut.activeTutorial, .slideToReply)
    }

    func test_promptThatComesUpHidesTheTutorialAndItComesBack() async {
        sut.setBlocked(false)
        sut.request(.slideToReply)
        await settle()
        XCTAssertEqual(sut.activeTutorial, .slideToReply)

        sut.setBlocked(true)
        XCTAssertNil(sut.activeTutorial)

        sut.setBlocked(false)
        await settle()
        XCTAssertEqual(sut.activeTutorial, .slideToReply)
    }

    func test_onlyOneTutorialAtATime() async {
        sut.setBlocked(false)
        sut.request(.slideToReply)
        sut.request(.waterfallButtons)
        await settle()
        XCTAssertEqual(sut.activeTutorial, .slideToReply)

        sut.finish(.slideToReply)
        await settle()
        XCTAssertEqual(sut.activeTutorial, .waterfallButtons)
    }

    func test_finishMarksTheTutorialAsSeen() async {
        sut.setBlocked(false)
        sut.request(.waterfallButtons)
        await settle()
        sut.finish(.waterfallButtons)
        XCTAssertTrue(defaults.bool(forKey: AppTutorial.waterfallButtons.seenKey))

        sut.request(.waterfallButtons)
        await settle()
        XCTAssertNil(sut.activeTutorial, "A dismissed tutorial is not shown again")
    }

    /// Leaving the tab hands the turn back instead of keeping it hidden.
    func test_withdrawFreesTheTurn() async {
        sut.setBlocked(false)
        sut.request(.slideToReply)
        await settle()
        sut.request(.waterfallButtons)
        sut.withdraw(.slideToReply)
        await settle()
        XCTAssertEqual(sut.activeTutorial, .waterfallButtons)
        XCTAssertFalse(defaults.bool(forKey: AppTutorial.slideToReply.seenKey),
                       "Withdrawn is not seen: it shows again on the next visit")
    }

    func test_alreadySeenTutorialIsNeverRequested() async {
        defaults.set(true, forKey: AppTutorial.slideToReply.seenKey)
        sut.setBlocked(false)
        sut.request(.slideToReply)
        await settle()
        XCTAssertNil(sut.activeTutorial)
    }
}
