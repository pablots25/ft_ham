//
//  PSKReporterReporter.swift
//  ft_ham
//
//  Created by Pablo Turrion on 27/02/26.
//

import Foundation

#if canImport(FTHamPremium)
import FTHamPremium

/// Backward-compatible alias to the premium implementation.
@available(*, deprecated, message: "Use PremiumFeatures.pskReporter instead")
typealias PSKReporterReporter = FTHamPremium.PSKReporterReporter

#else

/// Compatibility placeholder for builds without premium linkage.
@available(*, deprecated, message: "Use PremiumFeatures.pskReporter instead")
final class PSKReporterReporter: ObservableObject {
    static let shared = PSKReporterReporter()
    private init() {}
}

#endif
