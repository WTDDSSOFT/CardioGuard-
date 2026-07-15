//
//  DashboardViewModelTests.swift
//  CardioGuardTests
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import Testing
@testable import CardioGuard

@MainActor
@Suite("DashboardViewModelTests", .tags(.success, .failure))
struct DashboardViewModelTests {

    // MARK: - Initial State

    @Test("Initial state: not monitoring, no metrics, alert is normal", .tags(.success))
    func initialState() {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        #expect(vm.isMonitoring == false)
        #expect(vm.currentMetrics == nil)
        #expect(vm.alertState == .normal)
    }

    // MARK: - Toggle Monitoring

    @Test("toggleMonitoring starts monitoring when idle", .tags(.success))
    func toggleMonitoringStartsWhenIdle() {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()

        #expect(vm.isMonitoring == true)
        #expect(mock.startMonitoringCallCount == 1)
        #expect(mock.stopMonitoringCallCount == 0)
    }

    @Test("toggleMonitoring stops monitoring when active", .tags(.success))
    func toggleMonitoringStopsWhenActive() {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring() // start
        vm.toggleMonitoring() // stop

        #expect(vm.isMonitoring == false)
        #expect(mock.startMonitoringCallCount == 1)
        #expect(mock.stopMonitoringCallCount == 1)
    }

    @Test("Double toggle returns to monitoring state", .tags(.success))
    func doubleToggleReturnsToMonitoring() {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring() // start
        vm.toggleMonitoring() // stop
        vm.toggleMonitoring() // start again

        #expect(vm.isMonitoring == true)
        #expect(mock.startMonitoringCallCount == 2)
        #expect(mock.stopMonitoringCallCount == 1)
    }

    // MARK: - Metrics Updates from Stream
    @Test("Emitting metrics updates currentMetrics", .tags(.success))
    func emittingMetricsUpdatesCurrentMetrics() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()  // let the monitoring task subscribe to the stream
        mock.emit(CardioVascularMetrics(BPM: 75, Systolic: 120, Diastolic: 80))
        await Task.yield()  // let the monitoring task process the emitted value

        #expect(vm.currentMetrics?.BPM == 75)
        #expect(vm.currentMetrics?.Systolic == 120)
        #expect(vm.currentMetrics?.Diastolic == 80)
    }

    @Test("Emitting without starting monitoring does not update currentMetrics", .tags(.failure))
    func emittingWithoutStartDoesNotUpdateMetrics() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        mock.emit(CardioVascularMetrics(BPM: 75, Systolic: 120, Diastolic: 80))
        await Task.yield()

        #expect(vm.currentMetrics == nil)
    }

    // MARK: - Risk Evaluation Wiring
    //
    // The exhaustive per-threshold + boundary-value matrix lives in
    // EvaluateCardioRiskUseCaseTests (Domain level) - these two tests just
    // confirm DashboardViewModel actually wires an emitted reading through
    // to EvaluateCardioRiskUseCase and surfaces the result as `alertState`,
    // without re-asserting every threshold a second time here.

    @Test("An out-of-range reading updates alertState via the risk use case", .tags(.success))
    func riskyReadingUpdatesAlertState() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, Systolic: 141, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState == .hypertension)
    }

    @Test("A normal reading keeps alertState .normal", .tags(.success))
    func normalReadingKeepsAlertStateNormal() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, Systolic: 120, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState == .normal)
    }
}
