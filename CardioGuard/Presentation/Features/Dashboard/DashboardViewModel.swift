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
    
    private let monitorService: CardioMonitorServing
    private var monitoringTask: Task<Void, Never>?
    
    init(monitorService: CardioMonitorServing) {
        self.monitorService = monitorService
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
    
    private func evaluateRisks(metrics: CardioVascularMetrics) {
        // Aqui entra o teu UseCase ou lógica do Requisito 2 (Crises)
        if metrics.SystoliC > 140 || metrics.Diastolic > 90 {
            alertState = .hypertension
        } else if metrics.SystoliC < 90 {
            alertState = .hypotension
        } else if metrics.BPM > 120 {
            alertState = .tachycardia
        } else if metrics.BPM < 50 {
            alertState = .bradycardia
        } else {
            alertState = .normal
        }
    }
    
    // Garante que se a ViewModel for destruída, a recolha de dados para
    deinit {
        Task { @MainActor [weak self] in
            self?.monitoringTask?.cancel()
        }
    }
}
