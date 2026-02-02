//
//  QSOManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 1/1/26.
//

import Foundation
import Combine
import os.log

// MARK: - Internal QSO State Machine

enum QSOState: Equatable {
    case idle, callingCQ
    case sendingGrid(dxCallsign: String)
    case sendingReport(dxCallsign: String), listeningReport(dxCallsign: String)
    case sendingRReport(dxCallsign: String), listeningRReport(dxCallsign: String)
    case sendingRRR(dxCallsign: String), listeningRRR(dxCallsign: String)
    case sending73(dxCallsign: String)
    // completed is a UI-visible terminal state.
    // Operational state is already reset and ready for a new QSO.
    case completed(dxCallsign: String), timeout(dxCallsign: String)

    var lockedCallsign: String? {
        switch self {
        case .sendingGrid(let dx),
             .sendingReport(let dx), .listeningReport(let dx),
             .sendingRReport(let dx), .listeningRReport(let dx),
             .sendingRRR(let dx), .listeningRRR(let dx),
             .sending73(let dx),
             .completed(let dx), .timeout(let dx):
            return dx
        default: return nil
        }
    }

    var description: String {
        switch self {
        case .idle: return "No contact started"
        case .callingCQ: return "Calling CQ..."
        case .sendingGrid: return "Sending grid..."
        case .sendingReport: return "Sending SNR report..."
        case .listeningReport: return "Expecting SNR report..."
        case .sendingRReport: return "Sending R-Report..."
        case .listeningRReport: return "Expecting RRR / RR73..."
        case .sendingRRR: return "Sending RRR..."
        case .listeningRRR: return "Expecting 73..."
        case .sending73: return "Sending 73..."
        case .completed: return "QSO completed"
        case .timeout: return "Timeout/Retry exceeded"
        }
    }
}

enum QSOAction: Equatable {
    case sendCQ
    case sendGrid(dxCallsign: String, dxLocator: String)
    case sendReport(dxCallsign: String, report: Int)
    case sendRReport(dxCallsign: String, report: Int)
    case sendRRR(dxCallsign: String)
    case sendRR73(dxCallsign: String)
    case send73(dxCallsign: String)
    case completeQSO(dxCallsign: String)
    case abortQSO
    case ignore
}

// MARK: - QSOManager
@MainActor
final class QSOStatusManager: ObservableObject {

    @Published var qsoState: QSOState = .idle
    
    private let invalidSNR = Int.min
    
    @Published var lockedDXCallsign: String = ""
    @Published var lockedDXLocator: String = ""
    @Published var lastSentSNR: Int = Int.min  // Measured by us -> RST_SENT (FT8Message.measuredSNR)
    @Published var lastReceivedSNR: Int = Int.min // From DX text  -> RST_RCVD (FT8Message.messageTxtSNR)

    var currentCQModifier: String?

    @Published var retryCounter = 0
    var maxRetrySlots = 3
    var qsoAlreadyLogged = false

    // Explicit confirmation that DX has copied our report
    var dxHasConfirmedMyReport = false

    // Courtesy listening control
    var courtesyListeningEnabled = true // ToDo - enable or disable
    var lastCourtesyDXCallsign: String?
    var courtesy73SentDuringQSO = false
    var courtesy73SentAfterQSO = false
    var courtesyDeadline: Date?
    
    // Slot-based timeout tracking
    // Reset at start of each RX slot, set to true when valid response advances state
    var responseReceivedThisSlot = false
    
    /// Call this at the start of each RX slot to reset the response tracking
    func prepareForRXSlot() {
        responseReceivedThisSlot = false
    }

    internal let appLogger = AppLogger(category: "QSO")

    init() {}

