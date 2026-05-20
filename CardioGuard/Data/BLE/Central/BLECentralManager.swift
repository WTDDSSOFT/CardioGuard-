//
//  BLECentralManager.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation
import CoreBluetooth
import OSLog

final class BLECentralManager:  NSObject, BLECentralManaging {
    
    private var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?
    
    private let heartServiceUUID = CBUUID(string: "180D") // UUID defaultof Heart Rate
    private let measurementCharacteristicUUID = CBUUID(string: "2A37")
    
    private let parser = BLEDataParser()
    private var metricsContinuation: AsyncStream<CardioVascularMetrics>.Continuation?
    
    var metricsStream: AsyncStream<CardioVascularMetrics> {
        AsyncStream { continuation in
            self.metricsContinuation = continuation
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
        if let peripheral = discoveredPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        metricsContinuation?.finish()
    }
}

extension BLECentralManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        case .poweredOff, .unauthorized, .unsupported:
            metricsContinuation?.finish()
        default :
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        centralManager?.stopScan()
        self.discoveredPeripheral = peripheral
        self.discoveredPeripheral?.delegate = self
        
        centralManager?.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([heartServiceUUID])
    }
    
}

extension BLECentralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let services = peripheral.services else {return }
        for service in services  where service.uuid == heartServiceUUID {
            peripheral.discoverCharacteristics([measurementCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service:
                    CBService, error: (any Error)?) {
        guard let characteristics = service.characteristics else {return }
        for characteristic in characteristics where characteristic.uuid == measurementCharacteristicUUID {
            peripheral.setNotifyValue(true, for: characteristic)
            
        }
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
