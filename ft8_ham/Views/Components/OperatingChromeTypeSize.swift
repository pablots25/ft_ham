//
//  OperatingChromeTypeSize.swift
//  ft_ham
//
//  Created by Pablo Turrion on 29/09/26.
//

import SwiftUI

/// Dynamic Type limits for the operating chrome: the app title, status and
/// clock, and the TX/RX buttons that sit above the decode list and the
/// waterfall on every operating screen. That chrome shares a fixed band of
/// the screen with the content, so at accessibility sizes it would push the
/// decodes and the waterfall off screen. It grows up to `limit`, and past
/// that the Large Content Viewer shows the enlarged label on long press.
enum OperatingChromeTypeSize {
    static let limit: DynamicTypeSize = .accessibility1
    static let range: PartialRangeThrough<DynamicTypeSize> = ...limit
}

extension View {
    /// Caps Dynamic Type for operating chrome. See `OperatingChromeTypeSize`.
    func operatingChromeTypeSize() -> some View {
        dynamicTypeSize(OperatingChromeTypeSize.range)
    }
}
