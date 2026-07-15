//
//  AIRiskPrediction.swift
//  CardioGuard
//
//  Output of the on-device early-warning model (see MLPipeline/).
//

import Foundation

struct AIRiskPrediction: Equatable {
    /// Probability, 0...1, that a clinical crisis (per EvaluateCardioRiskUseCase)
    /// occurs within the next few BLE readings.
    let riskScore: Double

    /// Threshold picked to favor recall over precision: an early warning that
    /// is occasionally too eager is preferable to one that misses a real trend.
    /// Matches the operating point evaluated in MLPipeline/reference_validation.
    var isElevated: Bool { riskScore >= 0.6 }
}
