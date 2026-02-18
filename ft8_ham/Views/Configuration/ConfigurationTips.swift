//
//  ConfigurationTips.swift
//  ft_ham
//
//  Created by Pablo Turrion on 02/18/26.
//

import SwiftUI
import TipKit

// MARK: - TipKit Tips (iOS 17+)

@available(iOS 17, *)
struct AutoRXAtStartTip: Tip {
    var title: Text {
        Text("Auto-start RX")
    }

    var message: Text? {
        Text("Automatically starts RX when the app launches if your settings are valid.")
    }
}

@available(iOS 17, *)
struct AutoCQReplyTip: Tip {
    var title: Text {
        Text("Auto-reply to CQ")
    }

    var message: Text? {
        Text("Automatically responds to incoming CQs when auto-sequencing is enabled.")
    }
}

@available(iOS 17, *)
struct AutoCQNewBandModeTip: Tip {
    var title: Text {
        Text("New band/mode only")
    }

    var message: Text? {
        Text("Only auto-reply to a CQ if that callsign is not yet confirmed on the current band and mode.")
    }
}

@available(iOS 17, *)
struct DecodeSelfTXTip: Tip {
    var title: Text {
        Text("Include transmitted messages")
    }

    var message: Text? {
        Text("Your transmitted messages will be included in the RX list so you can review them.")
    }
}

@available(iOS 17, *)
struct HoldTXFrequencyTip: Tip {
    var title: Text {
        Text("Keep TX frequency fixed")
    }

    var message: Text? {
        Text("TX frequency will remain fixed and won't auto-align to incoming DX frequency.")
    }
}

@available(iOS 17, *)
struct AutoSequencingTip: Tip {
    var title: Text {
        Text("Auto-advance QSO sequence")
    }

    var message: Text? {
        Text("Automatically advances through QSO stages based on received messages.")
    }
}

@available(iOS 17, *)
struct AutoQSOLoggingTip: Tip {
    var title: Text {
        Text("Auto-log completed QSOs")
    }

    var message: Text? {
        Text("Completed QSOs will be logged automatically without requiring your confirmation.")
    }
}

@available(iOS 17, *)
struct AnalyticsTip: Tip {
    var title: Text {
        Text("Anonymous usage analytics")
    }

    var message: Text? {
        Text("Help improve the app by sharing anonymous usage statistics. No personal data is collected.")
    }
}
