//
//  DashboardViewModel.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Foundation

@MainActor @Observable
final class DashboardViewModel {

    // Estados que a View SwiftUI vai observar
    var currentMetrics: CardioVascularMetrics?
    var alertState: HealthStatusAlert = .normal
    var isMonitoring = false

    /// Predictive signal from the on-device Core ML model (see MLPipeline/),
    /// updated once enough readings have accumulated to fill a window. `nil`
    /// until then, or if the model isn't bundled / prediction failed.
    var aiRiskPrediction: AIRiskPrediction?

    private let monitorService: CardioMonitorServing
    private let riskUseCase: EvaluateCardioRiskUseCase
    private let aiPredictor: CardioRiskPredicting
    private var monitoringTask: Task<Void, Never>?

    /// Rolling window of the most recent readings fed to the AI predictor.
    private var recentReadings: [CardioVascularMetrics] = []

    init(
        monitorService: CardioMonitorServing,
        riskUseCase: EvaluateCardioRiskUseCase = EvaluateCardioRiskUseCase(),
        aiPredictor: CardioRiskPredicting = NoOpCardioRiskPredictor()
    ) {
        self.monitorService = monitorService
        self.riskUseCase = riskUseCase
        self.aiPredictor = aiPredictor
    }

    func toggleMonitoring() {
        if isMonitoring {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        isMonitoring = true
        monitorService.startMonitoring()

        // Criamos uma Task assíncrona para escutar o fluxo sem travar a main thread
        monitoringTask = Task {
            // Fica à escuta na "esteira rolante". O loop espera de forma assíncrona o próximo valor
            for await metrics in monitorService.metricsStream {
                // Como a classe está anotada com @MainActor, esta atualização é thread-safe para a UI
                self.currentMetrics = metrics
                self.evaluateRisks(metrics: metrics)
                await self.updateAIPrediction(with: metrics)
            }
        }
    }

    private func stop() {
        isMonitoring = false
        // Requisito 4: Cancelar a Task cancela o AsyncStream graças ao `onTermination`
        monitoringTask?.cancel()
        monitoringTask = nil
        monitorService.stopMonitoring()
    }

    /// Instant, deterministic clinical-threshold evaluation (reactive).
    private func evaluateRisks(metrics: CardioVascularMetrics) {
        alertState = riskUseCase.primaryAlert(for: metrics)
    }

    /// Predictive, trend-based evaluation (proactive): once the rolling
    /// window has enough readings, ask the on-device model whether a crisis
    /// is likely within the next few readings - even if every individual
    /// reading so far is still within the clinical thresholds above.
    private func updateAIPrediction(with metrics: CardioVascularMetrics) async {
        recentReadings.append(metrics)
        if recentReadings.count > CardioRiskPredictorConfig.windowSize {
            recentReadings.removeFirst()
        }
        guard recentReadings.count == CardioRiskPredictorConfig.windowSize else { return }

        aiRiskPrediction = try? await aiPredictor.predict(window: recentReadings)
    }

    // Garante que se a ViewModel for destruída, a recolha de dados para
    deinit {
        Task { @MainActor [weak self] in
            self?.monitoringTask?.cancel()
        }
    }
}
