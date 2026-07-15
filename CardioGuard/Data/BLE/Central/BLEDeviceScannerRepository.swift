//
//  BLEDeviceScannerRepository.swift
//  CardioGuard
//
//  Adapts BLECentralManaging (CoreBluetooth-shaped) to BLEDeviceScanning
//  (the Domain-facing protocol ScannerViewModel depends on) - mirrors how
//  BLECardioMonitorRepository adapts the same central manager for metrics.
//

import Foundation

final class BLEDeviceScannerRepository: BLEDeviceScanning {

    private let central: BLECentralManaging

    init(central: BLECentralManaging) {
        self.central = central
    }

    var discoveredDevicesStream: AsyncStream<DiscoveredDevice> {
        central.discoveredDevicesStream
    }

    func startScan() {
        central.startScanning()
    }

    func stopScan() {
        central.stopScanning()
    }

    func connect(to device: DiscoveredDevice) async throws {
        try await central.connect(to: device.id)
    }
}
