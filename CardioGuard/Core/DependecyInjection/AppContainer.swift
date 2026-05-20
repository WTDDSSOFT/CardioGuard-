//
//  AppContainer.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation

final class AppContainer {
    static let shared = AppContainer()

    private(set) lazy var router = AppRouter()

    private init() {}

    func makeCardioMonitorService() -> CardioMonitorServing {
        #if targetEnvironment(simulator)
        return BLECardioMonitorMock()
        #else
        return BLECardioMonitorRepository(central: BLECentralManager())
        #endif
    }

    func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(monitorService: makeCardioMonitorService())
    }

    func makeScannerViewModel() -> ScannerViewModel {
        ScannerViewModel()
    }
}
