//
//  BLECentralManaging.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation

protocol BLECentralManaging: AnyObject {
    var metricsStream: AsyncStream<CardioVascularMetrics> { get }
    var discoveredDevicesStream: AsyncStream<DiscoveredDevice> { get }
    func startScanning()
    func stopScanning()
    func connect(to deviceID: UUID) async throws
}
