//
//  BLECentralManager.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//
//  NOTE on GATT compliance: this scans the real, standard Bluetooth Heart
//  Rate Service (0x180D) / Measurement characteristic (0x2A37) UUIDs, but
//  the payload is decoded with this project's own custom 3-byte
//  [BPM, Systolic, Diastolic] schema (see BLEDataParser), not the real GATT
//  Heart Rate Measurement wire format (a flags byte + 8/16-bit BPM, no blood
//  pressure - that lives in an entirely separate GATT Blood Pressure Service
//  with its own format). This is deliberate for an exercise built around a
//  simulated combined payload, but it means this type would not interoperate
//  with a real off-the-shelf heart rate strap as written.
//

import Foundation
import CoreBluetooth
import OSLog

final class BLECentralManager: NSObject, BLECentralManaging {

    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    private let heartServiceUUID = CBUUID(string: "180D") // UUID defaultof Heart Rate
    private let measurementCharacteristicUUID = CBUUID(string: "2A37")

    private let parser = BLEDataParser()
    private var metricsContinuation: AsyncStream<CardioVascularMetrics>.Continuation?
    private var discoveredDevicesContinuation: AsyncStream<DiscoveredDevice>.Continuation?
    private var connectContinuation: CheckedContinuation<Void, Error>?

    var metricsStream: AsyncStream<CardioVascularMetrics> {
        AsyncStream { continuation in
            self.metricsContinuation = continuation
        }
    }

    var discoveredDevicesStream: AsyncStream<DiscoveredDevice> {
        AsyncStream { continuation in
            self.discoveredDevicesContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopScanning()
                }
            }
        }
    }

    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .userInitiated))
    }

    func startScanning() {
        guard centralManager?.state == .poweredOn else { return }
        centralManager?.scanForPeripherals(withServices: [heartServiceUUID], options: nil)
    }

    func stopScanning() {
        centralManager?.stopScan()
        metricsContinuation?.finish()
        discoveredDevicesContinuation?.finish()
    }

    /// Connects to a previously-discovered peripheral by the `id` handed out
    /// in its `DiscoveredDevice` (the peripheral's stable CoreBluetooth
    /// identifier). Suspends until CoreBluetooth reports the connection (and
    /// notification subscription) succeeded or failed.
    func connect(to deviceID: UUID) async throws {
        guard let peripheral = discoveredPeripherals[deviceID] else {
            throw BLEDeviceScanningError.deviceNotFound
        }
        peripheral.delegate = self

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
            self.centralManager?.connect(peripheral, options: nil)
        }
    }
}

extension BLECentralManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            break
        case .poweredOff, .unauthorized, .unsupported:
            metricsContinuation?.finish()
            discoveredDevicesContinuation?.finish()
        default :
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        discoveredDevicesContinuation?.yield(
            DiscoveredDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "Unknown Device",
                rssi: RSSI.intValue,
                type: "Heart Rate Monitor"
            )
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([heartServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        connectContinuation?.resume(throwing: error ?? BLEDeviceScanningError.connectionFailed)
        connectContinuation = nil
    }

}

extension BLECentralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let services = peripheral.services else {return }
        for service in services  where service.uuid == heartServiceUUID {
            peripheral.discoverCharacteristics([measurementCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service:
                    CBService, error: (any Error)?) {
        guard let characteristics = service.characteristics else {return }
        for characteristic in characteristics where characteristic.uuid == measurementCharacteristicUUID {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        if let error {
            connectContinuation?.resume(throwing: error)
        } else {
            connectContinuation?.resume()
        }
        connectContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard let data = characteristic.value else {return }

        let rawbyts = [UInt8](data)
        do {
            let metrics = try parser.parse(payload: rawbyts)
            metricsContinuation?.yield(metrics)
        } catch {
            Logger().error("Failed to parse data: \(error.localizedDescription)")
        }

    }
}
