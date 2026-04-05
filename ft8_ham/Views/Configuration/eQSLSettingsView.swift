//
//  eQSLSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 05/04/26.
//
//  The authoritative eQSL Settings view lives in FTHamPremium.
//  This typealias lets callers reference `eQSLSettingsView` without
//  qualifying the module name — the premium package is the single source of truth.
//

#if canImport(FTHamPremium)
import FTHamPremium
typealias eQSLSettingsView = FTHamPremium.eQSLSettingsView
#endif
