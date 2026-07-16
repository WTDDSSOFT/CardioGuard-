//
//  AIRiskPrediction.swift
//  CardioGuard
//
//  Output of the on-device early-warning model (see MLPipeline/).
//

import Foundation

/// Where a prediction actually came from. Surfaced so the UI/fallback logic
/// can be honest about whether the on-device model answered, or whether a
/// remote (cloud) model had to cover for it.
enum PredictionSource: Equatable {
    case onDevice
    case cloud
}

struct AIRiskPrediction: Equatable {
    /// Probability, 0...1, that a clinical crisis (per EvaluateCardioRiskUseCase)
    /// occurs within the next few BLE readings.
    let riskScore: Double

    /// Defaults to `.onDevice` so existing call sites (`AIRiskPrediction(riskScore:)`)
    /// keep compiling unchanged; only `HybridCardioRiskPredictor` ever passes `.cloud`.
    let source: PredictionSource

    init(riskScore: Double, source: PredictionSource = .onDevice) {
        self.riskScore = riskScore
        self.source = source
    }

    /// Threshold picked to favor recall over precision: an early warning that
    /// is occasionally too eager is preferable to one that misses a real trend.
    /// Matches the operating point evaluated in MLPipeline/reference_validation.
    var isElevated: Bool { riskScore >= 0.6 }
}
