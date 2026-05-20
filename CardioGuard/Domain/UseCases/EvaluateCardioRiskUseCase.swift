//
//  EvaluateCardioRiskUseCase.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import Foundation

struct EvaluateCardioRiskUseCase {
    // Standard clinical thresholds:
    //   BPM:        bradycardia < 60, tachycardia > 100
    //   Systolic:   hypotension < 90, hypertension > 140
    //   Diastolic:  hypotension < 60, hypertension > 90
    
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
}

fileprivate struct BPMClinicalThresholds: EvaluateCardioRiskUseSG {
    func evaluate(_ clinicalThreshold: CardioVascularMetrics) -> [HealthStatusAlert]? {
        var healthStatusAlerts = Array<HealthStatusAlert>()
        if clinicalThreshold.BPM < 60 {
            healthStatusAlerts.append(.bradycardia)
        } else if clinicalThreshold.BPM > 100 {
            healthStatusAlerts.append(.tachycardia)
        }
        return healthStatusAlerts
    }
}

fileprivate struct SystolicClinicalThresholds: EvaluateCardioRiskUseSG {
    func evaluate(_ clinicalThreshold: CardioVascularMetrics) -> [HealthStatusAlert]? {
        var healthStatusAlerts: [HealthStatusAlert] = []
        
        if clinicalThreshold.SystoliC < 90 {
            healthStatusAlerts.append(.hypotension)
        } else if clinicalThreshold.SystoliC > 140 {
            healthStatusAlerts.append(.hypertension)
        }
        return healthStatusAlerts
    }
}

fileprivate struct DiastolicClinicalThresholds: EvaluateCardioRiskUseSG {
    func evaluate(_ clinicalThreshold: CardioVascularMetrics) -> [HealthStatusAlert]? {
        var healthStatusAlerts: [HealthStatusAlert] = []
        
        if clinicalThreshold.Diastolic < 60 {
            healthStatusAlerts.append(.hypotension)
        } else if clinicalThreshold.Diastolic > 90 {
            healthStatusAlerts.append(.hypertension)
        }
        return healthStatusAlerts
    }
}
