//
//  PremiumTelemetryProtocol.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/11/26.
//

import Foundation

/// App-side copy of `FTHamPremium.PremiumTelemetryEvent`: a failure or a
/// settings change reported by a premium service. The adapter in
/// `PremiumFeatures` maps one onto the other, so the app compiles without
/// the premium package.
struct PremiumServiceEvent: Equatable {

    enum Service: String, CaseIterable {
        case cat
        case qrz
        case lotw
        case eqsl

        var feature: AnalyticsFeature {
            switch self {
            case .cat: return .catControl
            case .qrz: return .qrzLogbook
            case .lotw: return .lotwSync
            case .eqsl: return .eqslSync
            }
        }
    }

    enum Action: String, CaseIterable {
        case connect
        case upload
        case fetchConfirmations = "fetch_confirmations"
        case saveCredentials = "save_credentials"
        case deleteCredentials = "delete_credentials"
        case importCertificate = "import_certificate"
        case deleteCertificate = "delete_certificate"
    }

    let service: Service
    let action: Action
    /// nil when the action succeeded.
    let errorCode: String?

    init(service: Service, action: Action, errorCode: String? = nil) {
        self.service = service
        self.action = action
        self.errorCode = errorCode
    }
}
