//
//  FT8ViewModel.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import Accelerate
import Combine
import CoreLocation
import Foundation
import SwiftUI
import os.signpost
import os.lock
import UserNotifications

// MARK: - Performance Monitoring
private let performanceLog = OSLog(subsystem: "com.ft8ham.app", category: "Performance")

// MARK: - ViewModel
@MainActor
final class FT8ViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate, CLLocationManagerDelegate {
    
    // MARK: - Location Manager
    private let locationManager = CLLocationManager()
    private var lastUserLocator: String?
    
    // MARK: - Constants
    internal enum Constants {
        static let sampleRate: Double = 12000
        static let waterfallFFTSize = 2048
        static let waterfallRows = 1200
        static let throttleInterval = 150
        static let modeTransitionDelay: UInt64 = 200_000_000
        static let driftThreshold = 0.01
        
        static let ft8SignalDuration: Double = 12.6
        static let ft4SignalDuration: Double = 4.5

        // Maximum allowed TX start offset (seconds) from slot start.
        // Values chosen to preserve effective SNR
        static let ft8MaxStartOffset: Double = 2.4
        static let ft4MaxStartOffset: Double = 0.8
        
        static let ft8DecodeMargin: Double = 0.2
        static let ft4DecodeMargin: Double = 0.1
        
        static let txSafetyOffset: Double = 0.05
    }
    
    private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    internal let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    
    // MARK: - Dependencies
    internal let messageComposer = FT8MessageComposer()
    let audioManager: AudioManager
    internal let slotManager = SlotManager()
    internal let engine = ft8_Engine()
    internal let messageProcessor = MessageProcessor()
    internal let logbookManager = LogbookManager()
    
    let waterfallVM: WaterfallViewModel
    
    // MARK: - State Management
    internal var cancellables = Set<AnyCancellable>()
    
    // MARK: - Sequencer Task (Single Heartbeat)
    var sequencerTask: Task<Void, Never>?
    var isSequencerRunning = false
    internal var progressTimerCancellable: AnyCancellable?
    internal var isHarvestingRX = false

    internal var rxSampleBuffer = Data()
    internal let rxBufferLock = NSLock()
    
    var lastTransmittedSlotIndex: Int?
    var pendingTXMessageVersion: Int = 0
    var lastHandledTXMessageVersion: Int = 0
    
    private var hasLoadedLogbook = false
    
    // MARK: - TX Retry Control (Added)
    
    var currentTXRetryCount: Int = 0
    var lastTXVersionRetried: Int?
    
    // MARK: - QSO Manager
    @Published private(set) var qsoManager = QSOStatusManager()
    internal var activeTXMessage: FT8Message?
    
    // MARK: - Loggers
    let rxLogger = AppLogger(category: "RX")
    let txLogger = AppLogger(category: "TX")
    internal let appLogger = AppLogger(category: "APP")
    
    // MARK: - Published Properties
    @Published var decodedMessage: FT8Message?
    @Published var receivedMessages: [FT8Message] = []
    @Published var transmittedMessages: [FT8Message] = []
    @Published var qsoList: [LogEntry] = []
    @Published var audioError: String?
    @Published var adifURL: URL?
    
    @Published var isListening = false
    @Published var isTransmitting = false
    @Published var transmitLoopActive = false
    @Published var wavURL: URL?
    
    @Published var isReadyForTX = false
    @MainActor
    private var readyForTXContinuation: CheckedContinuation<Void, Never>?
    internal var firstLoopRX = true
    
    // MARK: - Worked Locators & Countries
    internal var workedLocatorsSet: Set<String> = []
    @Published var workedLocators: [String] = [] {
        didSet { workedLocatorsSet = Set(workedLocators) }
    }
    
    internal var workedCountryPairsSet: Set<CountryPair> = []
    
    @Published var workedCountryPairs: [CountryPair] = [] {
        didSet { workedCountryPairsSet = Set(workedCountryPairs) }
    }
    
    
    @Published var dxCallsign = ""
    @Published var dxLocator = ""
    @Published var lastReceivedSNR: Double = .nan
    @Published var lastSentSNR: Double = .nan
    
    
    @Published var allMessages: [String] = [""]
    @Published var selectedMessageIndex: Int? = 0 {
        didSet {
            if oldValue != selectedMessageIndex {
                appLogger.debug("selectedMessageIndex changed: \(String(describing: oldValue)) → \(String(describing: selectedMessageIndex))")
            }
        }
    }
    @Published var cycleProgress: Double = 0

    // MARK: - Message Caching
    internal var cachedMessages: [String]?
    internal var lastMessageParams: MessageParams?
    private var lastGeneratedMessageParams: MessageParams?

