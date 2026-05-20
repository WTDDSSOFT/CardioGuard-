//
//  BLECardioMonitorRepository.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation

final class BLECardioMonitorRepository: CardioMonitorServing {

    private let central: BLECentralManaging

    init(central: BLECentralManaging) {
        self.central = central
    }

    var metricsStream: AsyncStream<CardioVascularMetrics> {
        central.metricsStream
    }

    func startMonitoring() {
        central.startScanning()
    }

    func stopMonitoring() {
        central.stopScanning()
    }
}
