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
            self.viewModel.callsign = "MYCALL"
            self.viewModel.locator = "JN18aa"
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
            text = "CQ MYCALL"
        case .gridExchange:
            text = "MYCALL OTHERCALL IM99"
        case .standardSignalReport:
            text = "OTHERCALL MYCALL +10"
        case .rrr:
            text = "OTHERCALL MYCALL RRR"
        case .final73:
            text = "OTHERCALL MYCALL 73"
        default:
            text = "CQ MYCALL"
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
        // The current implementation sets the selected message index to 1 on reply
        viewModel.autoSequencingEnabled = true
        let variants: [FT8MessageType] = [.cq, .gridExchange, .standardSignalReport, .rrr, .final73]
        for t in variants {
            let m = makeMessage(msgType: t)
            await MainActor.run { viewModel.reply(to: m) }
            await MainActor.run { XCTAssertEqual(viewModel.selectedMessageIndex, 1) }
        }
    }
}
