//
//  BLECardioMonitorMock.swift
//  CardioGuardTests
//
//  Created by William Dias Dos Santos on 20/05/2026.
//
//  Test double for CardioMonitorServing. Not shipped in the app target -
//  see CardioGuard/Data/BLE/Central/SimulatedCardioMonitorService.swift for
//  the equivalent shipped Simulator fallback, which carries no test
//  instrumentation (call counts, emit()).
//

import Foundation
@testable import CardioGuard

final class BLECardioMonitorMock: CardioMonitorServing {

    // Armazenamos a continuação para conseguir enviar dados fora do bloco inicial
    private var metricsContinuation: AsyncStream<CardioVascularMetrics>.Continuation?
    private var timer: Timer?
    private let parser = BLEDataParser()

    private(set) var startMonitoringCallCount = 0
    private(set) var stopMonitoringCallCount = 0
    
    var metricsStream: AsyncStream<CardioVascularMetrics> {
        AsyncStream { continuation in
            // Guardamos a referência da continuação
            self.metricsContinuation = continuation
            

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopMonitoring()
                }
            }
        }
    }
    
    func emit(_ metrics: CardioVascularMetrics) {
        metricsContinuation?.yield(metrics)
    }

    func startMonitoring() {
        startMonitoringCallCount += 1
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let randomBPM = UInt8.random(in: 55...130)
            let randomSYS = UInt8.random(in: 100...150)
            let randomDIA = UInt8.random(in: 65...95)
            
            let rawBytes: [UInt8] = [randomBPM, randomSYS, randomDIA]
            
            do {
                // Usamos o parser que criaste anteriormente
                let decodedMetrics = try self.parser.parse(payload: rawBytes)
                
                // "Empurra" o dado decodificado para a esteira (Stream)
                self.metricsContinuation?.yield(decodedMetrics)
            } catch {
                print("Erro ao decodificar bytes: \(error)")
            }
        }
    }
    
    func stopMonitoring() {
        stopMonitoringCallCount += 1
        timer?.invalidate()
        timer = nil

        metricsContinuation?.finish()
        metricsContinuation = nil
    }
}