    // MARK: - Start a QSO (Run mode)
    func startReply(to message: FT8Message, myCallsign: String, myLocator: String) -> QSOAction {
        let reportToSend: Int
        
        guard let dx = message.callsign else {
            appLogger.debug("startReply: No callsign in message, ignoring.")
            return .ignore
        }

        let cqModifier = message.msgType == .cq ? message.cqModifier : nil
        setupNewQSO(dx: dx, locator: message.locator ?? "", initialSNR: message.measuredSNR, cqModifier: cqModifier)

        appLogger.debug("startReply: Locked DX \(dx), message type: \(message.msgType), \(message.cycle)")

        switch message.msgType {
        case .cq:
            qsoState = .sendingGrid(dxCallsign: dx)
            appLogger.debug("Transition to sendingGrid for \(dx)")
            return .sendGrid(dxCallsign: dx, dxLocator: lockedDXLocator)

        case .gridExchange where message.dxCallsign?.uppercased() == myCallsign.uppercased():
            qsoState = .sendingReport(dxCallsign: dx)
            appLogger.debug("Transition to sendingReport for \(dx)")

            guard lastSentSNR != invalidSNR else {
                appLogger.error("Attempting to send report without valid frozen RST_SENT")
                return .ignore
            }

            return .sendReport(dxCallsign: dx, report: lastSentSNR)

        default:
            qsoState = .sendingGrid(dxCallsign: dx)
                        appLogger.debug("startReply: idle. Starting default grid exchange")
            return .sendGrid(dxCallsign: dx, dxLocator: lockedDXLocator)
        }
    }

