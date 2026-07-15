//
//  EvaluateCardioRiskUseCase.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import Foundation

struct EvaluateCardioRiskUseCase {
    // Clinical thresholds (must match README §2 "Business Rules & Alerting"
    // and MLPipeline/generate_data.py's `is_crisis`, which the predictive
    // Core ML model is trained to anticipate):
    //   BPM:        bradycardia < 50, tachycardia > 120
    //   Systolic:   hypotension < 90, hypertension > 140
    //   Diastolic:  hypertension > 90

    // Priority order used to resolve a single alertState when several
    // alerts fire at once (mirrors the previous inline if/else chain in
    // DashboardViewModel).
    static let priority: [HealthStatusAlert] = [.hypertension, .hypotension, .tachycardia, .bradycardia]

    private let strategy: [EvaluateCardioRiskUseSG] = [
        BPMClinicalThresholds(),
        SystolicClinicalThresholds(),
        DiastolicClinicalThresholds()
    ]

    func evaluate(_ cardioMetrics: CardioVascularMetrics) -> [HealthStatusAlert] {
        let alerts = strategy.compactMap { $0.evaluate(cardioMetrics) }.flatMap { $0 }
        var seen = Set<HealthStatusAlert>()
        return alerts.filter { seen.insert($0).inserted }
    }

    /// Convenience for the dashboard: a single alert state, resolved by
    /// clinical priority (hypertension > hypotension > tachycardia >
    /// bradycardia), defaulting to `.normal` when nothing fires.
    func primaryAlert(for cardioMetrics: CardioVascularMetrics) -> HealthStatusAlert {
        let alerts = Set(evaluate(cardioMetrics))
        return Self.priority.first(where: alerts.contains) ?? .normal
    }
}

fileprivate struct BPMClinicalThresholds: EvaluateCardioRiskUseSG {
    func evaluate(_ clinicalThreshold: CardioVascularMetrics) -> [HealthStatusAlert]? {
        var healthStatusAlerts = Array<HealthStatusAlert>()
        if clinicalThreshold.BPM > 120 {
            healthStatusAlerts.append(.tachycardia)
        } else if clinicalThreshold.BPM < 50 {
            healthStatusAlerts.append(.bradycardia)
        }
        return healthStatusAlerts
    }
}

fileprivate struct SystolicClinicalThresholds: EvaluateCardioRiskUseSG {
    func evaluate(_ clinicalThreshold: CardioVascularMetrics) -> [HealthStatusAlert]? {
        var healthStatusAlerts: [HealthStatusAlert] = []

        if clinicalThreshold.SystoliC > 140 {
            healthStatusAlerts.append(.hypertension)
        } else if clinicalThreshold.SystoliC < 90 {
            healthStatusAlerts.append(.hypotension)
        }
        return healthStatusAlerts
    }
}

fileprivate struct DiastolicClinicalThresholds: EvaluateCardioRiskUseSG {
    func evaluate(_ clinicalThreshold: CardioVascularMetrics) -> [HealthStatusAlert]? {
        var healthStatusAlerts: [HealthStatusAlert] = []

        if clinicalThreshold.Diastolic > 90 {
            healthStatusAlerts.append(.hypertension)
        }
        return healthStatusAlerts
    }
}
