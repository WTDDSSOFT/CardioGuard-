//
//  EvaluateCardioRiskUseSG.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation
protocol EvaluateCardioRiskUseSG {
    func evaluate(_ cardioMetrics: CardioVascularMetrics) -> [HealthStatusAlert]?
}
