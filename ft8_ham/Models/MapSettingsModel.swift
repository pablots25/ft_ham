//
//  MapSettingsModel.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//

import Foundation
import SwiftUI

/// Centralized map settings that can be shared across views
/// Uses AppStorage for persistence while providing reactive updates
class MapSettingsModel: ObservableObject {
    @AppStorage("mapShowGrids") var showGrids: Bool = true
    @AppStorage("mapShowCountryCircles") var showCountryCircles: Bool = true
    @AppStorage("mapShowGeodesics") var showGeodesics: Bool = true
    @AppStorage("mapShowAnnotations") var showAnnotations: Bool = false
    
    static let shared = MapSettingsModel()
    
    private init() {}
}
