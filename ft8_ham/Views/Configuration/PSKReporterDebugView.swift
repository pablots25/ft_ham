//
//  PSKReporterDebugView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//
//  The authoritative PSK Reporter Debug View view lives in FTHamPremium.
//  This typealias lets callers reference `PSKReporterDebugView` without
//  qualifying the module name — the premium package is the single source of truth.
//

#if canImport(FTHamPremium)
import FTHamPremium
typealias PSKReporterDebugView = FTHamPremium.PSKReporterDebugView
#endif
