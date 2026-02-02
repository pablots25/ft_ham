//
//  FT8MessageComposer.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/12/25.
//

import Foundation

struct FT8MessageComposer {
    func generateMessages(
        callsign: String,
        locator: String,
        dxCallsign: String,
        dxLocator: String,
        snrToSend: Double
    ) -> [String] {
        let de = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        let grid = String(locator.uppercased().prefix(4))
        let dx = dxCallsign.isEmpty ? "XXXXXX" : dxCallsign.uppercased().trimmingCharacters(in: .whitespaces)
        
        let report: String
        if snrToSend.isNaN {
            report = "-15"
        } else {
            let snr = Int(snrToSend.rounded())
            let clampedSnr = max(min(snr, 30), -30) // Protocol limits
            report = String(format: "%+03d", clampedSnr)
        }

        // Get CQ modifier from UserDefaults
        let cqModifier = UserDefaults.standard.string(forKey: "cqModifier") ?? "NONE"
        
        // Build CQ message with optional modifier
        let cqMessage: String
        if cqModifier != "NONE", FT8Message.validCQTokens.contains(cqModifier) {
            cqMessage = "CQ \(cqModifier) \(de)"
        } else {
            cqMessage = "CQ \(de) \(grid)"
        }

        // 2. Standard WSJT-X sequence definition
        let messages = [
            cqMessage,                     // [0] Tx6 General broadcast (with optional modifier)
            "\(dx) \(de) \(grid)",         // [1] Tx1 Reply to CQ (sending my Grid)
            "\(dx) \(de) \(report)",       // [2] Tx2 Sending Report (after receiving DX Grid)
            "\(dx) \(de) R\(report)",      // [3] Tx3 Sending Report with ACK (after receiving DX Report)
            "\(dx) \(de) RRR",             // [4] Tx4 Triple R (Report accepted)
            "\(dx) \(de) 73",              // [5] Tx5 Final sign-off
            "\(dx) \(de) RR73"             // [6] Tx6 Final sign-off quick
        ]
        
        return messages.map { msg in
            // Ensure message fits FT8 18-character limit
            msg.count > 18 ? String(msg.prefix(18)) : msg
        }
    }
}
