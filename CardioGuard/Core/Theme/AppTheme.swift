//
//  AppTheme.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import SwiftUI

enum AppTheme {

    enum Colors {
        static let heartRate = Color.red
        static let bloodPressure = Color.blue
        static let liveMonitoring = Color.green
        static let warning = Color.orange
        static let critical = Color.red
        static let bluetoothSignal = Color.blue
    }

    enum Radius {
        static let tag: CGFloat = 14
        static let button: CGFloat = 16
        static let actionButton: CGFloat = 18
        static let card: CGFloat = 20
    }

    enum Spacing {
        static let tight: CGFloat = 8
        static let compact: CGFloat = 12
        static let standard: CGFloat = 16
        static let comfortable: CGFloat = 22
        static let loose: CGFloat = 24
        static let safeAreaBottom: CGFloat = 32
    }

    enum Animation {
        static let backgroundTransition = SwiftUI.Animation.easeInOut(duration: 0.6)
        static let stateChange = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let metricUpdate = SwiftUI.Animation.easeOut(duration: 0.3)
        static let buttonToggle = SwiftUI.Animation.spring(response: 0.3)
        static let listTransition = SwiftUI.Animation.spring(response: 0.4)
    }
}
