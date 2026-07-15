//
//  BLEDeviceScanning.swift
//  CardioGuard
//
//  Abstraction over "discover nearby devices, then connect to one", so
//  ScannerViewModel depends only on the Domain layer and never imports
//  CoreBluetooth directly - mirrors how CardioMonitorServing decouples
//  DashboardViewModel from it.
//

import Foundation

enum BLEDeviceScanningError: Error {
    case deviceNotFound
    case connectionFailed
}

protocol BLEDeviceScanning {
    var discoveredDevicesStream: AsyncStream<DiscoveredDevice> { get }
    func startScan()
    func stopScan()
    func connect(to device: DiscoveredDevice) async throws
}