    // MARK: - Handle incoming messages (RX)
    func handleIncomingMessage(
        _ message: FT8Message,
        myCallsign: String,
        autoSequencingEnabled: Bool,
        autoCQReplyEnabled: Bool
    ) -> QSOAction {

        guard autoSequencingEnabled else {
            appLogger.debug("RX autoSequencingEnabled=\(autoSequencingEnabled)")
            return .ignore }
        guard message.msgType != .unknown else { return .ignore }
        guard let dx = message.callsign else { return .ignore }

        let myCallUpper = myCallsign.uppercased()
        let dxCallUpper = dx.uppercased()
        let was = qsoState
        
        // --- IGNORE MESSAGES WHEN QSO IS COMPLETED/TIMEOUT (except courtesy) ---
        // Check if we're in a terminal state before processing further
        if case .completed = qsoState, !courtesyListeningEnabled {
            appLogger.debug("Ignoring message - QSO already completed and courtesy listening disabled")
            return .ignore
        }
        
        if case .timeout = qsoState {
            appLogger.debug("Ignoring message - QSO already timed out")
            return .ignore
        }
        
        // --- COURTESY RX 73 AFTER COMPLETED QSO ---
        // Only reply with 73 if we haven't already sent RR73 or 73 during the QSO
        // RR73 already contains 73, so no need to send another one
        if courtesyListeningEnabled,
           message.msgType == .final73,
           let courtesyDX = lastCourtesyDXCallsign,
           message.callsign?.uppercased() == courtesyDX.uppercased(),
           let deadline = courtesyDeadline,
           Date() <= deadline,
           !courtesy73SentAfterQSO,
           !courtesy73SentDuringQSO {

            courtesy73SentAfterQSO = true
            courtesyDeadline = nil
            lastCourtesyDXCallsign = nil

            appLogger.debug(
                "Courtesy RX 73 from \(courtesyDX) after QSO completion, replying once"
            )

            return .send73(dxCallsign: courtesyDX)
        }

        // --- START LOGIC (IDLE / CQ) ---
        if qsoState == .idle || qsoState == .callingCQ {
            
            if message.msgType == .cq && autoCQReplyEnabled {
                // Additional safety: verify callsign is valid before starting QSO
                guard isValidCallsign(dxCallUpper) else {
                    appLogger.warning("Ignoring CQ with invalid callsign: \(dxCallUpper)")
                    return .ignore
                }
                
                setupNewQSO(dx: dxCallUpper, locator: message.locator ?? "", initialSNR: message.measuredSNR, cqModifier: message.cqModifier)
                qsoState = .sendingGrid(dxCallsign: dxCallUpper)
                return .sendGrid(dxCallsign: dxCallUpper, dxLocator: lockedDXLocator)
            }

            if message.msgType == .gridExchange,
               message.dxCallsign?.uppercased() == myCallUpper {
                // Additional safety: verify callsign is valid before starting QSO
                guard isValidCallsign(dxCallUpper) else {
                    appLogger.warning("Ignoring grid exchange with invalid callsign: \(dxCallUpper)")
                    return .ignore
                }
                
                setupNewQSO(dx: dxCallUpper, locator: message.locator ?? "", initialSNR: message.measuredSNR, cqModifier: message.cqModifier)
                qsoState = .sendingReport(dxCallsign: dxCallUpper)
                guard lastSentSNR != invalidSNR else {
                    appLogger.error("Attempting to send report without valid RST_SENT")
                    return .ignore
                }
                return .sendReport(dxCallsign: dxCallUpper, report: lastSentSNR)
            }
        }

        if !lockedDXCallsign.isEmpty && dxCallUpper != lockedDXCallsign {
            return .ignore
        }
        
        if case .sending73(let dx) = qsoState,
           dxCallUpper == dx,
           message.msgType == .final73 {

            appLogger.debug("Final 73 received from \(dx), completing QSO immediately")

            return closeQSO(
                dxCallsign: dxCallUpper,
                openCourtesyWindow: true
            )
        }
        
        // --- RX RR73 CLOSES QSO ---
        // When DX sends RR73 (instead of RRR), they're confirming + saying 73
        // We should send 73 back as courtesy, then close QSO on TX
        if message.msgType == .rr73,
           message.dxCallsign?.uppercased() == myCallUpper,
           isQSOOngoing() {

            appLogger.debug("RR73 received from \(dxCallUpper), sending courtesy 73")
            
            // Transition to sending73 state - the QSO will complete after TX
            qsoState = .sending73(dxCallsign: dxCallUpper)
            courtesy73SentDuringQSO = true  // Mark that we're sending 73
            return .send73(dxCallsign: dxCallUpper)
        }


        // --- MAIN STATE MACHINE ---
        switch qsoState {

        case .sendingGrid(let dx):
            if (message.msgType == .standardSignalReport || message.msgType == .rSignalReport),
               message.dxCallsign?.uppercased() == myCallUpper {
                
                if message.msgType == .standardSignalReport {
                    lastReceivedSNR = Int(message.messageTxtSNR.rounded())
                } else if message.msgType == .rSignalReport,
                          lastReceivedSNR == invalidSNR {
                    lastReceivedSNR = Int(message.messageTxtSNR.rounded())
                    appLogger.debug("RST_RCVD fixed from R-REPORT RX: \(lastReceivedSNR)")
                }

                retryCounter = 0
                responseReceivedThisSlot = true
                qsoState = .sendingRReport(dxCallsign: dx)
                guard lastSentSNR != invalidSNR else {
                    appLogger.error("Attempting to send report without valid RST_SENT")
                    return .ignore
                }
                return .sendRReport(dxCallsign: dx, report: lastSentSNR)
            }
            // Don't call handleRetry here - let slot timeout handle it
            return .ignore

        case .sendingReport(let dx), .listeningReport(let dx):
            if (message.msgType == .rSignalReport || message.msgType == .standardSignalReport),
               message.dxCallsign?.uppercased() == myCallUpper {

                if message.msgType == .standardSignalReport {
                    lastReceivedSNR = Int(message.messageTxtSNR.rounded())
                } else if message.msgType == .rSignalReport,
                          lastReceivedSNR == invalidSNR {
                    lastReceivedSNR = Int(message.messageTxtSNR.rounded())
                    appLogger.debug("RST_RCVD fixed from R-REPORT RX: \(lastReceivedSNR)")
                }

                dxHasConfirmedMyReport = message.msgType == .rSignalReport
                retryCounter = 0
                responseReceivedThisSlot = true
                        
                if message.msgType == .standardSignalReport {
                    // S&P Mode: Received their standard report - respond with our R-report
                    qsoState = .sendingRReport(dxCallsign: dx)
                    guard lastSentSNR != invalidSNR else {
                        appLogger.error("Attempting to send R-report without valid RST_SENT")
                        return .ignore
                    }
                    appLogger.debug("S&P Mode: Received DX report, sending R-report")
                    return .sendRReport(dxCallsign: dx, report: lastSentSNR)
                }

                // RUN Mode: Received R-report (DX confirmed our report) - send RR73
                // RR73 combines acknowledgment + 73 for faster QSO completion
                qsoState = .sending73(dxCallsign: dx)
                courtesy73SentDuringQSO = true  // Mark that we're sending 73 (via RR73)
                appLogger.debug("RUN Mode: Received R-report from DX, sending RR73")
                return .sendRR73(dxCallsign: dx)
            }

            // Don't call handleRetry here - let slot timeout handle it
            return .ignore

        case .sendingRReport(let dx), .listeningRReport(let dx):
            // S&P Mode: We sent R-report, waiting for RRR from DX
            if message.msgType == .rrr,
               message.dxCallsign?.uppercased() == myCallUpper {

                retryCounter = 0
                responseReceivedThisSlot = true
                qsoState = .sending73(dxCallsign: dx)
                courtesy73SentDuringQSO = true  // Mark that we're sending 73 (via RR73)
                appLogger.debug("S&P Mode: Received RRR, sending RR73")
                return .sendRR73(dxCallsign: dx)
            }

            // Don't call handleRetry here - let slot timeout handle it
            return .ignore

        case .sendingRRR(let dx), .listeningRRR(let dx):
            // RUN Mode: We sent RRR, waiting for 73 or RR73 from DX
            if (message.msgType == .final73 || message.msgType == .rr73),
               message.dxCallsign?.uppercased() == myCallUpper || message.callsign?.uppercased() == dx.uppercased() {

                retryCounter = 0
                responseReceivedThisSlot = true
                appLogger.debug("RUN Mode: Received \(message.msgType) from DX, QSO complete")
                return closeQSO(
                    dxCallsign: dx,
                    openCourtesyWindow: true
                )
            }

            // Don't call handleRetry here - let slot timeout handle it
            return .ignore

        default:
            appLogger.debug("handleIncomingMessage: No action for state \(qsoState.description)")
            return .ignore
        }
    }


