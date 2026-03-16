//
//  CATControlStub.swift
//  ft8_ham
//
//  NO-OP stub implementation for public-only builds
//  Premium implementation is in private ft_ham_premium package
//
//  Created on 01/03/26.
//

import Foundation

/// Stub CAT controller that does nothing
/// Used when premium package is not available
public final class CATControlStub: CATControlProtocol {
    public static let shared = CATControlStub()
    
    private init() {}
    
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
