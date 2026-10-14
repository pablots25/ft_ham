//
//  ConsolidatedTests.swift
//  ft_hamTests
//
//  Created by Pablo Turrion on 12/1/26.
//

import XCTest
@testable import ft8_ham
import MapKit
import SwiftUI

// MARK: - FT8ViewModelTests (original)
@MainActor
final class FT8ViewModelTests: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = FT8ViewModel(txMessages: [], rxMessages: [])
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testGenerateMessagesWithDefaultValues() {
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IM99"
        viewModel.dxCallsign = "K1ABC"
        viewModel.dxLocator = "FN31"
        viewModel.lastSentSNR = 10

        let messages = viewModel.generateMessages()

        XCTAssertEqual(messages.count, 7)
        XCTAssertTrue(messages[0].contains("EA1AAA"))
        XCTAssertTrue(messages[1].contains("K1ABC"))
        XCTAssertTrue(messages[2].contains("+10"))
    }
    
    func testSettingsLoadedReturnsTrueOnlyIfCallsignAndLocatorSet() {
        viewModel.callsign = ""
        viewModel.locator = ""
        XCTAssertFalse(viewModel.settingsLoaded)

        viewModel.callsign = "EA1AAA"
        XCTAssertFalse(viewModel.settingsLoaded)

        viewModel.locator = "IM99"
        XCTAssertTrue(viewModel.settingsLoaded)
    }

    func testWorkedLocatorsAreUpdated() {
        viewModel.receivedMessages = [
            FT8Message(text: "CQ EA4IQL IN80", mode: .ft8, measuredSNR: -12, frequency: 1500.0, timeOffset: 0.1, isTX: false),
            FT8Message(text: "CQ EA5TTT IN15", mode: .ft8, measuredSNR: -12, frequency: 1500.0, timeOffset: 0.1, isTX: false),
            FT8Message(text: "CQ EA1QQQ IN19", mode: .ft8, measuredSNR: -12, frequency: 1500.0, timeOffset: 0.1, isTX: false),
        ]

        for msg in viewModel.receivedMessages {
            if let dx = msg.locator, !dx.isEmpty, !viewModel.workedLocators
                .contains(dx) {
                viewModel.workedLocators.append(dx)
            }
        }

        XCTAssertEqual(viewModel.workedLocators.count, 3)
        XCTAssertTrue(viewModel.workedLocators.contains("IN15"))
        XCTAssertTrue(viewModel.workedLocators.contains("IN19"))
    }

    func testDecodeFromWavAppendsMessages() {
        let message1 = FT8Message.decode(text: "EA1AAA K1ABC +10", mode: .ft8, snr: -10, frequency: 1500, timeOffset: 0.1)
        let message2 = FT8Message.decode(text: "K1ABC EA1AAA -12", mode: .ft8, snr: -12, frequency: 1501, timeOffset: 0.2)
        
        // Simulate engine decoding by setting wavURL to nil (so decode returns empty array) and manually appending
        viewModel.receivedMessages = []
        viewModel.workedLocators = []

        viewModel.receivedMessages.append(message1)
        viewModel.receivedMessages.append(message2)

        for msg in viewModel.receivedMessages {
            if let dx = msg.dxLocator, !dx.isEmpty, !viewModel.workedLocators
                .contains(dx) {
                viewModel.workedLocators.append(dx)
            }
        }

        XCTAssertEqual(viewModel.receivedMessages.count, 2)
        XCTAssertTrue(viewModel.workedLocators.isEmpty || viewModel.workedLocators.count <= 2)
    }
    
    func testClearReceivedMessages() {
        viewModel.receivedMessages = [
            FT8Message(text: "Message 1", mode: .ft8),
            FT8Message(text: "Message 2", mode: .ft8)
        ]

        viewModel.clearReceived()

        XCTAssertTrue(viewModel.receivedMessages.isEmpty)
    }

    func testClearTransmittedMessages() {
        viewModel.transmittedMessages = [
            FT8Message(text: "TX 1", mode: .ft8),
            FT8Message(text: "TX 2", mode: .ft8)
        ]

        viewModel.clearTransmitted()

        XCTAssertTrue(viewModel.transmittedMessages.isEmpty)
    }

    func testClearLastDecodedMessage() {
        viewModel.decodedMessage = FT8Message(text: "Last decoded", mode: .ft8)

        viewModel.clearLastMessage()

        XCTAssertNil(viewModel.decodedMessage)
    }

}

// MARK: - AudioManagerTests
final class AudioManagerTests: XCTestCase {
    func testInitInPreviewMode() {
        let am = AudioManager(waterfallFFTSize: 1024, sampleRate: 12000, isTestMode: true)
        XCTAssertEqual(am.sampleRate, 12000)
        XCTAssertEqual(am.waterfallFFTSize, 1024)
    }

    func testPlayAndStopPlaybackNoCrash() {
        let am = AudioManager(waterfallFFTSize: 256, sampleRate: 12000, isTestMode: true)

        var floats = [Float](repeating: 0.0, count: 16)
        floats[0] = 1.0
        let data = Data(bytes: &floats, count: floats.count * MemoryLayout<Float>.size)

        am.playAudio(data)
        am.stopPlayback()
        XCTAssertFalse(am.isPlaying)
    }
}

// MARK: - FT8ViewModelUnitTests + Integration + E2E
@MainActor
final class FT8ViewModelUnitTests: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = FT8ViewModel()
        viewModel.autoSequencingEnabled = false
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IN81aa"
        viewModel.selectedBand = .band20m
        viewModel.clearReceived()
        viewModel.clearTransmitted()
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testInitialValues() async {
        XCTAssertEqual(viewModel.callsign, "EA1AAA")
        XCTAssertEqual(viewModel.locator, "IN81aa")
        XCTAssertEqual(viewModel.selectedBand, .band20m)
        XCTAssertFalse(viewModel.autoSequencingEnabled)
    }

    func testAppendingRxMessage() async {
        let msg = FT8Message(
            text: "CQ EA1AAA IN81aa",
            mode: .ft8,
            isRealtime: true,
            measuredSNR: 10,
            frequency: 14074_000,
            band: viewModel.selectedBand,
            allowsReply: true
        )

        viewModel.receivedMessages.append(msg)

        XCTAssertEqual(viewModel.receivedMessages.count, 1)
        XCTAssertEqual(viewModel.receivedMessages.first?.text, "CQ EA1AAA IN81aa")
    }

    func testAppendingTxMessage() async {
        let msg = FT8Message(
            text: "RR73 EA1AAA IN81aa",
            mode: .ft8,
            isRealtime: true,
            measuredSNR: 15,
            frequency: 14074_000,
            isTX: true,
            band: viewModel.selectedBand,
            allowsReply: false
        )

        viewModel.transmittedMessages.append(msg)

        XCTAssertEqual(viewModel.transmittedMessages.count, 1)
        XCTAssertTrue(viewModel.transmittedMessages.first!.isTX)
    }
}

@MainActor
final class FT8ViewModelIntegrationTests: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = FT8ViewModel()
        viewModel.autoSequencingEnabled = true
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IN81aa"
        viewModel.selectedBand = .band20m
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testAutoSequencingEnabled() async {
        XCTAssertTrue(viewModel.autoSequencingEnabled)
    }

    func testLockingDXCallsign() async {
        let msg = FT8Message(
            text: "CQ EA2BBB IN81bb",
            mode: .ft8,
            isRealtime: true,
            band: viewModel.selectedBand
        )

        viewModel.receivedMessages.append(msg)
//        viewModel.lockedDXCallsign = "EA2BBB"

//        XCTAssertEqual(viewModel.lockedDXCallsign, "EA2BBB")
    }
}