    internal func setupNewQSO(dx: String, locator: String, initialSNR: Double?, cqModifier: String? = nil) {
        lockedDXCallsign = dx
        lockedDXLocator = locator
        
        // Freeze RST_SENT at the instant the QSO begins - the one and only place
        // Valid FT8 SNR range is roughly -24 to +50 dB
        if let snr = initialSNR, !snr.isNaN, snr >= -50, snr <= 50 {
            lastSentSNR = Int(snr.rounded())
            appLogger.debug("RST_SENT frozen at QSO start: \(lastSentSNR)")
        } else {
            appLogger.warning("Invalid SNR at QSO start: \(String(describing: initialSNR))")
            lastSentSNR = invalidSNR
        }
        
        lastReceivedSNR = invalidSNR
        retryCounter = 0
        qsoAlreadyLogged = false
        dxHasConfirmedMyReport = false
        courtesy73SentAfterQSO = false
        courtesy73SentDuringQSO = false
        currentCQModifier = cqModifier
    }

    // MARK: - Slot-based timeout handling
    /// Called at the end of each RX slot when no matching response was received.
    /// Increments retry counter and returns the appropriate resend action.
    /// After maxRetrySlots attempts, returns abortQSO.
    func handleQSOTimeout() -> QSOAction {
        // Only trigger timeout if we're actually awaiting a response
        guard isAwaitingResponse() else { return .ignore }
        guard !lockedDXCallsign.isEmpty else { return .ignore }
        
        // If we received a valid response this slot, don't timeout
        if responseReceivedThisSlot {
            appLogger.debug("Response received this slot, skipping timeout")
            return .ignore
        }

        retryCounter += 1
        
        if retryCounter <= maxRetrySlots {
            appLogger.debug("Slot timeout for \(lockedDXCallsign), attempt \(retryCounter)/\(maxRetrySlots)")

            switch qsoState {
            case .sendingGrid(let dx), .listeningReport(let dx):
                // listeningReport means we sent grid and are waiting for DX's report
                // On timeout, resend our grid
                return .sendGrid(dxCallsign: dx, dxLocator: lockedDXLocator)
            case .sendingReport(let dx):
                // Resend our report if DX hasn't responded
                guard lastSentSNR != invalidSNR else {
                    appLogger.error("Attempting to send report without valid RST_SENT")
                    return .ignore
                }
                return .sendReport(dxCallsign: dx, report: lastSentSNR)
            case .sendingRReport(let dx), .listeningRReport(let dx):
                // listeningRReport means we sent R-report, waiting for RRR
                // On timeout, resend our R-report
                guard lastSentSNR != invalidSNR else {
                    appLogger.error("Attempting to send R-report without valid RST_SENT")
                    return .ignore
                }
                return .sendRReport(dxCallsign: dx, report: lastSentSNR)
            case .sendingRRR(let dx), .listeningRRR(let dx):
                // RUN mode: Resend RRR if DX hasn't sent 73/RR73 yet
                return .sendRRR(dxCallsign: dx)
            case .sending73(let dx):
                return .send73(dxCallsign: dx)
            default:
                break
            }
        }

        let dx = lockedDXCallsign
        let oldState = qsoState
        appLogger.debug("Max retries exceeded for \(dx), marking timeout")
        qsoState = .timeout(dxCallsign: dx)
        logTransition(oldState: oldState, newState: qsoState, dx: dx)
        resetQSO()
        return .abortQSO
    }


