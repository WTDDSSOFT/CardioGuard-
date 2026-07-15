//
//  CardioRiskPredicting.swift
//  CardioGuard
//
//  Abstraction over the on-device early-warning model, so DashboardViewModel
//  depends only on the Domain layer and never imports CoreML directly.
//

import Foundation

enum CardioRiskPredictorConfig {
    /// Number of most-recent readings the model looks at.
    /// Must match WINDOW_SIZE in MLPipeline/generate_data.py.
    static let windowSize = 6
}

enum CardioRiskPredictingError: Error {
    case invalidWindowSize
    case modelUnavailable
    case predictionFailed
}

protocol CardioRiskPredicting {
    /// - Parameter window: the most recent readings, oldest first. Must
    ///   contain exactly `CardioRiskPredictorConfig.windowSize` elements.
    func predict(window: [CardioVascularMetrics]) async throws -> AIRiskPrediction
}

/// Default predictor used when nothing else is injected (keeps existing call
/// sites/tests that only provide a `monitorService` compiling unchanged).
/// Always reports zero risk, so it never needs a bundled Core ML model.
struct NoOpCardioRiskPredictor: CardioRiskPredicting {
    func predict(window: [CardioVascularMetrics]) async throws -> AIRiskPrediction {
        AIRiskPrediction(riskScore: 0)
    }
}
