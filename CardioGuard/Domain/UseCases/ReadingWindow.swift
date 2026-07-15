//
//  ReadingWindow.swift
//  CardioGuard
//
//  Sliding buffer of the most recent readings fed to the on-device predictor
//  (see CardioRiskPredicting). Pulled out of DashboardViewModel so the
//  ViewModel doesn't also own window bookkeeping alongside UI state.
//

import Foundation

struct ReadingWindow {
    private(set) var readings: [CardioVascularMetrics] = []
    private let size: Int

    init(size: Int = CardioRiskPredictorConfig.windowSize) {
        self.size = size
    }

    /// - Returns: the full window once `size` readings have accumulated,
    ///   `nil` otherwise.
    mutating func appending(_ metrics: CardioVascularMetrics) -> [CardioVascularMetrics]? {
        readings.append(metrics)
        if readings.count > size {
            readings.removeFirst()
        }
        return readings.count == size ? readings : nil
    }
}
