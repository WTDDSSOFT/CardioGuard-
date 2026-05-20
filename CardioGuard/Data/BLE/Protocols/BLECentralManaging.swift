//
//  BLECentralManaging.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

protocol BLECentralManaging: AnyObject {
    var metricsStream: AsyncStream<CardioVascularMetrics> { get }
    func startScanning()
    func stopScanning()
}
