//
//  HybridCardioRiskPredictorTests.swift
//  CardioGuardTests
//
//  Verifies the local/cloud fallback contract: local is always tried first,
//  remote is only consulted when local throws, and predictions are tagged
//  with the right PredictionSource.
//

import Testing
@testable import CardioGuard

@Suite("HybridCardioRiskPredictorTests", .tags(.success, .failure))
struct HybridCardioRiskPredictorTests {

    private func sampleWindow() -> [CardioVascularMetrics] {
        Array(repeating: CardioVascularMetrics(BPM: 75, Systolic: 120, Diastolic: 80),
              count: CardioRiskPredictorConfig.windowSize)
    }

    @Test("Uses the local prediction and never calls remote when local succeeds", .tags(.success))
    func usesLocalWhenItSucceeds() async throws {
        let local = CardioRiskPredictorMock()
        local.stubbedPrediction = AIRiskPrediction(riskScore: 0.42, source: .onDevice)
        let remote = CardioRiskPredictorMock()
        let hybrid = HybridCardioRiskPredictor(local: local, remote: remote)

        let result = try await hybrid.predict(window: sampleWindow())

        #expect(result.riskScore == 0.42)
        #expect(result.source == .onDevice)
        #expect(local.predictCallCount == 1)
        #expect(remote.predictCallCount == 0)
    }

    @Test("Falls back to remote when local throws, and tags the result as .cloud", .tags(.success))
    func fallsBackToRemoteWhenLocalFails() async throws {
        let local = CardioRiskPredictorMock()
        local.stubbedError = CardioRiskPredictingError.modelUnavailable
        let remote = CardioRiskPredictorMock()
        remote.stubbedPrediction = AIRiskPrediction(riskScore: 0.77, source: .cloud)
        let hybrid = HybridCardioRiskPredictor(local: local, remote: remote)

        let result = try await hybrid.predict(window: sampleWindow())

        #expect(result.riskScore == 0.77)
        #expect(result.source == .cloud)
        #expect(local.predictCallCount == 1)
        #expect(remote.predictCallCount == 1)
    }

    @Test("Propagates the remote error (not local's) when both local and remote fail", .tags(.failure))
    func propagatesErrorWhenBothFail() async {
        let local = CardioRiskPredictorMock()
        local.stubbedError = CardioRiskPredictingError.modelUnavailable
        let remote = CardioRiskPredictorMock()
        remote.stubbedError = CardioRiskPredictingError.predictionFailed
        let hybrid = HybridCardioRiskPredictor(local: local, remote: remote)

        do {
            _ = try await hybrid.predict(window: sampleWindow())
            Issue.record("Expected predict(window:) to throw")
        } catch let error as CardioRiskPredictingError {
            #expect(error == .predictionFailed)
        } catch {
            Issue.record("Expected a CardioRiskPredictingError, got \(error)")
        }
        #expect(local.predictCallCount == 1)
        #expect(remote.predictCallCount == 1)
    }

    @Test("RemoteCardioRiskPredictor throws .modelUnavailable when no endpoint is configured", .tags(.failure))
    func remoteThrowsWithoutEndpoint() async {
        let remote = RemoteCardioRiskPredictor(endpoint: nil)

        do {
            _ = try await remote.predict(window: sampleWindow())
            Issue.record("Expected predict(window:) to throw")
        } catch let error as CardioRiskPredictingError {
            #expect(error == .modelUnavailable)
        } catch {
            Issue.record("Expected a CardioRiskPredictingError, got \(error)")
        }
    }
}
