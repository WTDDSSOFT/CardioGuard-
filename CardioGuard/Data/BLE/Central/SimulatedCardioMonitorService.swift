//
//  SimulatedCardioMonitorService.swift
//  CardioGuard
//
//  Shipped fallback for CardioMonitorServing used on the Simulator, where
//  real CoreBluetooth hardware isn't available - generates plausible-looking
//  readings on a timer through the same BLEDataParser real devices use.
//
//  This is intentionally separate from BLECardioMonitorMock (CardioGuardTests/),
//  which is a test double carrying call-count instrumentation that has no
//  business shipping inside the app bundle.
//

import Foundation

final class SimulatedCardioMonitorService: CardioMonitorServing {

    private var metricsContinuation: AsyncStream<CardioVascularMetrics>.Continuation?
    private var timer: Timer?
    private let parser = BLEDataParser()

    var metricsStream: AsyncStream<CardioVascularMetrics> {
        AsyncStream { continuation in
            self.metricsContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopMonitoring()
                }
            }
        }
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }

            let randomBPM = UInt8.random(in: 55...130)
            let randomSystolic = UInt8.random(in: 100...150)
            let randomDiastolic = UInt8.random(in: 65...95)
            let rawBytes: [UInt8] = [randomBPM, randomSystolic, randomDiastolic]

            do {
                let decodedMetrics = try self.parser.parse(payload: rawBytes)
                self.metricsContinuation?.yield(decodedMetrics)
            } catch {
                print("Erro ao decodificar bytes: \(error)")
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        metricsContinuation?.finish()
        metricsContinuation = nil
    }
}