    // MARK: - QSO Logger
    internal var logAction: ((LogEntry) -> Void)?
    @Published internal var showConfirmQSOAlert: Bool = false
    @Published internal var pendingQSOToLog: LogEntry?
    
    
    // MARK: - AppStorage Properties
    @AppStorage("viewType") var selectedViewMode = ViewMode.vertical
    @AppStorage("autoRXAtStart") var autoRXAtStart = false
    @AppStorage("autoSequencingEnabled") var autoSequencingEnabled: Bool = true
    @AppStorage("decodeSelfTXMessages") var decodeSelfTXMessages: Bool = false
    @AppStorage("autoCQReplyEnabled") var autoCQReplyEnabled: Bool = false
    @AppStorage("maxRetrySlots") var maxRetrySlots: Int = 3
    @AppStorage("autoQSOLogging") var autoQSOLogging: Bool = true
    @AppStorage("holdTXFrequency") var holdTXFrequency: Bool = false
    
    @AppStorage("callsign") var callsign = ""
    @AppStorage("locator") var locator = ""

    @AppStorage("frequency") private var _frequency = 1500.0
    
    enum TXSlotPreference {
        case followClock
        case forceEven
        case forceOdd
    }
    
    @MainActor
    var txSlotPreference: TXSlotPreference = .followClock {
        didSet { evenCycle = (txSlotPreference == .forceEven) ? true : false }
    }
    
    var frequency: Double {
        get { _frequency }
        set { _frequency = min(max(0, newValue), 3000) }
    }
    
    @AppStorage("isFT4") var isFT4 = false {
        didSet {
            waterfallVM.mode = isFT4 ? .ft4 : .ft8
            restartLoopsForModeChange()
        }
    }
    
    internal func restartLoopsForModeChange() {
        guard isSequencerRunning else { return }
        restartSequencer()
    }

    @AppStorage("evenCycle") var evenCycle = true
    
    @AppStorage("band") private var selectedBandRaw = FT8Message.Band.band10m.rawValue
    var selectedBand: FT8Message.Band {
        get { FT8Message.Band(rawValue: selectedBandRaw) ?? .band10m }
        set { selectedBandRaw = newValue.rawValue }
    }
    
    @AppStorage("inputGain") var inputGain = 1.0 {
        didSet {
            let clamped = min(max(inputGain, 0.1), 2.0)
            let gainToSet = clamped != inputGain ? clamped : inputGain
            if gainToSet != inputGain { inputGain = gainToSet }
            audioManager.setInputGain(gainToSet)
        }
    }
    
    // MARK: - Computed Properties
    var settingsLoaded: Bool {
        !callsign.isEmpty && isValidCallsign(callsign) &&
        !locator.isEmpty && isValidLocator(locator)
    }
    
    // MARK: - Initialization
    init(txMessages: [FT8Message] = [], rxMessages: [FT8Message] = []) {
        
        let savedGain = UserDefaults.standard.value(forKey: "inputGain") as? Double ?? 0.3
        
        audioManager = AudioManager(
            waterfallFFTSize: Constants.waterfallFFTSize,
            sampleRate: Constants.sampleRate,
            initialGain: savedGain
        )
        
        let savedBandRaw = UserDefaults.standard.string(forKey: "band") ?? FT8Message.Band.band10m.rawValue
        let storedIsFT4 = UserDefaults.standard.bool(forKey: "isFT4")
        
        waterfallVM = WaterfallViewModel(
            sampleRate: Float(Constants.sampleRate),
            waterfallFFTSize: Constants.waterfallFFTSize,
            waterfallRows: Constants.waterfallRows,
            isFT4: storedIsFT4
        )
        
        super.init()
        
        self.selectedBandRaw = selectedBand.rawValue
        self.selectedBand = FT8Message.Band(rawValue: savedBandRaw) ?? .band10m
        self.isFT4 = storedIsFT4
        self.lastReceivedSNR = 0
        
        setupLogbook()
        setupAudioSubscriptions()
        setupQSOSubscriptions()
        setupMessageRefreshSubscriptions()
        setupPreviewData()
        configureLocationManager()
        
        refreshMessagesIfNeeded(reason: "initial load")
    }
    
    @MainActor
    private func setupLogbook() {
        if !hasLoadedLogbook {
            self.qsoList = logbookManager.loadEntries()
            self.adifURL = logbookManager.saveInternalLog(self.qsoList) ?? logbookManager.getEmptyADIFURL()
            hasLoadedLogbook = true
        }

        $qsoList
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self else { return }
                _ = self.logbookManager.saveInternalLog(list)
            }
            .store(in: &cancellables)
        
