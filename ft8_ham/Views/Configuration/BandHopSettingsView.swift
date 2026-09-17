//
//  BandHopSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//
//  The authoritative band-hopping settings view lives in FTHamPremium; this
//  typealias lets callers reference `BandHopSettingsView` unqualified.
//  Without the package, `BandHopSettingsViewStub` provides the same name.
//

#if canImport(FTHamPremium)
import FTHamPremium
typealias BandHopSettingsView = FTHamPremium.BandHopSettingsView
#endif