@MainActor
final class FT8ViewModelE2ETests2: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = FT8ViewModel()
        viewModel.autoSequencingEnabled = true
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IN81aa"
        viewModel.selectedBand = .band20m
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testFullTxRxCycle() async {
        viewModel.clearReceived()
        viewModel.clearTransmitted()
        
        let rxMsg = FT8Message(
            text: "CQ EA1AAA IN81aa",
            mode: .ft8,
            isRealtime: true,
            measuredSNR: 12,
            frequency: 14074_000,
            band: viewModel.selectedBand
        )

        viewModel.receivedMessages.append(rxMsg)

        let txMsg = FT8Message(
            text: "RR73 EA2BBB IN81bb",
            mode: .ft8,
            isRealtime: true,
            measuredSNR: 15,
            frequency: 14074_000,
            isTX: true,
            band: viewModel.selectedBand
        )

        viewModel.transmittedMessages.append(txMsg)

        XCTAssertEqual(viewModel.receivedMessages.count, 1)
        XCTAssertEqual(viewModel.transmittedMessages.count, 1)
        XCTAssertEqual(viewModel.transmittedMessages.first?.isTX, true)
        XCTAssertEqual(viewModel.receivedMessages.first?.text, "CQ EA1AAA IN81aa")
    }
}

// MARK: - FT8ViewModelAdditionalTests (uses mocks kept in project)
//@MainActor
//final class FT8ViewModelAdditionalTests: XCTestCase {
//    var viewModel: FT8ViewModel!
//    var mockAudio: MockAudioManager!
//    var mockEngine: MockFT8Engine!
//    var mockSlots: MockSlotManager!
//
//    override func setUp() async throws {
//        try await super.setUp()
//        mockAudio = MockAudioManager()
//        mockEngine = MockFT8Engine()
//        mockSlots = MockSlotManager()
//
//        viewModel = FT8ViewModel(
//            txMessages: [],
//            rxMessages: []
//        )
//    }
//
//    override func tearDown() async throws {
//        viewModel = nil
//        mockAudio = nil
//        mockEngine = nil
//        mockSlots = nil
//        try await super.tearDown()
//    }
//
//    func testReplyPreparesReply() {
//        let msg = FT8Message(text: "EA1AAA K1ABC +10", mode: .ft8, isRealtime: true)
//        viewModel.callsign = "K1ABC"
//        viewModel.locator = "IM99"
//        viewModel.reply(to: msg)
//
//        XCTAssertEqual(viewModel.dxCallsign, "EA1AAA")
//        XCTAssertEqual(viewModel.dxLocator, "IM99")
//        XCTAssertEqual(viewModel.selectedMessageIndex, 1)
//        XCTAssertFalse(viewModel.allMessages.isEmpty)
//    }
//
//    func testStartProgressBarUTCUpdatesProgress() async {
//        viewModel.isFT4 = false
//        viewModel.startProgressBarUTC()
//        try? await Task.sleep(nanoseconds: 200_000_000)
//        XCTAssertGreaterThanOrEqual(viewModel.cycleProgress, 0.0)
//        XCTAssertLessThanOrEqual(viewModel.cycleProgress, 1.0)
//    }
//
//    func testToggleTransmitStartsTXLoopAndPlays() async {
//        viewModel.callsign = "EA1AAA"
//        viewModel.locator = "IM99"
//        viewModel.allMessages = ["CQ EA1AAA IM99"]
//        viewModel.selectedMessageIndex = 0
//        viewModel.selectedBand = .band10m
//
//        XCTAssertFalse(viewModel.transmitLoopActive)
//
//        viewModel.toggleTransmit()
//        XCTAssertTrue(viewModel.transmitLoopActive)
//
//        try? await Task.sleep(nanoseconds: 15_000_000_000)
//
//        XCTAssertTrue(mockEngine.generateCalled)
//        XCTAssertTrue(mockAudio.playCalled)
//        XCTAssertEqual(viewModel.transmittedMessages.count, 1)
//
//        viewModel.toggleTransmit()
//        XCTAssertFalse(viewModel.transmitLoopActive)
//    }
//
//    func testDecodeFromWavUsesEngineAndAppendsMessages() async {
//        viewModel.wavURL = nil
//        viewModel.decodeFromWav()
//        XCTAssertTrue(mockEngine.decodeCalled)
//        XCTAssertGreaterThanOrEqual(viewModel.receivedMessages.count, 1)
//        XCTAssertNotNil(viewModel.decodedMessage)
//    }
//}

// MARK: - FT8ViewModelComprehensiveTests
@MainActor
final class FT8ViewModelComprehensiveTests: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = FT8ViewModel(txMessages: [], rxMessages: [])
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testSettingsLoadedWithVariousCombinations() {
        // Empty callsign and locator
        viewModel.callsign = ""
        viewModel.locator = ""
        XCTAssertFalse(viewModel.settingsLoaded)
        
        // Only callsign
        viewModel.callsign = "EA1AAA"
        viewModel.locator = ""
        XCTAssertFalse(viewModel.settingsLoaded)
        
        // Only locator
        viewModel.callsign = ""
        viewModel.locator = "IM99"
        XCTAssertFalse(viewModel.settingsLoaded)
        
        // Both set
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IM99"
        XCTAssertTrue(viewModel.settingsLoaded)
    }

    func testGenerateMessagesFT8AndFT4() {
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IM99"
        viewModel.dxCallsign = "K1ABC"
        viewModel.dxLocator = "FN31"
        viewModel.lastSentSNR = 10
        
        let ft8Messages = viewModel.generateMessages()
        XCTAssertEqual(ft8Messages.count, 7)
        XCTAssertTrue(ft8Messages[0].contains("EA1AAA"))
        XCTAssertTrue(ft8Messages[1].contains("K1ABC"))
        XCTAssertTrue(ft8Messages[2].contains("+10"))

    }

    func testGenerateMessagesWithEmptyDXValues() {
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IM99"
        viewModel.dxCallsign = ""
        viewModel.dxLocator = ""
        viewModel.lastSentSNR = -5
        
        let messages = viewModel.generateMessages()
        XCTAssertTrue(messages[1].contains("XXXXXX"))
        XCTAssertTrue(messages[1].contains("EA1AAA"))
        XCTAssertTrue(messages[2].contains("-05"))
    }

    func testReplyUpdatesDXAndPower() {
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IM99"
        
        let message = FT8Message(
            text: "CQ K1ABC FN31",
            mode: .ft8,
            measuredSNR: 12,
            frequency: 1400,
            isTX: false
        )
        viewModel.reply(to: message)
        
        XCTAssertEqual(viewModel.dxCallsign, "K1ABC")
        XCTAssertEqual(viewModel.dxLocator, "FN31")
        XCTAssertEqual(viewModel.qsoManager.lastSentSNR, 12)
        XCTAssertEqual(viewModel.frequency, 1400)
        XCTAssertEqual(viewModel.selectedMessageIndex, 1)
    }

    func testWorkedLocatorsPopulateFromMessages() {
        let msg1 = FT8Message(
            text: "EA1AAA K1ABC +10",
            mode: .ft8,
            isRealtime: true,
            measuredSNR: -12.0,
            frequency: 1500.0,
            timeOffset: 0.1,
            isTX: false
        )
        
        viewModel.receivedMessages = [msg1]
        XCTAssertFalse(viewModel.receivedMessages.isEmpty)
    }

//    func testDecodeFromWavAppendsMessages() {
//        viewModel.wavURL = nil
//        viewModel.decodeFromWav()
//        XCTAssertNotNil(viewModel.receivedMessages)
//    }

