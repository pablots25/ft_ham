//
//  CQModifier.swift
//  ft_ham
//
//  Created by Pablo Turrion on 02/19/26.
//

import Foundation

enum CQModifier: String, CaseIterable, Identifiable {
    case none = "NONE"
    case other = "OTHER"
    case dx = "DX"
    case eu = "EU"
    case na = "NA"
    case sa = "SA"
    case af = "AF"
    case `as` = "AS"
    case oc = "OC"
    case ant = "ANT"
    case pota = "POTA"
    case sota = "SOTA"
    case wwff = "WWFF"
    case iota = "IOTA"
    
    var id: Self { self }
}

extension CQModifier {
    enum Group: String, CaseIterable {
        case geographic = "Geographic"
        case activations = "Activations"
        case custom = "Custom"
        
        var localizedName: String {
            switch self {
            case .geographic: return String(localized: "Geographic")
            case .activations: return String(localized: "Activations")
            case .custom: return String(localized: "Custom")
            }
        }
    }
    
    var group: Group? {
        switch self {
        case .dx, .eu, .na, .sa, .af, .as, .oc, .ant:
            return .geographic
        case .pota, .sota, .wwff, .iota:
            return .activations
        case .other:
            return .custom
        case .none:
            return nil
        }
    }
    
    static func modifiers(for group: Group) -> [CQModifier] {
        allCases.filter { $0.group == group }
    }
    
    var displayName: String {
        switch self {
        case .none: return String(localized: "None")
        case .other: return String(localized: "Others")
        case .dx: return String(localized: "DX (Long distance)")
        case .eu: return String(localized: "EU (Europe)")
        case .na: return String(localized: "NA (North America)")
        case .sa: return String(localized: "SA (South America)")
        case .af: return String(localized: "AF (Africa)")
        case .as: return String(localized: "AS (Asia)")
        case .oc: return String(localized: "OC (Oceania)")
        case .ant: return String(localized: "ANT (Antarctica)")
        case .pota: return String(localized: "POTA (Parks)")
        case .sota: return String(localized: "SOTA (Summits)")
        case .wwff: return String(localized: "WWFF (Flora & Fauna)")
        case .iota: return String(localized: "IOTA (Islands)")
        }
    }
    
    var referenceLabel: String? {
        switch self {
        case .pota: return String(localized: "POTA Reference:")
        case .sota: return String(localized: "SOTA Reference:")
        case .wwff: return String(localized: "WWFF Reference:")
        case .iota: return String(localized: "IOTA Reference:")
        default: return nil
        }
    }
    
    var referencePlaceholder: String? {
        switch self {
        case .pota: return String(localized: "e.g. EA-1234")
        case .sota: return String(localized: "e.g. EA/MD-001")
        case .wwff: return String(localized: "e.g. EAFF-0456")
        case .iota: return String(localized: "e.g. EU-005")
        default: return nil
        }
    }
    
    var referenceKey: String? {
        switch self {
        case .pota: return "myPotaRef"
        case .sota: return "mySotaRef"
        case .wwff: return "myWwffRef"
        case .iota: return "myIotaRef"
        default: return nil
        }
    }
    
    var requiresReference: Bool {
        referenceLabel != nil
    }
}
