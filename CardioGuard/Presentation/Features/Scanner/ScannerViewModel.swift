//
//  ScannerViewModel.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation
import SwiftUI

@Observable @MainActor
final class ScannerViewModel {
 
    var scanPhase: ScanPhase = .idle
    var discoveredDevices: [DiscoveredDevice] = []

    func startScan() {
        scanPhase = .scanning
        discoveredDevices = []
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard scanPhase == .scanning else { return }
            discoveredDevices = [
                DiscoveredDevice(name: "CardioGuard Pro", rssi: -52, type: "Heart Rate Monitor"),
                DiscoveredDevice(name: "HealthBand Ultra", rssi: -71, type: "Multi-sensor Band"),
            ]
            scanPhase = .found
        }
    }

    func connect(to device: DiscoveredDevice) {
        scanPhase = .connecting
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            scanPhase = .connected
        }
    }

    func stopScan() {
        scanPhase = .idle
        discoveredDevices = []
    }
}
