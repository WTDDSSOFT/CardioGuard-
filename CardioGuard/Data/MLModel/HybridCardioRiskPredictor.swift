//
//  HybridCardioRiskPredictor.swift
//  CardioGuard
//
//  Local/cloud fallback strategy: always prefers the on-device model
//  (privacy, latency, works offline); only calls the remote model if the
//  local one throws (missing/uninitialized bundle, prediction failure).
//  The network path is a safety net, never a general performance shortcut -
//  on-device inference is not "slow", so there's no reason to race the two
//  or prefer the network under normal conditions.
//

import Foundation

final class HybridCardioRiskPredictor: CardioRiskPredicting {

    private let local: CardioRiskPredicting
    private let remote: CardioRiskPredicting

    init(local: CardioRiskPredicting, remote: CardioRiskPredicting) {
        self.local = local
        self.remote = remote
    }

    func predict(window: [CardioVascularMetrics]) async throws -> AIRiskPrediction {
        do {
            return try await local.predict(window: window)
        } catch {
            // Local failed (model not bundled, prediction error, ...) - fall
            // back to the remote model. If that also fails, its error
            // propagates and DashboardViewModel's `try?` just leaves
            // aiRiskPrediction as nil, same as today.
            return try await remote.predict(window: window)
        }
    }
}
