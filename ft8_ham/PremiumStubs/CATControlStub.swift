//
//  CATControlStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 01/03/26.
//
//

import Foundation
import Combine

/// Stub CAT controller that does nothing
/// Used when premium package is not available
public final class CATControlStub: CATControlProtocol {
    public static let shared = CATControlStub()

    private init() {}

    public var isConnected: Bool { false }

    public var connectionStatePublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    public func connect(host: String, port: UInt16) {}

    public func disconnect() {}
    
    public func setPTT(enabled: Bool, host: String, port: UInt16) async -> CatRigResponse {
        return CatRigResponse(
            success: false,
            response: "",
            errorMessage: "CAT control requires premium features"
        )
    }
    
    public func setFrequency(frequency: Int64, host: String, port: UInt16) async -> CatRigResponse {
        return CatRigResponse(
            success: false,
            response: "",
            errorMessage: "CAT control requires premium features"
        )
    }
    
    public func getFrequency(host: String, port: UInt16) async -> CatRigResponse {
        return CatRigResponse(
            success: false,
            response: "",
            errorMessage: "CAT control requires premium features"
        )
    }
}
