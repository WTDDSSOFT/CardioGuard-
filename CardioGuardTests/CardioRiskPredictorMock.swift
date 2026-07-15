//
//  CardioRiskPredictorMock.swift
//  CardioGuardTests
//
//  Test double for CardioRiskPredicting. Lets CardioAIPredictionTests
//  exercise the AI-window wiring in DashboardViewModel without needing a
//  real Core ML model bundled anywhere.
//

import Foundation
@testable import CardioGuard

final class CardioRiskPredictorMock: CardioRiskPredicting {

    var stubbedPrediction: AIRiskPrediction = AIRiskPrediction(riskScore: 0)
    var stubbedError: Error?

    private(set) var predictCallCount = 0
    private(set) var lastWindow: [CardioVascularMetrics]?

    func predict(window: [CardioVascularMetrics]) async throws -> AIRiskPrediction {
        predictCallCount += 1
        lastWindow = window
        if let stubbedError {
            throw stubbedError
        }
        return stubbedPrediction
    }
}