        workedLocators = []
    }
    
    @MainActor
    private func setupPreviewData() {
        if isPreview {
            receivedMessages = PreviewMocks.rxMessages
            transmittedMessages = PreviewMocks.txMessages
            
            extractWorkedLocators(from: PreviewMocks.rxMessages)
            extractWorkedCountryPairs(from: PreviewMocks.rxMessages)
            
            qsoList = PreviewMocks.qsoList
        }
    }
    
    @MainActor
    private func setupMessageRefreshSubscriptions() {
        let userDefaultsChanges = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .map { _ in () }
            .eraseToAnyPublisher()

        let dxCallsignChanges = $dxCallsign
            .map { _ in () }
            .eraseToAnyPublisher()

        let dxLocatorChanges = $dxLocator
            .map { _ in () }
            .eraseToAnyPublisher()

        let lastSentSNRChanges = $lastSentSNR
            .map { _ in () }
            .eraseToAnyPublisher()

        Publishers.MergeMany([
            userDefaultsChanges,
            dxCallsignChanges,
            dxLocatorChanges,
            lastSentSNRChanges
        ])
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refreshMessagesIfNeeded(reason: "message-relevant state changed")
        }
        .store(in: &cancellables)
    }
    
    // MARK: - Private Helper for Message Refresh
    private func refreshMessagesIfNeeded(reason: String) {
        guard settingsLoaded else {
            appLogger.info("Skipping message refresh due to invalid settings")
            return
        }

        let currentParams = MessageParams(
            callsign: callsign,
            locator: locator,
            dxCallsign: dxCallsign,
            dxLocator: dxLocator,
            snrToSend: lastSentSNR,
            cqModifier: UserDefaults.standard.string(forKey: "cqModifier") ?? "NONE"
        )

        if let lastParams = lastGeneratedMessageParams, lastParams == currentParams {
            return
        }

        appLogger.info("Regenerating messages due to: \(reason)")
        allMessages = generateMessages()
        // Only reset message index if we're not in an active QSO
        // During QSO, regeneration happens (e.g., power updates) but we should preserve
        // the selected message that was chosen for the current transmission
        if qsoManager.qsoState.lockedCallsign == nil {
            selectedMessageIndex = 0
        }
        lastGeneratedMessageParams = currentParams
    }


    @MainActor
    internal func handleTXDidFinishFromAudioManager() {
        guard let txMessage = activeTXMessage else {
            txLogger.debug("TX finished but no active TX message tracked")
            return
        }

        activeTXMessage = nil  

        txLogger.info("TX finished (AudioManager): \(txMessage.text)")
        AnalyticsManager.shared.stopRadioActivity() 
        
        if let action = qsoManager.advanceStateOnTX(
            message: txMessage,
            frequency: frequency,
            band: selectedBand,
            isFT4: isFT4
        ) {
            handleRXAction(action)
        }
    }

    // MARK: - Logbook Clearing
    @MainActor
    func clearLogbookConfirmed() {
        appLogger.info("User confirmed logbook clear")
        
        qsoList.removeAll()
        logbookManager.clearLogbook()
        adifURL = logbookManager.saveInternalLog([])
    }

    // MARK: - Location Manager Setup
    @MainActor
    func configureLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        
        // Check current authorization status
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            // Request authorization
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            // Already authorized, start updates
            locationManager.startUpdatingLocation()
            appLogger.info("Location services authorized, starting updates")
        case .denied, .restricted:
            appLogger.warning("Location services not authorized: \(status.rawValue)")
        @unknown default:
            appLogger.warning("Unknown location authorization status")
        }
    }

    // MARK: - CLLocationManagerDelegate
    @MainActor
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        appLogger.info("Location authorization changed to: \(status.rawValue)")
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            appLogger.info("Starting location updates after authorization")
        case .denied, .restricted:
            appLogger.warning("Location access denied or restricted")
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
    
    @MainActor
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let newLocator = MaidenheadGrid.locator(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            precision: 4
        )

        // Avoid unnecessary updates
        guard newLocator != lastUserLocator else { return }
        lastUserLocator = newLocator

        // Update the stored locator
        if self.locator != newLocator {
            self.locator = newLocator
            appLogger.info("Updated locator to: \(newLocator) from GPS location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }

    @MainActor
    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        appLogger.warning("Location manager error: \(error.localizedDescription)")
    }

    // MARK: - Deinitialization
    deinit {
        sequencerTask?.cancel()
        cancellables.removeAll()
        audioManager.cleanup()
        locationManager.stopUpdatingLocation()
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

}

