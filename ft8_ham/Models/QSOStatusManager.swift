//
//  QSOManager.swift
//  ft8_ham
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

    var retryCounter = 0
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

    internal let appLogger = AppLogger(category: "QSO")

    init() {}

    // MARK: - Start a QSO (Run mode)
    func startReply(to message: FT8Message, myCallsign: String, myLocator: String) -> QSOAction {
        let reportToSend: Int
        
        guard let dx = message.callsign else {
            appLogger.debug("startReply: No callsign in message, ignoring.")
            return .ignore
        }

        setupNewQSO(dx: dx, locator: message.locator ?? "")

        appLogger.debug("startReply: Locked DX \(dx), message type: \(message.msgType), \(message.cycle)")

        switch message.msgType {
        case .cq:
            qsoState = .sendingGrid(dxCallsign: dx)
            if lastSentSNR == invalidSNR {
                lastSentSNR = Int(message.measuredSNR.rounded())
                appLogger.debug("RST_SENT fixed from CQ RX: \(lastSentSNR)")
            }
            appLogger.debug("Transition to sendingGrid for \(dx)")
            return .sendGrid(dxCallsign: dx, dxLocator: lockedDXLocator)

        case .gridExchange where message.dxCallsign?.uppercased() == myCallsign.uppercased():
            qsoState = .sendingReport(dxCallsign: dx)
            appLogger.debug("Transition to sendingReport for \(dx)")
            if lastSentSNR == invalidSNR {
                reportToSend = Int(message.measuredSNR.rounded())
                lastSentSNR = reportToSend
            } else {
                reportToSend = lastSentSNR
            }
            return .sendReport(dxCallsign: dx, report: reportToSend)

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
        
        // --- COURTESY RX 73 AFTER COMPLETED QSO ---
        if courtesyListeningEnabled,
           message.msgType == .final73,
           let courtesyDX = lastCourtesyDXCallsign,
           message.callsign?.uppercased() == courtesyDX.uppercased(),
           let deadline = courtesyDeadline,
           Date() <= deadline,
           !courtesy73SentAfterQSO {

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
                setupNewQSO(dx: dxCallUpper, locator: message.locator ?? "")
                if lastSentSNR == invalidSNR {
                    lastSentSNR = Int(message.measuredSNR.rounded())
                    appLogger.debug("RST_SENT fixed from CQ RX: \(lastSentSNR)")
                }
                qsoState = .sendingGrid(dxCallsign: dxCallUpper)
                return .sendGrid(dxCallsign: dxCallUpper, dxLocator: lockedDXLocator)
            }

            if message.msgType == .gridExchange,
               message.dxCallsign?.uppercased() == myCallUpper {
                setupNewQSO(dx: dxCallUpper, locator: message.locator ?? "")
                if lastSentSNR == invalidSNR {
                    lastSentSNR = Int(message.measuredSNR.rounded())
                    appLogger.debug("RST_SENT fixed from GRID RX: \(lastSentSNR)")
                }
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
        if message.msgType == .rr73,
           message.dxCallsign?.uppercased() == myCallUpper,
           isQSOOngoing() {

            appLogger.debug("RR73 received from \(dxCallUpper), closing QSO")
            return closeQSO(
                dxCallsign: dxCallUpper,
                openCourtesyWindow: true
            )
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
                qsoState = .sendingRReport(dxCallsign: dx)
                guard lastSentSNR != invalidSNR else {
                    appLogger.error("Attempting to send report without valid RST_SENT")
                    return .ignore
                }
                return .sendRReport(dxCallsign: dx, report: lastSentSNR)
            }
            return handleRetry(forState: was) {
                .sendGrid(dxCallsign: dx, dxLocator: lockedDXLocator)
            }

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
                        
                if message.msgType == .standardSignalReport {
                    qsoState = .sendingRReport(dxCallsign: dx)
                    guard lastSentSNR != invalidSNR else {
                        appLogger.error("Attempting to send report without valid RST_SENT")
                        return .ignore
                    }
                    return .sendRReport(dxCallsign: dx, report: lastSentSNR)
                }

                qsoState = .sending73(dxCallsign: dx)
                return .sendRR73(dxCallsign: dx)
            }

            return handleRetry(forState: was) {
                .sendReport(dxCallsign: dx, report: lastSentSNR)
            }

        case .sendingRReport(let dx), .listeningRReport(let dx):
            if message.msgType == .rrr,
               message.dxCallsign?.uppercased() == myCallUpper {

                qsoState = .sending73(dxCallsign: dx)
                return .sendRR73(dxCallsign: dx)
            }


            return handleRetry(forState: was) {
                .sendRReport(dxCallsign: dx, report: lastSentSNR)
            }


        default:
            appLogger.debug("handleIncomingMessage: No action for state \(qsoState.description)")
            return .ignore
        }
    }


    private func setupNewQSO(dx: String, locator: String) {
        lockedDXCallsign = dx
        lockedDXLocator = locator
        lastSentSNR = invalidSNR
        lastReceivedSNR = invalidSNR
        retryCounter = 0
        qsoAlreadyLogged = false
        dxHasConfirmedMyReport = false
        courtesy73SentAfterQSO = false
        courtesy73SentDuringQSO = false
    }

    // MARK: - Retry handling
    func handleRetry(forState state: QSOState, resendAction: () -> QSOAction) -> QSOAction {
        retryCounter += 1
        if retryCounter <= maxRetrySlots {
            appLogger.debug("Retry \(retryCounter)/\(maxRetrySlots) for \(lockedDXCallsign)")
            return resendAction()
        } else {
            appLogger.debug("Max retries exceeded for \(lockedDXCallsign), marking timeout")
            qsoState = .timeout(dxCallsign: lockedDXCallsign)
            logTransition(oldState: state, newState: qsoState, dx: lockedDXCallsign)
            return .abortQSO
        }
    }

    // MARK: - Timeout handling with retry awareness
    func handleQSOTimeout() -> QSOAction {
        if lockedDXCallsign.isEmpty { return .ignore }

        if retryCounter < maxRetrySlots {
            retryCounter += 1
            appLogger.debug("Timeout for \(lockedDXCallsign), retrying \(retryCounter)/\(maxRetrySlots)")

            switch qsoState {
            case .sendingGrid(let dx):
                return .sendGrid(dxCallsign: dx, dxLocator: lockedDXLocator)
            case .sendingReport(let dx):
                guard lastSentSNR != invalidSNR else {
                    appLogger.error("Attempting to send report without valid RST_SENT")
                    return .ignore
                }
                return .sendReport(dxCallsign: dx, report: lastSentSNR)
            case .sendingRReport(let dx):
                guard lastSentSNR != invalidSNR else {
                    appLogger.error("Attempting to send report without valid RST_SENT")
                    return .ignore
                }
                return .sendRReport(dxCallsign: dx, report: lastSentSNR)
            case .sendingRRR(let dx):
                return .sendRRR(dxCallsign: dx)
            case .sending73(let dx):
                return .send73(dxCallsign: dx)
            default:
                break
            }
        }

        let dx = lockedDXCallsign
        appLogger.debug("Max retries exceeded for \(dx), marking timeout")
        qsoState = .timeout(dxCallsign: dx)
        logTransition(oldState: .idle, newState: qsoState, dx: dx)
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
        lastSentSNR = invalidSNR
        lastReceivedSNR = invalidSNR
        dxHasConfirmedMyReport = false
        courtesy73SentDuringQSO = false
        courtesy73SentAfterQSO = false
        qsoAlreadyLogged = false
    }
    
    func resetRadioStateAfterCompletion() {
        appLogger.debug("Reset radio state after QSO completion")
        qsoState = .idle
        lockedDXCallsign = ""
        lockedDXLocator = ""
//        lastSentSNR = invalidSNR
//        lastReceivedSNR = invalidSNR
        qsoAlreadyLogged = false
    }

    func isQSOOngoing() -> Bool {
        switch qsoState {
        case .idle, .completed, .timeout:
            return false
        default:
            return !lockedDXCallsign.isEmpty
        }
    }

    func closeQSO(dxCallsign: String, openCourtesyWindow: Bool) -> QSOAction {

        if qsoAlreadyLogged {
            return .ignore
        }

        qsoAlreadyLogged = true

        let oldState = qsoState
        qsoState = .completed(dxCallsign: dxCallsign)
        logTransition(oldState: oldState, newState: qsoState, dx: dxCallsign)

        if openCourtesyWindow && courtesyListeningEnabled {
            lastCourtesyDXCallsign = dxCallsign
            courtesyDeadline = Date().addingTimeInterval(30)
            appLogger.debug("Courtesy listening window opened for \(dxCallsign)")
        } else {
            lastCourtesyDXCallsign = nil
            courtesyDeadline = nil
        }

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
            // TX 73 is etiquette only, does not affect QSO validity
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
        guard rstSent != invalidSNR, rstRcvd != invalidSNR else {
            appLogger.error("Attempting to log QSO without valid SNRs")
            return LogEntry(
                callsign: dxCallsign,
                grid: dxLocator,
                date: qsoDate,
                mode: isFT4 ? "FT4" : "FT8",
                band: band.rawValue,
                rstSent: "Invalid",
                rstRcvd: "Invalid"
            )
        }
        
        return LogEntry(
            callsign: dxCallsign,
            grid: dxLocator,
            date: qsoDate,
            mode: isFT4 ? "FT4" : "FT8",
            band: band.rawValue,
            rstSent: String(rstSent),
            rstRcvd: String(rstRcvd)
        )
    }

    
    func startCallingCQ() {
        qsoState = .callingCQ
    }
}
