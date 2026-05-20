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
        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 120, Diastolic: 80))
        await Task.yield()  // let the monitoring task process the emitted value

        #expect(vm.currentMetrics?.BPM == 75)
        #expect(vm.currentMetrics?.SystoliC == 120)
        #expect(vm.currentMetrics?.Diastolic == 80)
    }

    @Test("Emitting without starting monitoring does not update currentMetrics", .tags(.failure))
    func emittingWithoutStartDoesNotUpdateMetrics() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 120, Diastolic: 80))
        await Task.yield()

        #expect(vm.currentMetrics == nil)
    }

    // MARK: - Risk Evaluation (Alert State)

    @Test("Systolic > 140 triggers hypertension alert", .tags(.success))
    func highSystolicTriggersHypertension() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 141, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState == .hypertension)
    }

    @Test("Diastolic > 90 triggers hypertension alert", .tags(.success))
    func highDiastolicTriggersHypertension() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 120, Diastolic: 91))
        await Task.yield()

        #expect(vm.alertState == .hypertension)
    }

    @Test("Systolic < 90 triggers hypotension alert", .tags(.success))
    func lowSystolicTriggersHypotension() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 89, Diastolic: 60))
        await Task.yield()

        #expect(vm.alertState == .hypotension)
    }

    @Test("BPM > 120 with normal BP triggers tachycardia alert", .tags(.success))
    func highBPMTriggersTachycardia() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 121, SystoliC: 120, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState == .tachycardia)
    }

    @Test("BPM < 50 with normal BP triggers bradycardia alert", .tags(.success))
    func lowBPMTriggersBradycardia() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 49, SystoliC: 120, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState == .bradycardia)
    }

    @Test("Normal metrics keeps alert as normal", .tags(.success))
    func normalMetricsKeepsNormalAlert() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 120, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState == .normal)
    }

    // MARK: - Boundary Value Tests

    @Test("Systolic exactly 140 does NOT trigger hypertension", .tags(.failure))
    func systolicExactly140DoesNotTriggerHypertension() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 140, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState != .hypertension)
    }

    @Test("Diastolic exactly 90 does NOT trigger hypertension", .tags(.failure))
    func diastolicExactly90DoesNotTriggerHypertension() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 120, Diastolic: 90))
        await Task.yield()

        #expect(vm.alertState != .hypertension)
    }

    @Test("Systolic exactly 90 does NOT trigger hypotension", .tags(.failure))
    func systolicExactly90DoesNotTriggerHypotension() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 75, SystoliC: 90, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState != .hypotension)
    }

    @Test("BPM exactly 120 does NOT trigger tachycardia", .tags(.failure))
    func bpmExactly120DoesNotTriggerTachycardia() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 120, SystoliC: 120, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState != .tachycardia)
    }

    @Test("BPM exactly 50 does NOT trigger bradycardia", .tags(.failure))
    func bpmExactly50DoesNotTriggerBradycardia() async {
        let mock = BLECardioMonitorMock()
        let vm = DashboardViewModel(monitorService: mock)

        vm.toggleMonitoring()
        await Task.yield()
        mock.emit(CardioVascularMetrics(BPM: 50, SystoliC: 120, Diastolic: 80))
        await Task.yield()

        #expect(vm.alertState != .bradycardia)
    }
}
