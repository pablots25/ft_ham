//
//  SlotManagerTests.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/1/26.
//


import XCTest
@testable import ft8_ham

final class SlotManagerTests2: XCTestCase {
    
    var slotManager: SlotManager!
    
    override func setUp() async throws {
        slotManager = SlotManager()
    }
    
    // MARK: - Test 1: Robustez de Ciclo (Even/Odd)
    func testEvenOddDetection() async {
        let calendar = Calendar.current
        let now = Date()
        
        // Target: XX:XX:00 (Must be Even, Index N)
        let time00 = calendar.date(bySetting: .second, value: 0, of: now)!
        let info00 = await slotManager.getSlotInfo(at: time00, isFT4: false)
        XCTAssertTrue(info00.isEven, "00s must be EVEN in FT8")
        XCTAssertEqual(info00.slotIndex % 2, 0)
        
        // Target: XX:XX:15 (Must be Odd, Index N+1)
        let time15 = calendar.date(bySetting: .second, value: 15, of: now)!
        let info15 = await slotManager.getSlotInfo(at: time15, isFT4: false)
        XCTAssertFalse(info15.isEven, "15s must be ODD in FT8")
        XCTAssertEqual(info15.slotIndex % 2, 1)

        // Target: XX:XX:14.90 (Still Even)
        let time14_9 = time00.addingTimeInterval(14.9)
        let info14_9 = await slotManager.getSlotInfo(at: time14_9, isFT4: false)
        XCTAssertTrue(info14_9.isEven, "14.9s must still be EVEN in FT8")
    }
    
    // MARK: - Test 2: Cambio de Modo (FT8 vs FT4)
    func testFT4TimingAcceleration() async {
        let now = Date()
        
        // 1. FT8 Next Slot
        let nextFT8Info = await slotManager.getNextSlot(from: now, isFT4: false)
        let diffFT8 = nextFT8Info.startTime.timeIntervalSince(now)
        
        // FT8 wait <= 15.05s
        XCTAssertLessThanOrEqual(diffFT8, 15.1, "FT8 wait max 15s")
        
        // 2. FT4 Next Slot
        let nextFT4Info = await slotManager.getNextSlot(from: now, isFT4: true)
        let diffFT4 = nextFT4Info.startTime.timeIntervalSince(now)
        
        // FT4 wait <= 7.55s
        XCTAssertLessThanOrEqual(diffFT4, 7.6, "FT4 wait max 7.5s")
        
        // FT4 cycles are faster, so next slot is likely sooner or equal
        XCTAssertLessThanOrEqual(diffFT4, diffFT8, "FT4 cycle faster/equal to FT8")
    }
    
    // MARK: - Test 3: Lógica de Frontera (Jitter Protection)
    func testBoundaryProtection() async {
        let calendar = Calendar.current
        let now = Date()
        
        // Simulate: XX:XX:14.96 (Very close to boundary)
        let nearBoundaryDate = calendar.date(bySetting: .second, value: 14, of: now)!
            .addingTimeInterval(0.96)
        
        let nextSlotInfo = await slotManager.getNextSlot(from: nearBoundaryDate, isFT4: false)
        
        // Next slot should NOT be at 15.00 (0.04s away), but at 30.00
        let waitTime = nextSlotInfo.startTime.timeIntervalSince(nearBoundaryDate)
        
        XCTAssertGreaterThan(waitTime, 1.0, "Should skip immediate boundary (<0.05s) to avoid double trigger")
    }
}
