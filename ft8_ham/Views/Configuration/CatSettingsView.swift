//
//  CatSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//
//  The authoritative CAT Settings view lives in FTHamPremium.
//  This typealias lets callers reference `CatSettingsView` without
//  qualifying the module name — the premium package is the single source of truth.
//

#if canImport(FTHamPremium)
import FTHamPremium
typealias CatSettingsView = FTHamPremium.CatSettingsView
#endif
