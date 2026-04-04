//
//  LoTWSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//
//  The authoritative LoTW Settings view lives in FTHamPremium.
//  This typealias lets callers reference `LoTWSettingsView` without
//  qualifying the module name — the premium package is the single source of truth.
//

#if canImport(FTHamPremium)
import FTHamPremium
typealias LoTWSettingsView = FTHamPremium.LoTWSettingsView
#endif
