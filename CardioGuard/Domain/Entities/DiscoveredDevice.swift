//
//  DiscoveredDevice.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation

struct DiscoveredDevice: Identifiable {
    /// On a real device this is the underlying CBPeripheral's stable
    /// `identifier`, so a `BLEDeviceScanning` implementation can look the
    /// peripheral back up when `connect(to:)` is called with this value.
    let id: UUID
    let name: String
    let rssi: Int
    let type: String
}


enum ScanPhase: Equatable {
    case idle, scanning, found, connecting, connected
}