    // MARK: - Manual Reset QSO
    func resetQSO() {
        appLogger.debug("Resetting QSO, clearing state and DX lock")
        qsoState = .idle
        lockedDXCallsign = ""
        lockedDXLocator = ""
        lastCourtesyDXCallsign = nil
        retryCounter = 0
        responseReceivedThisSlot = false
        lastSentSNR = invalidSNR
        lastReceivedSNR = invalidSNR
        dxHasConfirmedMyReport = false
        courtesy73SentDuringQSO = false
        courtesy73SentAfterQSO = false
        qsoAlreadyLogged = false
        currentCQModifier = nil
    }
    
    func resetRadioStateAfterCompletion() {
        appLogger.debug("Reset radio state after QSO completion")
        qsoState = .idle
        lockedDXCallsign = ""
        lockedDXLocator = ""
        retryCounter = 0
//        lastSentSNR = invalidSNR
//        lastReceivedSNR = invalidSNR
        qsoAlreadyLogged = false
        currentCQModifier = nil
    }

    /// Returns true if the QSO state is awaiting a response from DX
    /// These are "listening" states where we've already transmitted and are waiting for DX reply
    /// Does NOT include "sending" states since we haven't transmitted yet
    func isAwaitingResponse() -> Bool {
        switch qsoState {
        case .listeningReport, .listeningRReport, .listeningRRR:
            return true
        default:
            return false
        }
    }
    
    func isQSOOngoing() -> Bool {
        switch qsoState {
        case .idle, .completed, .timeout:
            return false
        default:
            return !lockedDXCallsign.isEmpty
        }
    }
    
    /// Returns true if we should transmit this slot based on QSO state
    /// TX should happen when: calling CQ, or in a "sending" state
    /// TX should NOT happen when: idle, listening, completed, or timeout
    func shouldTransmitThisSlot() -> Bool {
        switch qsoState {
        case .callingCQ:
            return true
        case .sendingGrid, .sendingReport, .sendingRReport, .sendingRRR, .sending73:
            return true
        case .idle, .listeningReport, .listeningRReport, .listeningRRR, .completed, .timeout:
            return false
        }
    }

    func closeQSO(dxCallsign: String, openCourtesyWindow: Bool) -> QSOAction {

        if qsoAlreadyLogged {
            appLogger.debug("QSO already logged for \(dxCallsign), ignoring duplicate close attempt")
            return .ignore
        }

        qsoAlreadyLogged = true
        retryCounter = 0

        let oldState = qsoState
        qsoState = .completed(dxCallsign: dxCallsign)
        logTransition(oldState: oldState, newState: qsoState, dx: dxCallsign)

        if openCourtesyWindow && courtesyListeningEnabled {
            lastCourtesyDXCallsign = dxCallsign
            courtesyDeadline = Date().addingTimeInterval(30)
            appLogger.debug("Courtesy listening window opened for \(dxCallsign)")
            // Clear the lock to allow other CQs to be heard during courtesy window
            lockedDXCallsign = ""
            lockedDXLocator = ""
        } else {
            lastCourtesyDXCallsign = nil
            courtesyDeadline = nil
            // Clear the lock immediately if no courtesy window
            lockedDXCallsign = ""
            lockedDXLocator = ""
        }
        
        // Reset operational state to idle so new QSOs can start
        // (completed is a UI-visible state, but operationally we're ready for a new QSO)
        qsoState = .idle

        return .completeQSO(dxCallsign: dxCallsign)
    }


    func logTransition(oldState: QSOState, newState: QSOState, dx: String) {
        appLogger.debug("\(oldState) -> \(newState) for \(dx)")
    }

