//
//  MessageReplyTests.swift
//  ft_hamTests
//
//  Created by Pablo Turrion on 01/01/26.
//

import XCTest
@testable import ft8_ham

final class MessageReplyTests: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            self.viewModel = FT8ViewModel()
            // reply(to:) requires a valid station callsign and locator
            // (settingsLoaded) and a valid DX callsign.
            self.viewModel.callsign = "EA4XYZ"
            self.viewModel.locator = "JN18"
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            self.viewModel = nil
        }
        try await super.tearDown()
    }

    // Helper to create a message with a given timestamp
    private func makeMessage(msgType: FT8MessageType, timestampOffset: TimeInterval = 0) -> FT8Message {
        let now = Date().addingTimeInterval(timestampOffset)
        // Build message text according to requested type so tests can exercise reply logic
        let text: String
        switch msgType {
        case .cq:
            text = "CQ K1ABC FN31"
        case .gridExchange:
            text = "EA4XYZ K1ABC FN31"
        case .standardSignalReport:
            text = "EA4XYZ K1ABC +10"
        case .rrr:
            text = "EA4XYZ K1ABC RRR"
        case .final73:
            text = "EA4XYZ K1ABC 73"
        default:
            text = "CQ K1ABC FN31"
        }

        return FT8Message(
            text: text,
            mode: .ft8,
            isRealtime: true,
            timestamp: now,
            measuredSNR: 10,
            frequency: 1400,
            timeOffset: 0,
            band: .band20m
        )
    }

    @MainActor
    func testEvenCycleCalculation_FT8() async {
        viewModel.isFT4 = false
        let cycleLength = 15.0

        // 1. Obtener una fecha de referencia: el inicio del minuto actual
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        _ = Calendar.current.date(from: components)!

        // 2. Escenario: Mensaje recibido en el segundo 0 (Ciclo PAR)
        // Debemos responder en el segundo 15 (Ciclo IMPAR -> evenCycle = false)
        let evenTimestamp = Date(timeIntervalSinceReferenceDate: cycleLength * 2)
        let messageEven = makeMessage(msgType: .cq, timestampOffset: evenTimestamp.timeIntervalSinceNow)
        
        viewModel.reply(to: messageEven)
        
        XCTAssertFalse(viewModel.evenCycle, "Si recibo en PAR (0s), mi transmisión debe ser IMPAR (false)")

        // 3. Escenario: Mensaje recibido en el segundo 15 (Ciclo IMPAR)
        // Debemos responder en el segundo 30 (Ciclo PAR -> evenCycle = true)
        let oddTimestamp = Date(timeIntervalSinceReferenceDate: cycleLength * 3)
        let messageOdd = makeMessage(msgType: .cq, timestampOffset: oddTimestamp.timeIntervalSinceNow)
        
        viewModel.reply(to: messageOdd)
        
        XCTAssertTrue(viewModel.evenCycle, "Si recibo en IMPAR (15s), mi transmisión debe ser PAR (true)")
    }

    @MainActor
    func testMessageIndexSelection() async {
        // A grid addressed to me is answered with the report (TX2) and a
        // report addressed to me with the R-report (TX3). Every other
        // message starts the exchange with my grid (TX1).
        viewModel.autoSequencingEnabled = true
        let expectations: [(FT8MessageType, Int)] = [
            (.cq, 1), (.gridExchange, 2), (.standardSignalReport, 3), (.rrr, 1), (.final73, 1)
        ]
        for (t, expectedIndex) in expectations {
            let m = makeMessage(msgType: t)
            await MainActor.run { viewModel.reply(to: m) }
            await MainActor.run {
                XCTAssertEqual(viewModel.selectedMessageIndex, expectedIndex, "Reply to \(t)")
            }
        }
    }
}
