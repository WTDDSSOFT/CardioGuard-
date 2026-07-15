//
//  CardioAIPredictionTests.swift
//  CardioGuardTests
//
//  Verifies the DashboardViewModel <-> CardioRiskPredicting wiring: the
//  on-device model should only be consulted once the rolling window of
//  readings is full, and its output should surface as `aiRiskPrediction`.
//

import Testing
@testable import CardioGuard

@MainActor
@Suite("CardioAIPredictionTests", .tags(.success, .failure))
struct CardioAIPredictionTests {

    private func emitNormalReadings(_ count: Int, mock: BLECardioMonitorMock) async {
        for _ in 0..<count {
            mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 120, Diastolic: 80))
            await Task.yield()
            await Task.yield()
        }
    }

    @Test("Predictor is not called before the window fills", .tags(.success))
    func predictorNotCalledBeforeWindowFills() async {
        let bleMock = BLECardioMonitorMock()
        let aiMock = CardioRiskPredictorMock()
        let vm = DashboardViewModel(monitorService: bleMock, aiPredictor: aiMock)

        vm.toggleMonitoring()
        await Task.yield()

        await emitNormalReadings(CardioRiskPredictorConfig.windowSize - 1, mock: bleMock)

        #expect(aiMock.predictCallCount == 0)
        #expect(vm.aiRiskPrediction == nil)
    }

    @Test("Predictor is called once the window fills, and its output surfaces", .tags(.success))
    func predictorCalledOnceWindowFills() async {
        let bleMock = BLECardioMonitorMock()
        let aiMock = CardioRiskPredictorMock()
        aiMock.stubbedPrediction = AIRiskPrediction(riskScore: 0.82)
        let vm = DashboardViewModel(monitorService: bleMock, aiPredictor: aiMock)

        vm.toggleMonitoring()
        await Task.yield()

        await emitNormalReadings(CardioRiskPredictorConfig.windowSize, mock: bleMock)

        #expect(aiMock.predictCallCount == 1)
        #expect(aiMock.lastWindow?.count == CardioRiskPredictorConfig.windowSize)
        #expect(vm.aiRiskPrediction?.riskScore == 0.82)
        #expect(vm.aiRiskPrediction?.isElevated == true)
    }

    @Test("Window keeps sliding (stays at windowSize) after it first fills", .tags(.success))
    func windowSlidesAfterFilling() async {
        let bleMock = BLECardioMonitorMock()
        let aiMock = CardioRiskPredictorMock()
        let vm = DashboardViewModel(monitorService: bleMock, aiPredictor: aiMock)

        vm.toggleMonitoring()
        await Task.yield()

        await emitNormalReadings(CardioRiskPredictorConfig.windowSize + 3, mock: bleMock)

        #expect(aiMock.predictCallCount == 4) // fired once per reading once the window is full
        #expect(aiMock.lastWindow?.count == CardioRiskPredictorConfig.windowSize)
    }

    @Test("A failing predictor leaves aiRiskPrediction nil instead of crashing", .tags(.failure))
    func predictorFailureIsHandledGracefully() async {
        let bleMock = BLECardioMonitorMock()
        let aiMock = CardioRiskPredictorMock()
        aiMock.stubbedError = CardioRiskPredictingError.modelUnavailable
        let vm = DashboardViewModel(monitorService: bleMock, aiPredictor: aiMock)

        vm.toggleMonitoring()
        await Task.yield()

        await emitNormalReadings(CardioRiskPredictorConfig.windowSize, mock: bleMock)

        #expect(aiMock.predictCallCount == 1)
        #expect(vm.aiRiskPrediction == nil)
    }

    @Test("Default DashboardViewModel init (no AI predictor injected) never crashes and stays at zero risk", .tags(.success))
    func defaultNoOpPredictorIsSafe() async {
        let bleMock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: bleMock) // uses NoOpCardioRiskPredictor by default

        vm.toggleMonitoring()
        await Task.yield()

        await emitNormalReadings(CardioRiskPredictorConfig.windowSize, mock: bleMock)

        #expect(vm.aiRiskPrediction?.riskScore == 0)
        #expect(vm.aiRiskPrediction?.isElevated == false)
    }
}