    // MARK: - TX State Advancement (Centralized Logic)
    func advanceStateOnTX(
        message: FT8Message,
        frequency: Double,
        band: FT8Message.Band,
        isFT4: Bool
    ) -> QSOAction? {
        // Do not advance state if QSO is completed
        if case .completed = qsoState {
            appLogger.debug("advanceStateOnTX ignored: QSO already completed")
            return nil
        }

        guard isQSOOngoing() else { return nil }

        let oldState = qsoState
        var newState: QSOState? = nil

        switch message.msgType {

        case .cq:
            if !isQSOOngoing(){
                newState = .callingCQ
            }

        case .gridExchange:
            if let dx = message.dxCallsign {
                newState = .listeningReport(dxCallsign: dx)
            }

        case .standardSignalReport:
            if let dx = message.dxCallsign {
                newState = .listeningReport(dxCallsign: dx)
            }

        case .rSignalReport:
            if let dx = message.dxCallsign {
                newState = .listeningRReport(dxCallsign: dx)
            }

        case .rrr:
            if let dx = message.dxCallsign {
                newState = .listeningRRR(dxCallsign: dx)
            }
            
        case .rr73:
            appLogger.debug("RR73 transmitted, closing QSO...")

            let dx = lockedDXCallsign
            guard !dx.isEmpty else {
                appLogger.error("RR73 TX without locked DX, ignoring")
                return nil
            }

            return closeQSO(
                dxCallsign: dx,
                openCourtesyWindow: true
            )


        case .final73:
            // If we're in sending73 state and TX 73, close the QSO
            // This happens when DX sent RR73 (instead of RRR) and we replied with 73
            if case .sending73(let dx) = qsoState {
                appLogger.debug("73 transmitted in sending73 state, closing QSO for \(dx)")
                return closeQSO(
                    dxCallsign: dx,
                    openCourtesyWindow: false  // No courtesy window needed, we just sent 73
                )
            }
            // Otherwise, TX 73 is courtesy only (after QSO already completed)
            break

        default:
            break
        }

        if let newState {
            qsoState = newState
            if oldState != newState {
                appLogger.debug("TX State Advanced: \(oldState) -> \(newState)")
            }
        }

        return nil
    }

    // MARK: - Log Entry Factory
    func createLogEntry(
        dxCallsign: String,
        dxLocator: String,
        qsoDate: Date,
        frequency: Double,
        band: FT8Message.Band,
        isFT4: Bool,
        rstSent: Int,
        rstRcvd: Int
    ) -> LogEntry {
        // Station callsign as-is from UserDefaults (may include /suffix)
        let stationCallsign = UserDefaults.standard.string(forKey: "callsign")
        let mySigInfo: String? = {
            switch currentCQModifier {
            case "POTA":
                return UserDefaults.standard.string(forKey: "myPotaRef")
            case "SOTA":
                return UserDefaults.standard.string(forKey: "mySotaRef")
            case "WWFF":
                return UserDefaults.standard.string(forKey: "myWwffRef")
            case "IOTA":
                return UserDefaults.standard.string(forKey: "myIotaRef")
            // Geographic filters (DX, EU, NA, SA, AF, AS, OC, ANT) don't have reference info
            default:
                return nil
            }
        }()

        guard rstSent != invalidSNR, rstRcvd != invalidSNR else {
            appLogger.error("Attempting to log QSO without valid SNRs")
            return LogEntry(
                callsign: dxCallsign,
                grid: dxLocator,
                date: qsoDate,
                mode: isFT4 ? "FT4" : "FT8",
                band: band.rawValue,
                rstSent: "Invalid",
                rstRcvd: "Invalid",
                stationCallsign: stationCallsign,
                cqModifier: currentCQModifier,
                mySigInfo: mySigInfo
            )
        }
        
        return LogEntry(
            callsign: dxCallsign,
            grid: dxLocator,
            date: qsoDate,
            mode: isFT4 ? "FT4" : "FT8",
            band: band.rawValue,
            rstSent: String(rstSent),
            rstRcvd: String(rstRcvd),
            stationCallsign: stationCallsign,
            cqModifier: currentCQModifier,
            mySigInfo: mySigInfo
        )
    }

    
    func startCallingCQ() {
        qsoState = .callingCQ
        // Set current CQ modifier from UserDefaults when starting CQ
        let storedModifier = UserDefaults.standard.string(forKey: "cqModifier") ?? "NONE"
        currentCQModifier = (storedModifier != "NONE") ? storedModifier : nil
    }
}
