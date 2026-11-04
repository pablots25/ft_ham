//
//  MockAudioManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/12/25.
//

import Foundation
import Combine
@testable import ft8_ham

// -----------------------------------------------------
// MARK: - Legacy Mock FT8 Engine
// Note: AudioManaging and MessageDecoding protocols are now in DependencyInjection.swift
// -----------------------------------------------------

// Protocol for FT8Engine (legacy, kept for backward compatibility with existing tests)
protocol FT8EngineProtocol {
    func generateFT8(_ message: String, frequency: Float, isFT4: Bool, toFile: URL?) -> Data?
    func startRealtimeDecode(_ isFT4: Bool, messageHandler: @escaping ([[AnyHashable: Any]]) -> Void)
    func stopRealtimeDecode()
    func decode(_ input: URL?, isFT4: Bool) -> [[AnyHashable: Any]]
}

//// -----------------------------------------------------
//// MARK: - Mock Audio Manager
//// -----------------------------------------------------
//final class MockAudioManager: AudioManaging {
//    var audioSamplesPublisher = PassthroughSubject<[Float], Never>().eraseToAnyPublisher()
//    var txStatusPublisher = PassthroughSubject<Bool, Never>().eraseToAnyPublisher()
//    var rxStatusPublisher = PassthroughSubject<Bool, Never>().eraseToAnyPublisher()
//    var audioErrorPublisher = PassthroughSubject<String, Never>().eraseToAnyPublisher()
//    
//    var startMicCalled = false
//    var stopMicCalled = false
//    var playCalled = false
//    var stopPlaybackCalled = false
//    
//    func startMicInput() {
//        startMicCalled = true
//    }
//    
//    func stopMicInput() {
//        stopMicCalled = true
//    }
//    
//    func playAudio(_ audioData: Data) {
//        playCalled = true
//    }
//    
//    func stopPlayback() {
//        stopPlaybackCalled = true
//    }
//}

//// -----------------------------------------------------
//// MARK: - Mock Slot Manager
//// -----------------------------------------------------
//final class MockSlotManager: SlotManaging {
//    var waitCalled = false
//    
//    func currentSlots(forTX: Bool, isFT4: Bool, evenCycle: Bool) -> [Double] {
//        return [0.0, isFT4 ? 7.5 : 15.0]
//    }
//    
//    func waitUntilNextSlot(
//        taskName: String,
//        logger: AppLogger,
//        forTX: Bool,
//        firstLoop: inout Bool,
//        isFT4: Bool,
//        evenCycle: Bool
//    ) async throws -> Bool {
//        waitCalled = true
//        firstLoop = false
//        return true
//    }
//}

// -----------------------------------------------------
// MARK: - Mock FT8 Engine
// -----------------------------------------------------
final class MockFT8Engine: FT8EngineProtocol {
    var generateCalled = false
    var decodeCalled = false
    var startRealtimeDecodeCalled = false
    var stopRealtimeDecodeCalled = false
    
    func generateFT8(_ message: String, frequency: Float, isFT4: Bool, toFile: URL?) -> Data? {
        generateCalled = true
        return Data([0x00, 0x01, 0x02])
    }
    
    func startRealtimeDecode(_ isFT4: Bool, messageHandler: @escaping ([[AnyHashable: Any]]) -> Void) {
        startRealtimeDecodeCalled = true
    }
    
    func stopRealtimeDecode() {
        stopRealtimeDecodeCalled = true
    }
    
    func decode(_ input: URL?, isFT4: Bool) -> [[AnyHashable: Any]] {
        decodeCalled = true
        return [["text": "EA1AAA K1ABC +10", "snr": 12.0, "frequency": 1400.0, "time": 0.1]]
    }
}
