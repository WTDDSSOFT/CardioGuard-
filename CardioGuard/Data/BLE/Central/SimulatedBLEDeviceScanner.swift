//
//  SimulatedBLEDeviceScanner.swift
//  CardioGuard
//
//  Shipped fallback for BLEDeviceScanning used on the Simulator, where real
//  CoreBluetooth scanning isn't available - yields two plausible-looking
//  devices shortly after a scan starts, and "connects" after a short delay.
//

import Foundation

final class SimulatedBLEDeviceScanner: BLEDeviceScanning {

    private var continuation: AsyncStream<DiscoveredDevice>.Continuation?
    private var scanTask: Task<Void, Never>?

    var discoveredDevicesStream: AsyncStream<DiscoveredDevice> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func startScan() {
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled else { return }
            self.continuation?.yield(DiscoveredDevice(id: UUID(), name: "CardioGuard Pro", rssi: -52, type: "Heart Rate Monitor"))
            self.continuation?.yield(DiscoveredDevice(id: UUID(), name: "HealthBand Ultra", rssi: -71, type: "Multi-sensor Band"))
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        continuation?.finish()
    }

    func connect(to device: DiscoveredDevice) async throws {
        try await Task.sleep(for: .seconds(1.5))
    }
}
