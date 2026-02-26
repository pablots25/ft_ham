//
//  LayoutConstants.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//

import CoreGraphics

/// Centralized layout constants for consistent spacing and styling throughout the app
enum LayoutConstants {
    // MARK: - Padding
    static let standardPadding: CGFloat = 12
    static let compactPadding: CGFloat = 8
    static let largePadding: CGFloat = 20
    static let ipadPadding: CGFloat = 30
    
    // MARK: - Spacing
    static let standardSpacing: CGFloat = 12
    static let compactSpacing: CGFloat = 8
    static let largeSpacing: CGFloat = 20
    static let headerSpacing: CGFloat = 50
    
    // MARK: - Corner Radius
    static let standardCornerRadius: CGFloat = 12
    static let largeCornerRadius: CGFloat = 25
    
    // MARK: - Heights
    static let controlBarHeight: CGFloat = 40
    static let progressBarMaxWidth: CGFloat = 400
    
    // MARK: - Animation
    static let springResponse: CGFloat = 0.4
    static let springDamping: CGFloat = 0.75
    static let springBlending: CGFloat = 0.3
}