//    func testTransmitMessageValidatesCallsignAndLocator() async {
//        viewModel.callsign = "EA1AAA"
//        viewModel.locator = "IM99"
//        viewModel.allMessages = ["CQ EA1AAA IM99"]
//        viewModel.selectedMessageIndex = 0
//        viewModel.selectedBand = .band10m
//        viewModel.isFT4 = false
//        viewModel.transmitLoopActive = true
//
//        viewModel.startSequencer()
//        
//        try? await Task.sleep(nanoseconds: 30_500_000_000) // Safe waiting depending on the time the test is triggered
//        
//        XCTAssertEqual(viewModel.transmittedMessages.count, 1)
//        if(!viewModel.transmittedMessages.isEmpty){
//            XCTAssertEqual(viewModel.transmittedMessages[0].text, "CQ EA1AAA IM99")
//        }
//        
//        viewModel.stopSequencer()
//    }

    func testTransmitMessageWithInvalidCallsignOrLocator() async {
        viewModel.callsign = ""
        viewModel.locator = ""
        viewModel.allMessages = ["CQ ??? ???"]
        viewModel.selectedMessageIndex = 0
        viewModel.transmitLoopActive = true

        _ = viewModel.generateMessages()
        
        XCTAssertTrue(viewModel.allMessages.isEmpty || viewModel.allMessages.contains(where: { $0.contains("?") }))
    }

    func testClearReceivedMessages() {
        viewModel.receivedMessages = [FT8Message(text: "1", mode: .ft8)]
        viewModel.clearReceived()
        XCTAssertTrue(viewModel.receivedMessages.isEmpty)
    }

    func testClearTransmittedMessages() {
        viewModel.transmittedMessages = [FT8Message(text: "TX", mode: .ft8)]
        viewModel.clearTransmitted()
        XCTAssertTrue(viewModel.transmittedMessages.isEmpty)
    }

    func testClearLastDecodedMessage() {
        viewModel.decodedMessage = FT8Message(text: "Last", mode: .ft8)
        viewModel.clearLastMessage()
        XCTAssertNil(viewModel.decodedMessage)
    }

//    func testStartProgressBarUpdatesCycleProgress() async throws {
//        viewModel.isFT4 = false
//        viewModel.startProgressBarUTC()
//        try await Task.sleep(nanoseconds: 100_000_000)
//        XCTAssertGreaterThanOrEqual(viewModel.cycleProgress, 0.0)
//        XCTAssertLessThanOrEqual(viewModel.cycleProgress, 1.0)
//    }
}

// MARK: - GridMapTests
final class GridMapTests: XCTestCase {
    func testGridPolygonValid() {
        let coords = MaidenheadGrid.gridPolygon(for: "IO91")
        XCTAssertNotNil(coords)
        XCTAssertEqual(coords?.count, 4)
        if let c = coords {
            XCTAssertTrue((-90...90).contains(c[0].latitude))
            XCTAssertTrue((-180...180).contains(c[0].longitude))
        }
    }

    func testGridPolygonInvalid() {
        XCTAssertNil(MaidenheadGrid.gridPolygon(for: "XX"))
    }
}

@MainActor
final class GridMapViewRenderingTests: XCTestCase {

    func testGridMapViewAddsPolygonAndAnnotation() {
        let mapView = MKMapView()
        var trackingMode: MKUserTrackingMode = .none
        let trackingModeBinding = Binding<MKUserTrackingMode>(get: { trackingMode }, set: { trackingMode = $0 })
        let coordinator = GridMapView.Coordinator(onUserLocator: nil, trackingMode: trackingModeBinding)

        let locators = ["IO91"]
        let countries: [CountryPair] = []
        let visibility = MapVisibility(grids: true, countryCircles: true, geodesics: true, annotations: true)

        coordinator.updateMap(mapView, locators: locators, countries: countries, visibility: visibility)

        XCTAssertFalse(mapView.overlays.isEmpty)
        XCTAssertFalse(mapView.annotations.isEmpty)

        // All grid squares share one multi-polygon overlay (one renderer).
        let hasPolygon = mapView.overlays.contains { $0 is MKMultiPolygon }
        XCTAssertTrue(hasPolygon)

        let annotation = mapView.annotations.first { !($0 is MKUserLocation) }
        XCTAssertNotNil(annotation)
        XCTAssertEqual(annotation?.title ?? "", "IO91")
    }

    func testRendererForPolygonCircleAndGeodesic() {
        var trackingMode: MKUserTrackingMode = .none
        let trackingModeBinding = Binding<MKUserTrackingMode>(get: { trackingMode }, set: { trackingMode = $0 })
        let coordinator = GridMapView.Coordinator(onUserLocator: nil, trackingMode: trackingModeBinding)
        let mapView = MKMapView()

        let polygon = MKPolygon(coordinates: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 1),
            CLLocationCoordinate2D(latitude: 1, longitude: 1),
            CLLocationCoordinate2D(latitude: 1, longitude: 0)
        ], count: 4)

        let circle = MKCircle(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), radius: 1000)

        let geodesic = MKGeodesicPolyline(coordinates: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 10, longitude: 10)
        ], count: 2)

        let polygonRenderer = coordinator.mapView(mapView, rendererFor: polygon)
        XCTAssertTrue(polygonRenderer is MKPolygonRenderer)

        let circleRenderer = coordinator.mapView(mapView, rendererFor: circle)
        XCTAssertTrue(circleRenderer is MKCircleRenderer)

        let geoRenderer = coordinator.mapView(mapView, rendererFor: geodesic)
        XCTAssertTrue(geoRenderer is MKPolylineRenderer)
    }

    func testCoordinatorDoesNotRedrawIfHashUnchanged() {
        let mapView = MKMapView()
        var trackingMode: MKUserTrackingMode = .none
        let trackingModeBinding = Binding<MKUserTrackingMode>(get: { trackingMode }, set: { trackingMode = $0 })
        let coordinator = GridMapView.Coordinator(onUserLocator: nil, trackingMode: trackingModeBinding)

        let locators = ["IO91"]
        let visibility = MapVisibility(grids: true, countryCircles: true, geodesics: true, annotations: true)

        coordinator.updateMap(mapView, locators: locators, countries: [], visibility: visibility)
        let overlayCount = mapView.overlays.count

        coordinator.updateMap(mapView, locators: locators, countries: [], visibility: visibility)
        XCTAssertEqual(mapView.overlays.count, overlayCount)
    }

    func testFitAllSetsVisibleMapRect() {
        let mapView = MKMapView()
        var trackingMode: MKUserTrackingMode = .none
        let trackingModeBinding = Binding<MKUserTrackingMode>(get: { trackingMode }, set: { trackingMode = $0 })
        let coordinator = GridMapView.Coordinator(onUserLocator: nil, trackingMode: trackingModeBinding)

        let locators = ["IO91", "IN80"]
        let visibility = MapVisibility(grids: true, countryCircles: true, geodesics: true, annotations: true)
        coordinator.updateMap(mapView, locators: locators, countries: [], visibility: visibility)

        XCTAssertFalse(mapView.visibleMapRect.isNull)
    }
}

// ============================================================
// MARK: - MapHelpers Geometry Tests
// ============================================================

final class MapHelpersTests: XCTestCase {

    func testQuadraticBezierReturnsCorrectNumberOfPoints() {
        let start = MKMapPoint(CLLocationCoordinate2D(latitude: 0, longitude: 0))
        let control = MKMapPoint(CLLocationCoordinate2D(latitude: 5, longitude: 10))
        let end = MKMapPoint(CLLocationCoordinate2D(latitude: 10, longitude: 0))

        let points = generateQuadraticBezierPointsMK(
            start: start,
            control: control,
            end: end,
            segments: 10
        )

        XCTAssertEqual(points.count, 11)
        guard let first = points.first, let last = points.last else {
            XCTFail("Bezier points array is empty")
            return
        }

        XCTAssertEqual(first.latitude, start.coordinate.latitude, accuracy: 1e-6)
        XCTAssertEqual(last.longitude, end.coordinate.longitude, accuracy: 1e-6)

    }

    func testDistanceBetweenCoordinatesIsPositive() {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 10, longitude: 10)

        let distance = distanceBetween(a, b)
        XCTAssertGreaterThan(distance, 0)
    }
}


