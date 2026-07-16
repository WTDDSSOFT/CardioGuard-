//
//  AppContainer.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation

final class AppContainer {
    static let shared = AppContainer()

    private let runEnvironment: RunEnvironment

    /// Shared between the monitor service and the device scanner in the
    /// `.live` case, so a device connected to via the Scanner is the same
    /// CoreBluetooth session the Dashboard's metricsStream reads from,
    /// rather than two independent, unconnected CBCentralManager instances.
    private lazy var centralManager = BLECentralManager()

    init(runEnvironment: RunEnvironment = .current) {
        self.runEnvironment = runEnvironment
    }

    func makeCardioMonitorService() -> CardioMonitorServing {
        switch runEnvironment {
        case .simulated: return SimulatedCardioMonitorService()
        case .live: return BLECardioMonitorRepository(central: centralManager)
        }
    }

    /// Local-first, cloud-fallback: prefers the on-device Core ML model, and
    /// only falls back to `RemoteCardioRiskPredictor` if the local model is
    /// unavailable or a prediction fails. With no cloud endpoint configured
    /// (`CloudInferenceConfig.endpoint == nil`, the default), this behaves
    /// exactly like the on-device-only predictor did before - the fallback
    /// path is inert until a real backend exists.
    func makeCardioRiskPredictor() -> CardioRiskPredicting {
        HybridCardioRiskPredictor(
            local: CoreMLCardioRiskPredictor(),
            remote: RemoteCardioRiskPredictor()
        )
    }

    func makeDeviceScanner() -> BLEDeviceScanning {
        switch runEnvironment {
        case .simulated: return SimulatedBLEDeviceScanner()
        case .live: return BLEDeviceScannerRepository(central: centralManager)
        }
    }

    func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(
            monitorService: makeCardioMonitorService(),
            aiPredictor: makeCardioRiskPredictor()
        )
    }

    func makeScannerViewModel() -> ScannerViewModel {
        ScannerViewModel(deviceScanner: makeDeviceScanner())
    }
}
