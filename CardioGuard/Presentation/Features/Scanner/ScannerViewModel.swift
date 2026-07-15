//
//  ScannerViewModel.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation

@Observable @MainActor
final class ScannerViewModel {

    var scanPhase: ScanPhase = .idle
    var discoveredDevices: [DiscoveredDevice] = []

    private let deviceScanner: BLEDeviceScanning
    private var scanTask: Task<Void, Never>?

    init(deviceScanner: BLEDeviceScanning) {
        self.deviceScanner = deviceScanner
    }

    func startScan() {
        scanPhase = .scanning
        discoveredDevices = []
        deviceScanner.startScan()

        scanTask = Task { [weak self] in
            guard let self else { return }
            for await device in self.deviceScanner.discoveredDevicesStream {
                self.discoveredDevices.append(device)
                if self.scanPhase == .scanning {
                    self.scanPhase = .found
                }
            }
        }
    }

    func connect(to device: DiscoveredDevice) {
        scanPhase = .connecting
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.deviceScanner.connect(to: device)
                self.scanPhase = .connected
            } catch {
                self.scanPhase = .found
            }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        deviceScanner.stopScan()
        scanPhase = .idle
        discoveredDevices = []
    }
}