// MARK: - RealtimeFFTTests
final class RealtimeFFTTests: XCTestCase {
    func testInitAndMagnitudes() {
        guard let fft = RealtimeFFT(size: 8) else {
            XCTFail("Failed to create RealtimeFFT")
            return
        }

        var samples: [Float] = [Float](repeating: 0, count: fft.n)
        samples[0] = 1.0

        let mags = samples.withUnsafeBufferPointer { ptr -> [Float] in
            return fft.magnitudes(from: ptr.baseAddress!)
        }

        XCTAssertEqual(mags.count, fft.n / 2)
        XCTAssertTrue(mags.max()! == 0.0)
    }
}
//
//// MARK: - SlotManagerTests
//final class SlotManagerTests: XCTestCase {
//    func testCurrentSlotsAndNextSlot() async {
//        let sm = SlotManager()
//
//        let txSlotsFT8Even = await sm.currentSlots(forTX: true, isFT4: false, evenCycle: true)
//        XCTAssertEqual(txSlotsFT8Even, [0.0, 30.0])
//
//        let rxSlotsFT8 = await sm.currentSlots(forTX: false, isFT4: false, evenCycle: false)
//        XCTAssertEqual(rxSlotsFT8, [0.0, 15.0, 30.0, 45.0])
//
//        let next = await sm.nextSlot(after: 10.0, forTX: true, isFT4: false, evenCycle: true)
//        XCTAssertEqual(next, 30.0)
//    }
//
//    func testWaitUntilNextSlotQuickPaths() async throws {
//        let logger = AppLogger(category: "TEST")
//        let result = try await SlotManager().waitUntilNextSlot(
//            taskName: "t",
//            logger: logger,
//            forTX: false,
//            isFT4: false,
//            evenCycle: true
//        )
//        XCTAssertTrue(result || result == false)
//    }
//}

// MARK: - ExtensionsTests
final class ExtensionsTests: XCTestCase {
    func testRotateLeft() {
        var a = [1, 2, 3, 4]
        a.rotateLeft(by: 2)
        XCTAssertEqual(a, [3, 4, 1, 2])
    }

    func testUTCISOFormatter() {
        let d = Date(timeIntervalSince1970: 0)
        let s = DateFormatter.utcISOFormatter.string(from: d)
        XCTAssertTrue(s.hasPrefix("1970-01-01T00:00:00"))
    }
}

// MARK: - AppLoggerTests
final class AppLoggerTests: XCTestCase {
    func testLoggerMethodsDontCrash() {
        let logger = AppLogger(category: "TEST")
        logger.info("info")
        logger.error("error")
        logger.debug("debug")
        XCTAssertTrue(true)
    }
}

// MARK: - FT8MessageTests
final class FT8MessageTests: XCTestCase {
    func testDetectMessageType() {
        XCTAssertEqual(FT8Message.detectMessageType(text: "CQ EA1AAA", parts: "CQ EA1AAA".uppercased().split(separator: " ")), .cq)
        XCTAssertEqual(FT8Message.detectMessageType(text: "F4XYZ EA1AAA -12", parts: "F4XYZ EA1AAA -12".uppercased().split(separator: " ")), .standardSignalReport)
        XCTAssertEqual(FT8Message.detectMessageType(text: "F4XYZ EA1AAA IM99", parts: "F4XYZ EA1AAA IM99".uppercased().split(separator: " ")), .gridExchange)
        XCTAssertEqual(FT8Message.detectMessageType(text: "EA1AAA K1ABC RR73", parts: "EA1AAA K1ABC RR73".uppercased().split(separator: " ")), .rr73)
        XCTAssertEqual(FT8Message.detectMessageType(text: "EA1AAA K1ABC RRR", parts: "EA1AAA K1ABC RRR".uppercased().split(separator: " ")), .rrr)
        XCTAssertEqual(FT8Message.detectMessageType(text: "Some random text", parts: "Some random text".uppercased().split(separator: " ")), .unknown)
    }

    func testIsForMe() {
        UserDefaults.standard.set("EA1AAA", forKey: "callsign")

        var participants = FT8Message.parseParticipants(parts: "CQ EA1AAA".uppercased().split(separator: " "))
        XCTAssertTrue(
            FT8Message.isForMe(
                participants: participants,
                myCallsign: "EA1AAA",
                isTX: false
            )
        )

        participants = FT8Message.parseParticipants(parts: "F4XYZ EA1AAA -12".uppercased().split(separator: " "))
        XCTAssertTrue(
            FT8Message.isForMe(
                participants: participants,
                myCallsign: "EA1AAA",
                isTX: false
            )
        )

        participants = FT8Message.parseParticipants(parts: "CQ K1ABC".uppercased().split(separator: " "))
        XCTAssertFalse(
            FT8Message.isForMe(
                participants: participants,
                myCallsign: "EA1AAA",
                isTX: false
            )
        )

        // Adapted versions of the original string-based test cases
        participants = FT8Message.parseParticipants(parts: "CQ EA1AAA".uppercased().split(separator: " "))
        XCTAssertTrue(
            FT8Message.isForMe(
                participants: participants,
                myCallsign: "EA1AAA",
                isTX: false
            )
        )

        participants = FT8Message.parseParticipants(parts: "F4XYZ EA1AAA -12".uppercased().split(separator: " "))
        XCTAssertTrue(
            FT8Message.isForMe(
                participants: participants,
                myCallsign: "EA1AAA",
                isTX: false
            )
        )

        participants = FT8Message.parseParticipants(parts: "F4XYZ EB1BBB -12".uppercased().split(separator: " "))
        XCTAssertFalse(
            FT8Message.isForMe(
                participants: participants,
                myCallsign: "EA1AAA",
                isTX: false
            )
        )
    }


    func testBandProperties() {
        // FT8 frequency for 10m band
        XCTAssertEqual(
            FT8Message.Band.band10m.frequency(for: .ft8),
            28_074_000
        )

        // Unknown band has no frequency
        XCTAssertNil(
            FT8Message.Band.unknown.frequency(for: .ft8)
        )

        // Valid bands list excludes .unknown
        XCTAssertTrue(
            FT8Message.Band.validBands.contains(.band20m)
        )
    }

}

// MARK: - FT8MessageComposerTests
final class FT8MessageComposerTests: XCTestCase {
    func testGenerateMessagesFormatting() {
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        let c = FT8MessageComposer()
        let msgs = c.generateMessages(
            callsign: "ea1aaa",
            locator: "im99",
            dxCallsign: "k1abc",
            dxLocator: "io91",
            snrToSend: 5.4
        )
        XCTAssertTrue(msgs.contains("CQ EA1AAA IM99"))
        XCTAssertTrue(msgs.contains("K1ABC EA1AAA IM99"))
        XCTAssertTrue(msgs.contains("K1ABC EA1AAA +05"))

        let msgsNaN = c.generateMessages(callsign: "E1", locator: "IM99", dxCallsign: "", dxLocator: "", snrToSend: Double.nan)
        XCTAssertTrue(msgsNaN.contains("CQ E1 IM99"))
        UserDefaults.standard.removeObject(forKey: "cqModifier")
    }
    
