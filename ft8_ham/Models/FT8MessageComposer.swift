//
//  FT8MessageComposer.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/12/25.
//

import Foundation

struct FT8MessageComposer {
    private func normalizedOutboundModifier(_ raw: String) -> String? {
        var upper = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if upper == "OTHER" {
            upper = (UserDefaults.standard.string(forKey: "cqModifierOther") ?? "")
                .uppercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard upper != "NONE" else { return nil }

        let filtered = upper.filter { $0.isLetter || $0.isNumber || $0 == "/" }
        guard filtered.count >= 1 && filtered.count <= 4 else { return nil }
        return filtered
    }

    func generateMessages(
        callsign: String,
        locator: String,
        dxCallsign: String,
        dxLocator: String,
        snrToSend: Double,
        includeGrid: Bool = true
    ) -> [String] {
        let de = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        let grid = String(locator.uppercased().prefix(4))
        let dx = dxCallsign.isEmpty ? "XXXXXX" : dxCallsign.uppercased().trimmingCharacters(in: .whitespaces)
        
        let report: String
        if !snrToSend.isFinite {
            report = "-15"
        } else {
            let snr = Int(snrToSend.rounded())
            let clampedSnr = max(min(snr, 30), -30) // Protocol limits
            report = String(format: "%+03d", clampedSnr)
        }

        // Get CQ modifier from UserDefaults
        let cqModifier = UserDefaults.standard.string(forKey: "cqModifier") ?? "NONE"

        // A compound callsign that the protocol cannot pack into the standard
        // 28-bit callsign field travels as a type-4 message, which carries the
        // call spelled out in place of the grid and the CQ modifier. Dropping
        // both here keeps the message list showing exactly what goes on the air;
        // leaving them in would push the CQ into a standard message where the
        // call is replaced by a hash that no one can answer.
        let deCanPackStandard = CompoundCallsign.parse(de)?.isStandardPackable ?? true

        // Build CQ message with optional modifier and optional grid
        let gridSuffix = (includeGrid && grid.count >= 4 && deCanPackStandard) ? " \(grid)" : ""
        let cqMessage: String
        if let txModifier = normalizedOutboundModifier(cqModifier), deCanPackStandard {
            cqMessage = "CQ \(txModifier) \(de)\(gridSuffix)"
        } else {
            cqMessage = "CQ \(de)\(gridSuffix)"
        }

        // Answering a CQ is the other moment a compound callsign has to be sent
        // spelled out, and it cannot carry a grid either. Sending one would put
        // the reply in a standard message, where the called station reads the
        // caller as an unresolved hash and cannot answer. The grid is the price
        // the protocol charges for a compound callsign; the reports that follow
        // are unaffected, because by then the call has been heard in full.
        let replyToCQ = deCanPackStandard ? "\(dx) \(de) \(grid)" : "\(dx) \(de)"

        // 2. Standard WSJT-X sequence definition
        let messages = [
            cqMessage,                     // [0] Tx6 General broadcast (with optional modifier)
            replyToCQ,                     // [1] Tx1 Reply to CQ (sending my Grid)
            "\(dx) \(de) \(report)",       // [2] Tx2 Sending Report (after receiving DX Grid)
            "\(dx) \(de) R\(report)",      // [3] Tx3 Sending Report with ACK (after receiving DX Report)
            "\(dx) \(de) RRR",             // [4] Tx4 Triple R (Report accepted)
            "\(dx) \(de) 73",              // [5] Tx5 Final sign-off
            "\(dx) \(de) RR73"             // [6] Tx6 Final sign-off quick
        ]
        
        return messages
    }
}
