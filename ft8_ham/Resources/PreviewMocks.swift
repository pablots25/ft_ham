//
//  PreviewMocks.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import Foundation
import SwiftUI

enum PreviewMocks {
    static let rxMessages = [
        // CQ calls
        FT8Message(text: "CQ EA4IQL IN80", mode: .ft8, measuredSNR: -12, frequency: 1500.0, timeOffset: 0.1, isTX: false),
        FT8Message(text: "CQ POTA EA4IQL", mode: .ft4, measuredSNR: -15, frequency: 1500.5, timeOffset: 0.2, isTX: false),
        FT8Message(
            text: "\(DateFormatter.utcFormatterMessage.string(from: .now)) - 10m",
            mode: .ft8,
            timestamp: .now,
            band: .band10m,
            msgType: FT8MessageType.internalTimestamp
        ),

        FT8Message(
            text: "Partial data loss",
            mode: .ft8,
            measuredSNR: .nan,
            frequency: .nan,
            timeOffset: .nan,
            isTX: false,
            band: .band10m,
            allowsReply: false
        ),

        // Grid exchanges
        FT8Message(text: "K1ABC N0XYZ FN31", mode: .ft8, measuredSNR: -5, frequency: 1400.0, timeOffset: 0.1, isTX: false),
        FT8Message(text: "N0XYZ K1ABC FN31", mode: .ft4, measuredSNR: -4, frequency: 1400.0, timeOffset: 0.3, isTX: false),
        FT8Message(
            text: "\(DateFormatter.utcFormatterMessage.string(from: .now)) - 10m",
            mode: .ft8,
            timestamp: .now,
            band: .band10m,
            msgType: FT8MessageType.internalTimestamp
        ),
        FT8Message(text: "G4DEF F4UVW IO91", mode: .ft8, measuredSNR: -12, frequency: 1412.5, timeOffset: -0.2, isTX: false),
        FT8Message(text: "F4UVW G4DEF IO91", mode: .ft8, measuredSNR: -11, frequency: 1412.5, timeOffset: 0.0, isTX: false),
        FT8Message(text: "JA1HIJ VK2LM QF56", mode: .ft8, measuredSNR: 3, frequency: 1408.7, timeOffset: 0.0, isTX: false),
        FT8Message(text: "VK2LM JA1HIJ QF56", mode: .ft8, measuredSNR: 2, frequency: 1408.7, timeOffset: 0.1, isTX: false),
        FT8Message(text: "DL3KLM EA7NOP JN48", mode: .ft8, measuredSNR: -8, frequency: 1420.3, timeOffset: 0.5, isTX: false),
        FT8Message(text: "EA7NOP DL3KLM JN48", mode: .ft8, measuredSNR: -7, frequency: 1420.3, timeOffset: 0.3, isTX: false),

        // Standard signal reports
        FT8Message(text: "EA4IQL UB5OFG +10", mode: .ft8, measuredSNR: -10, frequency: 1510.0, timeOffset: 0.1, isTX: false),
        FT8Message(text: "UB5OFG EA4IQL -12", mode: .ft8, measuredSNR: -9, frequency: 1510.0, timeOffset: 0.2, isTX: false),

        // RR73 / RRR
        FT8Message(text: "UB5OFG EA4IQL RR73", mode: .ft8, measuredSNR: -7, frequency: 1520.0, timeOffset: 0.2, isTX: false),
        FT8Message(text: "EA4IQL UB5OFG RRR", mode: .ft8, measuredSNR: -8, frequency: 1521.0, timeOffset: 0.2, isTX: false),

        // Final 73
        FT8Message(text: "EA4IQL UB5OFG 73", mode: .ft8, measuredSNR: -6, frequency: 1520.5, timeOffset: 0.2, isTX: false),

        // Separator / unknown messages
        FT8Message(
            text: "\(DateFormatter.utcFormatterMessage.string(from: .now)) - 10m",
            mode: .ft4,
            timestamp: .now,
            band: .band10m,
            msgType: FT8MessageType.internalTimestamp
        ),
        FT8Message(text: "HELLO WORLD TEST", mode: .ft8, measuredSNR: -20, frequency: 1501.0, timeOffset: 0.3, isTX: false)
    ]

    static let txMessages = [
        FT8Message(text: "CQ EA4IQL IN80", mode: .ft8, measuredSNR: .nan, frequency: 1500.0, timeOffset: .nan, isTX: true),
        FT8Message(text: "EA4IQL UB5OFG +12", mode: .ft8, measuredSNR: .nan, frequency: 1510.0, timeOffset: .nan, isTX: true),
        FT8Message(text: "EA4IQL UB5OFG RR73", mode: .ft4, measuredSNR: .nan, frequency: 1520.0, timeOffset: .nan, isTX: true),
        FT8Message(text: "EA4IQL K1ABC FN31", mode: .ft4, measuredSNR: .nan, frequency: 1400.0, timeOffset: .nan, isTX: true),
        FT8Message(text: "EA4IQL G4DEF IO91", mode: .ft4, measuredSNR: .nan, frequency: 1412.5, timeOffset: .nan, isTX: true)
    ]
    
    static let qsoList = [
        // Normal QSO (no modifier)
        LogEntry(
            callsign: "EA1ABC",
            grid: "JN02",
            date: Date().addingTimeInterval(-600),
            mode: "FT8",
            band: "20m",
            rstSent: "599",
            rstRcvd: "599",
            stationCallsign: "EA4IQL",
            cqModifier: nil,
            mySigInfo: nil
        ),

        // POTA activation
        LogEntry(
            callsign: "K1XYZ",
            grid: "FN31",
            date: Date().addingTimeInterval(-10800),
            mode: "FT8",
            band: "40m",
            rstSent: "-08",
            rstRcvd: "-12",
            stationCallsign: "EA4IQL",
            cqModifier: "POTA",
            mySigInfo: "EA-1234"
        ),

        // SOTA activation
        LogEntry(
            callsign: "DL5ME",
            grid: "JO62",
            date: Date().addingTimeInterval(-90000),
            mode: "FT8",
            band: "15m",
            rstSent: "-03",
            rstRcvd: "-07",
            stationCallsign: "EA4IQL",
            cqModifier: "SOTA",
            mySigInfo: "EA/MD-001"
        ),

        // WWFF activation
        LogEntry(
            callsign: "JA1NXS",
            grid: "PM95",
            date: Date().addingTimeInterval(-54000),
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-15",
            stationCallsign: "EA4IQL",
            cqModifier: "WWFF",
            mySigInfo: "EAFF-0456"
        ),

        // Another normal QSO after activation (must NOT contain MY_SIG)
        LogEntry(
            callsign: "LU4AA",
            grid: "GF05",
            date: Date().addingTimeInterval(-72000),
            mode: "FT8",
            band: "30m",
            rstSent: "-05",
            rstRcvd: "-06",
            stationCallsign: "EA4IQL",
            cqModifier: nil,
            mySigInfo: nil
        ),

        // POTA again (to test multiple activations in same log)
        LogEntry(
            callsign: "VK3XYZ",
            grid: "QF22",
            date: Date().addingTimeInterval(-36000),
            mode: "FT8",
            band: "17m",
            rstSent: "-02",
            rstRcvd: "-04",
            stationCallsign: "EA4IQL",
            cqModifier: "POTA",
            mySigInfo: "EA-1234"
        )
    ]


}