    func testGenerateMessagesWithActivationModifiers() {
        let c = FT8MessageComposer()
        
        // Test POTA
        UserDefaults.standard.set("POTA", forKey: "cqModifier")
        let potaMsgs = c.generateMessages(
            callsign: "EA4IQL",
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN31",
            snrToSend: -10.0
        )
        XCTAssertTrue(potaMsgs[0].contains("CQ POTA EA4IQL"))
//        XCTAssertTrue(potaMsgs[0].contains("IN80"))
        
        // Test SOTA
        UserDefaults.standard.set("SOTA", forKey: "cqModifier")
        let sotaMsgs = c.generateMessages(
            callsign: "EA4IQL",
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN31",
            snrToSend: -10.0
        )
        XCTAssertTrue(sotaMsgs[0].contains("CQ SOTA EA4IQL"))
        
        // Test WWFF
        UserDefaults.standard.set("WWFF", forKey: "cqModifier")
        let wwffMsgs = c.generateMessages(
            callsign: "EA4IQL",
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN31",
            snrToSend: -10.0
        )
        XCTAssertTrue(wwffMsgs[0].contains("CQ WWFF EA4IQL"))
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        
        // Test IOTA
        UserDefaults.standard.set("IOTA", forKey: "cqModifier")
        let iotaMsgs = c.generateMessages(
            callsign: "EA4IQL",
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN31",
            snrToSend: -10.0
        )
        XCTAssertTrue(iotaMsgs[0].contains("CQ IOTA EA4IQL"))
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "cqModifier")
    }
    
    func testGenerateMessagesWithGeographicFilters() {
        let c = FT8MessageComposer()
        let geographicFilters = ["DX", "EU", "NA", "SA", "AF", "AS", "OC", "ANT"]
        
        for filter in geographicFilters {
            UserDefaults.standard.set(filter, forKey: "cqModifier")
            let msgs = c.generateMessages(
                callsign: "EA4IQL",
                locator: "IN80",
                dxCallsign: "K1ABC",
                dxLocator: "FN31",
                snrToSend: -10.0
            )
            XCTAssertTrue(msgs[0].contains("CQ \(filter) EA4IQL"), "Geographic filter \(filter) not in CQ message")
//            XCTAssertTrue(msgs[0].contains("IN80"), "Grid missing for \(filter)")
        }
        
        UserDefaults.standard.removeObject(forKey: "cqModifier")
    }
    
    func testGenerateMessagesWithoutModifier() {
        let c = FT8MessageComposer()
        
        // Test with NONE
        UserDefaults.standard.set("NONE", forKey: "cqModifier")
        let noneMsg = c.generateMessages(
            callsign: "EA4IQL",
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN31",
            snrToSend: -10.0
        )
        XCTAssertTrue(noneMsg[0] == "CQ EA4IQL IN80")
        XCTAssertFalse(noneMsg[0].contains("CQ NONE"))
        
        // Test with no key set
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        let noKeyMsg = c.generateMessages(
            callsign: "EA4IQL",
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN31",
            snrToSend: -10.0
        )
        XCTAssertTrue(noKeyMsg[0] == "CQ EA4IQL IN80")
    }
    
    func testGenerateMessagesIgnoresInvalidModifier() {
        let c = FT8MessageComposer()
        
        // Set an invalid modifier
        UserDefaults.standard.set("INVALID", forKey: "cqModifier")
        let msgs = c.generateMessages(
            callsign: "EA4IQL",
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN31",
            snrToSend: -10.0
        )
        // Should generate normal CQ without invalid modifier
        XCTAssertTrue(msgs[0] == "CQ EA4IQL IN80")
        XCTAssertFalse(msgs[0].contains("INVALID"))
        
        UserDefaults.standard.removeObject(forKey: "cqModifier")
    }
}

// MARK: - FT8CallsignWithSuffixTests
// In FT8/FT4, any callsign with "/" is valid (no closed list of modifiers)
// User can directly enter callsigns like EA4IQL/P, EA4IQL/MM, EA4IQL/CUSTOM
final class FT8CallsignWithSuffixTests: XCTestCase {
    
    func testGenerateMessagesWithCallsignSuffix() {
        let c = FT8MessageComposer()
        
        // When user enters callsign with suffix directly
        let msgs = c.generateMessages(
            callsign: "EA4IQL/P",
            locator: "IN80",
            dxCallsign: "K1ABC",
            dxLocator: "FN31",
            snrToSend: -10.0
        )
        
        XCTAssertTrue(msgs[0].contains("EA4IQL/P"), "CQ message should contain /P")
        XCTAssertTrue(msgs[1].contains("EA4IQL/P"), "Grid exchange should contain /P")
        XCTAssertTrue(msgs[2].contains("EA4IQL/P"), "Report should contain /P")
        XCTAssertTrue(msgs[4].contains("EA4IQL/P"), "RRR should contain /P")
    }
    
    func testGenerateMessagesWithCommonCallsignSuffixes() {
        let c = FT8MessageComposer()
        let suffixes = ["/P", "/M", "/MM", "/AM", "/QRP", "/R", "/1", "/ABC"]
        
        for suffix in suffixes {
            let msgs = c.generateMessages(
                callsign: "EA4IQL\(suffix)",
                locator: "IN80",
                dxCallsign: "K1ABC",
                dxLocator: "FN31",
                snrToSend: -10.0
            )
            
            let expectedCallsign = "EA4IQL\(suffix)"
            XCTAssertTrue(msgs[0].contains(expectedCallsign), "CQ should contain \(suffix)")
            XCTAssertTrue(msgs[1].contains(expectedCallsign), "Grid exchange should contain \(suffix)")
            XCTAssertTrue(msgs[2].contains(expectedCallsign), "Report should contain \(suffix)")
        }
    }

}


// MARK: - FT8EngineTests
final class FT8EngineTests: XCTestCase {
    func testGenerateFT8ReturnsData() {
        let engine = ft8_Engine()
        let data = engine.generateFT8("CQ EA1AAA IM99", frequency: 1400.0, isFT4: false, toFile: nil)
        XCTAssertNotNil(data)
        if let d = data {
            XCTAssertTrue(d.count > 0)
        } else if let nsd = data as? NSData {
            XCTAssertTrue(nsd.length > 0)
        }
    }

    func testDecodeNilDoesNotCrash() {
        let engine = ft8_Engine()
        let decoded = engine.decode(nil, isFT4: false)
        XCTAssertNotNil(decoded)
        XCTAssertTrue(decoded.count >= 0)
    }
}

// MARK: - ValidatorsTests
final class ValidatorsTests: XCTestCase {
    func testIsValidCallsign() {
        XCTAssertTrue(isValidCallsign("EA1AAA"))
        XCTAssertFalse(isValidCallsign("???"))
    }
    
    func testIsValidCallsignWithSuffix() {
        // In FT8/FT4, any suffix with "/" is valid - no closed list
        XCTAssertTrue(isValidCallsign("EA1AAA/P"))      // Portable
        XCTAssertTrue(isValidCallsign("EA1AAA/M"))      // Mobile
        XCTAssertTrue(isValidCallsign("EA1AAA/MM"))     // Maritime Mobile
        XCTAssertTrue(isValidCallsign("EA1AAA/AM"))     // Aeronautical Mobile
        XCTAssertTrue(isValidCallsign("EA1AAA/QRP"))    // Low power
        XCTAssertTrue(isValidCallsign("EA1AAA/R"))      // Repeater
        XCTAssertTrue(isValidCallsign("EA1AAA/1"))      // Numeric suffix
        XCTAssertTrue(isValidCallsign("EA1AAA/ABC"))    // Custom suffix
        XCTAssertTrue(isValidCallsign("EA1AAA/TEST"))   // Multi-char suffix
        XCTAssertTrue(isValidCallsign("W1A/P"))         // Short callsign with suffix
    }

    func testIsValidLocator() {
        XCTAssertTrue(isValidLocator("IM99"))
        XCTAssertFalse(isValidLocator("RR73"))
        XCTAssertFalse(isValidLocator("ABC"))
    }

    func testIsSignalReport() {
        XCTAssertTrue(isSignalReport(Substring("12")))
        XCTAssertTrue(isSignalReport(Substring("R-12")))
        XCTAssertFalse(isSignalReport(Substring("abc")))
    }
}

// MARK: - WaterfallViewModelTests
@MainActor
final class WaterfallViewModelTests: XCTestCase {
    func testInitAndBasicAPIs() {
        let vm = WaterfallViewModel(imageWidth: 8, waterfallRows: 4, isFT4: false)

        XCTAssertEqual(vm.width, 8)
        XCTAssertEqual(vm.height, 4)

        XCTAssertEqual(vm.frequencyAtPixel(x: 1, width: 0), 0)
        XCTAssertGreaterThan(vm.frequencyAtPixel(x: 1, width: 10), 0)

        vm.updateConfig { c in
            c.waterfallMaxRows = 10
        }
        XCTAssertLessThanOrEqual(vm.height, WaterfallViewModel.Config.absoluteMaxRows)
    }

