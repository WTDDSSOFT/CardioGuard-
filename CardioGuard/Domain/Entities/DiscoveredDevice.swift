//
//  DiscoveredDevice.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let name: String
    let rssi: Int
    let type: String
}


enum ScanPhase: Equatable {
    case idle, scanning, found, connecting, connected
}
