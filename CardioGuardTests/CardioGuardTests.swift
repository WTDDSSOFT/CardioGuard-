//
//  CardioGuardTests.swift
//  CardioGuardTests
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import Testing
@testable import CardioGuard

@Suite("CardioGuardTests", .tags(.success, .failure))
struct CardioGuardTests {

    @Test("Valid packet returns 75 BPM and 120/80 mmHg", .tags(.success))
    func validPacketReturnsCorrectMetrics() throws {
        let parser = BLEDataParser()
        let metrics = try parser.parse(payload: [0x4B, 0x78, 0x50])

        #expect(metrics.BPM == 75)
        #expect(metrics.SystoliC == 120)
        #expect(metrics.Diastolic == 80)
    }

    @Test("Incomplete packet throws invalidPacketLength", .tags(.failure))
    func incompletePacketThrowsInvalidPacketLength() {
        let parser = BLEDataParser()

        #expect(throws: BLEDataParserError.invalidPacketLength) {
            try parser.parse(payload: [0x4B, 0x78])
        }
    }
}

@Suite("EvaluateCardioRiskUseCaseTests", .tags(.success, .failure))
struct EvaluateCardioRiskUseCaseTests {

    let useCase = EvaluateCardioRiskUseCase()

    // MARK: - Success Tests

    @Test("Normal metrics returns .none", .tags(.success))
    func normalMetricsReturnsNone() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 120, Diastolic: 80)
        #expect(useCase.evaluate(metrics) == [])
    }

    @Test("BPM below 60 returns .bradycardia", .tags(.success))
    func bpmBelow60ReturnsBradycardia() {
        let metrics = standardClinicalThresholds(BPM: 50, SystoliC: 120, Diastolic: 80)
        #expect(useCase.evaluate(metrics) == [.bradycardia])
    }

    @Test("BPM above 100 returns .tachycardia", .tags(.success))
    func bpmAbove100ReturnsTachycardia() {
        let metrics = standardClinicalThresholds(BPM: 110, SystoliC: 120, Diastolic: 80)
        #expect(useCase.evaluate(metrics) == [.tachycardia])
    }

    @Test("High blood pressure returns .hypertension", .tags(.success))
    func highBloodPressureReturnsHypertension() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 150, Diastolic: 95)
        #expect(useCase.evaluate(metrics) == [.hypertension,])
    }

    @Test("Low blood pressure returns .hypotension", .tags(.success))
    func lowBloodPressureReturnsHypotension() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 85, Diastolic: 55)
        #expect(useCase.evaluate(metrics) == [.hypotension])
    }

    @Test("Tachycardia combined with hypertension returns both alerts", .tags(.success))
    func tachycardiaAndHypertensionReturnsBothAlerts() {
        let metrics = standardClinicalThresholds(BPM: 110, SystoliC: 150, Diastolic: 95)
        #expect(useCase.evaluate(metrics) == [.tachycardia, .hypertension])
    }

    // MARK: - Boundary Value Failure Tests

    @Test("BPM exactly 60 does NOT trigger bradycardia", .tags(.failure))
    func bpmExactly60DoesNotTriggerBradycardia() {
        let metrics = standardClinicalThresholds(BPM: 60, SystoliC: 120, Diastolic: 80)
        #expect(!useCase.evaluate(metrics).contains(.bradycardia))
    }

    @Test("BPM exactly 100 does NOT trigger tachycardia", .tags(.failure))
    func bpmExactly100DoesNotTriggerTachycardia() {
        let metrics = standardClinicalThresholds(BPM: 100, SystoliC: 120, Diastolic: 80)
        #expect(!useCase.evaluate(metrics).contains(.tachycardia))
    }

    @Test("Systolic exactly 90 does NOT trigger hypotension", .tags(.failure))
    func systolicExactly90DoesNotTriggerHypotension() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 90, Diastolic: 80)
        #expect(!useCase.evaluate(metrics).contains(.hypotension))
    }

    @Test("Systolic exactly 140 does NOT trigger hypertension", .tags(.failure))
    func systolicExactly140DoesNotTriggerHypertension() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 140, Diastolic: 80)
        #expect(!useCase.evaluate(metrics).contains(.hypertension))
    }

    @Test("Diastolic exactly 60 does NOT trigger hypotension", .tags(.failure))
    func diastolicExactly60DoesNotTriggerHypotension() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 120, Diastolic: 60)
        #expect(!useCase.evaluate(metrics).contains(.hypotension))
    }

    @Test("Diastolic exactly 90 does NOT trigger hypertension", .tags(.failure))
    func diastolicExactly90DoesNotTriggerHypertension() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 120, Diastolic: 90)
        #expect(!useCase.evaluate(metrics).contains(.hypertension))
    }

    // MARK: - Wrong Alert Exclusion Failure Tests

    @Test("Bradycardia does NOT also return tachycardia", .tags(.failure))
    func bradycardiaDoesNotReturnTachycardia() {
        let metrics = standardClinicalThresholds(BPM: 50, SystoliC: 120, Diastolic: 80)
        #expect(!useCase.evaluate(metrics).contains(.tachycardia))
    }

    @Test("Tachycardia does NOT also return bradycardia", .tags(.failure))
    func tachycardiaDoesNotReturnBradycardia() {
        let metrics = standardClinicalThresholds(BPM: 110, SystoliC: 120, Diastolic: 80)
        #expect(!useCase.evaluate(metrics).contains(.bradycardia))
    }

    @Test("Hypertension does NOT also return hypotension", .tags(.failure))
    func hypertensionDoesNotReturnHypotension() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 150, Diastolic: 95)
        #expect(!useCase.evaluate(metrics).contains(.hypotension))
    }

    @Test("Hypotension does NOT also return hypertension", .tags(.failure))
    func hypotensionDoesNotReturnHypertension() {
        let metrics = standardClinicalThresholds(BPM: 75, SystoliC: 85, Diastolic: 55)
        #expect(!useCase.evaluate(metrics).contains(.hypertension))
    }
}