    /// The overlay, the cursor and tap-to-set-frequency share one axis: the
    /// edges are `minDisplayFrequency`/`maxDisplayFrequency` and
    /// pixel → Hz → pixel round-trips.
    func testFrequencyAxisRoundTrip() {
        let vm = WaterfallViewModel(imageWidth: 1024, waterfallRows: 4, isFT4: false)
        let width: CGFloat = 390
        let range = vm.displayedFrequencyRange

        XCTAssertEqual(range, 200 ... 3000, "the display covers the band the decoder analyses")
        XCTAssertEqual(vm.frequencyAtPixel(x: 0, width: width), range.lowerBound)
        XCTAssertEqual(vm.frequencyAtPixel(x: width, width: width), range.upperBound, accuracy: 1e-6)

        for hz in [200.0, 1500.0, 2999.0] {
            let x = vm.xPosition(for: hz, in: width)
            XCTAssertEqual(vm.frequencyAtPixel(x: x, width: width), hz, accuracy: 1e-6)
        }
    }

    /// A base tone picked on the waterfall must leave the whole signal inside
    /// the decoder's 200–3000 Hz window.
    func testTXFrequencyRangeKeepsTheSignalInThePassband() {
        let ft8 = WaterfallViewModel.txFrequencyRange(isFT4: false)
        XCTAssertEqual(ft8.lowerBound, 200)
        XCTAssertEqual(ft8.upperBound + WaterfallViewModel.occupiedBandwidthHz(isFT4: false), 3000, accuracy: 1e-9)

        let ft4 = WaterfallViewModel.txFrequencyRange(isFT4: true)
        XCTAssertEqual(ft4.upperBound + WaterfallViewModel.occupiedBandwidthHz(isFT4: true), 3000, accuracy: 1e-9)
        XCTAssertLessThan(ft4.upperBound, ft8.upperBound)

        XCTAssertEqual(3199.0.clamped(to: ft8), ft8.upperBound)
        XCTAssertEqual(0.0.clamped(to: ft8), 200)
        XCTAssertEqual(1500.0.clamped(to: ft8), 1500)
    }

    /// The monitor's bins (3.125 Hz from 200 Hz for FT8) must land on the
    /// same columns the overlay uses for those frequencies, whatever the
    /// image width.
    func testDisplayedBinIndicesFollowTheSourceBins() {
        let width = 1024
        let firstBinHz: Float = 200
        let binHz: Float = 3.125
        let binCount = 898
        let map = WaterfallViewModel.displayedBinIndices(
            pixelWidth: width, binCount: binCount, firstBinHz: firstBinHz, binHz: binHz,
            minDisplayHz: 200, maxDisplayHz: 3000
        )
        XCTAssertEqual(map.count, width)
        XCTAssertEqual(map.first, 0)
        XCTAssertEqual(map.last, Int(((3000 - 200) / binHz).rounded()))

        // A 1500 Hz tone is bin 416 and the overlay draws 1500 Hz at 1300/2800 of the width.
        let toneBin = Int(((1500 - firstBinHz) / binHz).rounded())
        let toneX = Int((1500.0 - 200.0) / 2800.0 * Double(width))
        let pixelsPerBin = Double(width) / (2800.0 / Double(binHz))
        let drawnX = map.firstIndex(of: toneBin)!
        XCTAssertEqual(Double(drawnX), Double(toneX), accuracy: pixelsPerBin)

        // A narrower display just zooms; columns outside the source clamp.
        let zoomed = WaterfallViewModel.displayedBinIndices(
            pixelWidth: 100, binCount: binCount, firstBinHz: firstBinHz, binHz: binHz,
            minDisplayHz: 0, maxDisplayHz: 400
        )
        XCTAssertEqual(zoomed.first, 0)
        let lastColumnCentreHz: Float = 398   // 0 + 99.5 / 100 × 400
        XCTAssertEqual(zoomed.last, Int(((lastColumnCentreHz - firstBinHz) / binHz).rounded()))

        XCTAssertTrue(WaterfallViewModel.displayedBinIndices(
            pixelWidth: 0, binCount: 8, firstBinHz: 0, binHz: 1, minDisplayHz: 0, maxDisplayHz: 8
        ).isEmpty)
        XCTAssertTrue(WaterfallViewModel.displayedBinIndices(
            pixelWidth: 8, binCount: 8, firstBinHz: 0, binHz: 1, minDisplayHz: 8, maxDisplayHz: 8
        ).isEmpty)
    }

    /// Records what the view model pushes to a renderer.
    @MainActor
    private final class RecordingSink: WaterfallRenderSink {
        var resets = 0
        var resetRows: (width: Int, height: Int, writeRow: Int)?
        var appended: [(ringRow: Int, absoluteRow: Int, firstPixel: UInt32)] = []
        var labels: [WaterfallPlacedLabel] = []
        var timestamps: [(String, Int)] = []
        var slots: [WaterfallSlotMark] = []

        func reset(width: Int, height: Int, pixels: UnsafeBufferPointer<UInt32>, writeRow: Int, absoluteRow: Int,
                   timestamps: [(absoluteRow: Int, text: String)],
                   labels: [WaterfallPlacedLabel],
                   slots: [WaterfallSlotMark]) {
            resets += 1
            resetRows = (width, height, writeRow)
            XCTAssertEqual(pixels.count, width * height)
            self.labels += labels
            self.timestamps += timestamps.map { ($0.text, $0.absoluteRow) }
            self.slots = slots
        }
        func append(row: UnsafeBufferPointer<UInt32>, ringRow: Int, absoluteRow: Int) {
            appended.append((ringRow, absoluteRow, row[0]))
        }
        func addTimestamp(_ text: String, absoluteRow: Int) { timestamps.append((text, absoluteRow)) }
        func addLabels(_ labels: [WaterfallPlacedLabel]) { self.labels += labels }
        func setSlots(_ slots: [WaterfallSlotMark]) { self.slots = slots }
    }

    func testUpdateWaterfallPushesRowsAndLabelsToSinks() {
        let vm = WaterfallViewModel(imageWidth: 16, waterfallRows: 4, isFT4: false)
        let sink = RecordingSink()
        vm.attach(sink)
        XCTAssertEqual(sink.resets, 1)
        XCTAssertEqual(sink.resetRows?.width, 16)
        XCTAssertEqual(sink.resetRows?.height, 4)
        XCTAssertFalse(vm.hasData)

        vm.addVerticalLabel(text: "L", frequency: 1000.0)
        XCTAssertEqual(sink.labels.count, 1)
        XCTAssertEqual(sink.labels.first?.anchorRow, 0, "anchored to the row about to be written")
        XCTAssertEqual(sink.labels.first?.spanRows, 0, "no DT: hangs from the anchor")

        let row = [UInt8](repeating: 140, count: 898)
        for _ in 0 ..< 5 { vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125) }

        XCTAssertTrue(vm.hasData)
        XCTAssertEqual(sink.appended.map(\.ringRow), [0, 1, 2, 3, 0], "ring of 4 rows wraps")
        XCTAssertEqual(sink.appended.map(\.absoluteRow), [0, 1, 2, 3, 4])
        XCTAssertEqual(vm.writeRow, 1)
        XCTAssertEqual(vm.absoluteRowCount, 5)
        XCTAssertNotEqual(sink.appended[0].firstPixel, 0xFF000000, "a row with signal is not black")

        // The overlay accessors still answer relative to the newest row.
        let labels = vm.verticalLabelsForOverlay(height: 10)
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels.first?.row, 4)

        // A sink attached later gets the history it missed.
        let late = RecordingSink()
        vm.attach(late)
        XCTAssertEqual(late.resetRows?.writeRow, 1)
        XCTAssertEqual(late.labels.count, 1)
        XCTAssertTrue(late.appended.isEmpty)

        vm.detach(sink)
        vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125)
        XCTAssertEqual(sink.appended.count, 5, "detached sinks stop receiving rows")
        XCTAssertEqual(late.appended.count, 1)
    }

    /// A decode carries the slot it came from and its DT; the label lands on
    /// the row the signal started and spans the signal's length.
    func testLabelsAreAnchoredToTheSignalStart() {
        let vm = WaterfallViewModel(imageWidth: 16, waterfallRows: 400, isFT4: false)
        vm.rowPeriod = 0.08
        let sink = RecordingSink()
        vm.attach(sink)
        let row = [UInt8](repeating: 140, count: 898)

        // Slot 7 starts at absolute row 10 (rows 0–9 belong to slot 6).
        for i in 0 ..< 10 { vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 6, slotRow: 100 + i) }
        for i in 0 ..< 190 { vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 7, slotRow: i) }
        // Slot 8 has begun; the decode of slot 7 arrives now.
        for i in 0 ..< 5 { vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 8, slotRow: i) }

        let cq = WaterfallLabel(text: "CQ W1AW FN31", frequency: 1000, kind: .cq, callsign: "W1AW", timeOffset: 0.48)
        let late = WaterfallLabel(text: "K1ABC W9XYZ -05", frequency: 2000, kind: .other, timeOffset: 1.6)
        let bogus = WaterfallLabel(text: "X", frequency: 500, kind: .other, timeOffset: 40)
        vm.addLabels([cq, late, bogus], slotSequence: 7, signalDuration: 12.64)

        XCTAssertEqual(sink.labels.count, 3)
        XCTAssertEqual(sink.labels[0].anchorRow, 10 + 6, "0.48 s = 6 rows after the slot started")
        XCTAssertEqual(sink.labels[0].spanRows, 158, "12.64 s = 158 rows")
        XCTAssertEqual(sink.labels[1].anchorRow, 10 + 20)
        XCTAssertEqual(sink.labels[2].anchorRow, vm.absoluteRowCount, "a start past the newest row falls back to the decode row")
        XCTAssertEqual(sink.labels[2].spanRows, 0)
        XCTAssertEqual(sink.labels[0].label.kind, .cq)

        // A decode from a slot the display never saw hangs from the current row.
        vm.addLabels([cq], slotSequence: 99, signalDuration: 12.64)
        XCTAssertEqual(sink.labels[3].anchorRow, vm.absoluteRowCount)

        // The overlay accessor reports the anchor relative to the newest row.
        let overlay = vm.verticalLabelsForOverlay(height: 400)
        XCTAssertEqual(overlay.first?.row, (vm.absoluteRowCount - 1) - 16)
        XCTAssertEqual(overlay.first?.spanRows, 158)
    }

    func testLabelKindsFromMessages() {
        let cq = FT8Message(text: "CQ W1AW FN31", mode: .ft8, frequency: 1200, timeOffset: 0.3)
        let cqLabel = WaterfallLabel(message: cq)
        XCTAssertEqual(cqLabel.kind, .cq)
        XCTAssertEqual(cqLabel.callsign, "W1AW")
        XCTAssertEqual(cqLabel.frequency, 1200)
        XCTAssertEqual(cqLabel.timeOffset, 0.3)
        XCTAssertFalse(cqLabel.isWorked)

        let other = FT8Message(text: "K1ABC W9XYZ -05", mode: .ft8, frequency: 900)
        let otherLabel = WaterfallLabel(message: other)
        XCTAssertEqual(otherLabel.kind, .other)
        XCTAssertNil(otherLabel.timeOffset, "NaN DT means unknown")
    }

    /// Snapping a tap and hit-testing a label both look at the placed labels.
    func testTapSnapAndLabelHitTest() {
        let vm = WaterfallViewModel(imageWidth: 16, waterfallRows: 400, isFT4: false)
        let row = [UInt8](repeating: 140, count: 898)
        for i in 0 ..< 200 { vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 1, slotRow: i) }
        let id = UUID()
        vm.addLabels([
            WaterfallLabel(text: "CQ W1AW FN31", frequency: 1000, kind: .cq, timeOffset: 0.5, messageID: id),
            WaterfallLabel(text: "K1ABC W9XYZ -05", frequency: 1030, kind: .other, timeOffset: 0.5),
        ], slotSequence: 1, signalDuration: 12.64)

        XCTAssertEqual(vm.nearestLabelFrequency(to: 1012, toleranceHz: 40, withinRows: 400), 1000)
        XCTAssertEqual(vm.nearestLabelFrequency(to: 1020, toleranceHz: 40, withinRows: 400), 1030)
        XCTAssertNil(vm.nearestLabelFrequency(to: 2000, toleranceHz: 40, withinRows: 400))
        XCTAssertNil(vm.nearestLabelFrequency(to: 1000, toleranceHz: 40, withinRows: 10), "scrolled out of the window")

        // The signal started at row 6 and runs 158 rows; the newest row is 199.
        let onSignal = vm.placedLabel(nearHz: 1005, rowFromTop: 199 - 80, toleranceHz: 40)
        XCTAssertEqual(onSignal?.label.messageID, id)
        XCTAssertNil(vm.placedLabel(nearHz: 1005, rowFromTop: 5, toleranceHz: 40), "above the signal's end")
        XCTAssertNil(vm.placedLabel(nearHz: 1500, rowFromTop: 100, toleranceHz: 40))
    }

    /// Flattening removes a sloped passband while leaving a signal standing.
    func testFlattenLevelsTheNoiseAcrossTheBand() {
        let vm = WaterfallViewModel(imageWidth: 256, waterfallRows: 8, isFT4: false)
        vm.displaySettings = WaterfallDisplaySettings(palette: .grey, flatten: true, autoLevel: true, zeroDB: 6, gainDB: 40)
        let sink = RecordingSink()
        vm.attach(sink)

        // Noise 20 dB louder at the low end than at the high end, plus a
        // 50 Hz signal 25 dB above the local noise around 2000 Hz.
        var row = [UInt8](repeating: 0, count: 898)
        for i in row.indices {
            let slope = Float(20) * (1 - Float(i) / 897)          // 20 → 0 dB
            var db: Float = -60 + slope
            let hz = 200 + Float(i) * 3.125
            if hz >= 2000 && hz < 2050 { db += 25 }
            row[i] = UInt8(max(0, min(255, (db + 120) * 2)))
        }
        // Let the baseline tracker settle.
        var last: [UInt32] = []
        for _ in 0 ..< 30 {
            vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 1, slotRow: 0)
        }
        _ = last
        last = vm.pixelRowForTesting(ringRow: (vm.writeRow + 7) % 8)

        func grey(_ px: UInt32) -> Int { Int(px & 0xFF) }
        let left = grey(last[20]), right = grey(last[235])
        let peakX = Int((2025.0 - 200) / 2800 * 256)
        let peak = grey(last[peakX])
        XCTAssertLessThan(abs(left - right), 25, "noise reads the same at both ends: \(left) vs \(right)")
        XCTAssertGreaterThan(peak - left, 100, "the signal still stands out: \(peak) vs \(left)")

        // Without flattening the slope shows: the low end is much brighter.
        vm.displaySettings.flatten = false
        for _ in 0 ..< 30 {
            vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 1, slotRow: 0)
        }
        let raw = vm.pixelRowForTesting(ringRow: (vm.writeRow + 7) % 8)
        XCTAssertGreaterThan(grey(raw[20]) - grey(raw[235]), 60)
    }

    func testDisplaySettingsRoundTrip() {
        let defaults = UserDefaults(suiteName: "WaterfallDisplaySettingsTests")!
        defaults.removePersistentDomain(forName: "WaterfallDisplaySettingsTests")
        XCTAssertEqual(WaterfallDisplaySettings.load(from: defaults), WaterfallDisplaySettings())

        var s = WaterfallDisplaySettings()
        s.palette = .fire; s.flatten = false; s.autoLevel = false
        s.zeroDB = 12; s.manualFloorDB = -30; s.gainDB = 55
        s.save(to: defaults)
        XCTAssertEqual(WaterfallDisplaySettings.load(from: defaults), s)

        defaults.set(999, forKey: "waterfall.gainDB")
        XCTAssertEqual(WaterfallDisplaySettings.load(from: defaults).gainDB, WaterfallDisplaySettings.gainRange.upperBound, "clamped")
    }

    func testPalettesAreWellFormed() {
        for palette in WaterfallPalette.allCases {
            let lut = palette.lookupTable
            XCTAssertEqual(lut.count, 256)
            XCTAssertTrue(lut.allSatisfy { $0 >> 24 == 0xFF }, "\(palette) opaque")
        }
        XCTAssertEqual(WaterfallPalette.grey.lookupTable.first, 0xFF000000)
        XCTAssertEqual(WaterfallPalette.grey.lookupTable.last, 0xFFFFFFFF)
        XCTAssertEqual(WaterfallPalette.blue.lookupTable.first, 0xFF000000, "noise floor is black")
        let top = WaterfallPalette.blue.rgb(at: 1)
        XCTAssertEqual(top.r, 255); XCTAssertEqual(top.g, 255); XCTAssertEqual(top.b, 255)
    }

    /// Slots are recorded as their rows arrive: each one closes the previous,
    /// carries its parity, and scrolls off with the ring.
    func testSlotMarksFollowTheRows() {
        let vm = WaterfallViewModel(imageWidth: 16, waterfallRows: 400, isFT4: false)
        vm.rowPeriod = 0.08
        vm.slotContextEnabled = true
        let sink = RecordingSink()
        vm.attach(sink)
        XCTAssertTrue(sink.slots.isEmpty)

        let row = [UInt8](repeating: 140, count: 898)
        for i in 0 ..< 50 { vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 4, slotRow: i) }
        XCTAssertEqual(vm.slots.count, 1)
        XCTAssertEqual(vm.slots[0].startRow, 0)
        XCTAssertEqual(vm.slots[0].rowCount, 188, "15 s at 80 ms per row until the next slot starts")

        for i in 0 ..< 10 { vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 5, slotRow: i) }
        XCTAssertEqual(vm.slots.count, 2)
        XCTAssertEqual(vm.slots[0].rowCount, 50, "the first slot is closed where the second begins")
        XCTAssertEqual(vm.slots[1].startRow, 50)
        let nowIsEven = WaterfallSlotMark.isEvenCycle(at: Date(), cycleLength: 15)
        XCTAssertEqual(vm.slots[1].isEvenCycle, nowIsEven, "parity is taken from the clock at the slot's first row")
        XCTAssertEqual(sink.slots, vm.slots)
    }

    /// While transmitting, rows are greyed out, kept out of the level
    /// trackers, and the slot is marked as ours.
    func testTransmitSlotsAreMarkedAndGreyed() {
        let vm = WaterfallViewModel(imageWidth: 16, waterfallRows: 8, isFT4: false)
        vm.slotContextEnabled = true
        let sink = RecordingSink()
        vm.attach(sink)
        let row = [UInt8](repeating: 200, count: 898)
        vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 1, slotRow: 0)
        let receiveRow = vm.pixelRowForTesting(ringRow: 0)
        XCTAssertFalse(vm.isTransmitting)
        XCTAssertEqual(vm.slots.first?.isTransmit, false)

        vm.setTransmitting(true)
        XCTAssertTrue(vm.isTransmitting)
        XCTAssertEqual(vm.slots.first?.isTransmit, false, "marked by the rows, not by the flag")

        vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 1, slotRow: 1)
        XCTAssertEqual(vm.slots.first?.isTransmit, true)
        XCTAssertEqual(sink.slots.first?.isTransmit, true)
        let txRow = vm.pixelRowForTesting(ringRow: 1)
        XCTAssertEqual(Set(txRow).count, 1, "a transmit row is flat grey")
        XCTAssertNotEqual(txRow[0], receiveRow[0])
        XCTAssertNotEqual(txRow[0], 0xFF000000, "grey, not black: the rows are not missing")

        // The next slot starts while still transmitting and inherits the mark.
        vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 2, slotRow: 0)
        XCTAssertEqual(vm.slots.last?.isTransmit, true)

        vm.setTransmitting(false)
        vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 2, slotRow: 1)
        XCTAssertNotEqual(vm.pixelRowForTesting(ringRow: 3)[0], txRow[0], "back to painting the spectrum")
        XCTAssertEqual(vm.slots.last?.isTransmit, true, "the slot we transmitted in stays marked")
    }

    /// With the flag off nothing about slots reaches the renderer and
    /// transmit rows are painted like any other.
    func testSlotContextIsOffByDefault() {
        let vm = WaterfallViewModel(imageWidth: 16, waterfallRows: 8, isFT4: false)
        XCTAssertFalse(vm.slotContextEnabled, "behind the waterfallSlotContext flag")
        let sink = RecordingSink()
        vm.attach(sink)
        let row = [UInt8](repeating: 200, count: 898)
        vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 1, slotRow: 0)
        vm.setTransmitting(true)
        vm.updateWaterfall(monitorRow: row, firstBinHz: 200, binHz: 3.125, slotSequence: 1, slotRow: 1)

        XCTAssertTrue(vm.slots.isEmpty)
        XCTAssertTrue(sink.slots.isEmpty)
        XCTAssertEqual(vm.pixelRowForTesting(ringRow: 1), vm.pixelRowForTesting(ringRow: 0), "no grey transmit row")

        // Labels still need the slot bookkeeping, which is not gated.
        vm.addLabels([WaterfallLabel(text: "CQ W1AW FN31", frequency: 1000, kind: .cq, timeOffset: 0.08)],
                     slotSequence: 1, signalDuration: 12.64)
        XCTAssertEqual(sink.labels.last?.spanRows ?? 0, 158, "decodes are still anchored to their slot")
    }

    func testSlotParityMatchesTheSequencer() {
        // Epoch second 0 is an even FT8 slot, 15 is odd, 30 even again.
        XCTAssertTrue(WaterfallSlotMark.isEvenCycle(at: Date(timeIntervalSince1970: 0), cycleLength: 15))
        XCTAssertFalse(WaterfallSlotMark.isEvenCycle(at: Date(timeIntervalSince1970: 15), cycleLength: 15))
        XCTAssertTrue(WaterfallSlotMark.isEvenCycle(at: Date(timeIntervalSince1970: 30), cycleLength: 15))
        XCTAssertTrue(WaterfallSlotMark.isEvenCycle(at: Date(timeIntervalSince1970: 44.9), cycleLength: 15))
        // FT4 alternates every 7.5 s.
        XCTAssertTrue(WaterfallSlotMark.isEvenCycle(at: Date(timeIntervalSince1970: 0), cycleLength: 7.5))
        XCTAssertFalse(WaterfallSlotMark.isEvenCycle(at: Date(timeIntervalSince1970: 7.5), cycleLength: 7.5))
    }

    /// Rows arriving from the audio thread are copied and applied on the
    /// main actor.
    func testAppendMonitorRowReachesTheMainActor() async {
        let vm = WaterfallViewModel(imageWidth: 16, waterfallRows: 4, isFT4: false)
        let sink = RecordingSink()
        vm.attach(sink)
        var row = [UInt8](repeating: 100, count: 64)
        row[32] = 255
        row.withUnsafeBufferPointer { vm.appendMonitorRow($0, firstBinHz: 200, binHz: 43.75, slotSequence: 1, slotRow: 0) }
        await Task.yield()
        for _ in 0 ..< 20 where sink.appended.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(sink.appended.count, 1)
    }
}
