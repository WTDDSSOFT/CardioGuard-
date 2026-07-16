//
//  RemoteCardioRiskPredictor.swift
//  CardioGuard
//
//  Cloud fallback for CardioRiskPredicting. No real backend ships with this
//  project (standing up and operating an inference API is out of scope for
//  a demo app) - `CloudInferenceConfig.endpoint` is `nil` by default, which
//  makes this predictor always throw `.modelUnavailable` until a real
//  endpoint is configured. That keeps the same "fail soft, never crash"
//  contract as CoreMLCardioRiskPredictor, and means the hybrid fallback
//  below degrades to on-device-only behavior out of the box.
//

import Foundation

enum CloudInferenceConfig {
    /// Replace with a real inference endpoint to enable the cloud fallback
    /// path. Left `nil` on purpose: this repo doesn't ship or operate a
    /// backend, so pretending one exists would be dishonest. Wiring it up is
    /// a one-line change once a real endpoint exists.
    static let endpoint: URL? = nil
}

final class RemoteCardioRiskPredictor: CardioRiskPredicting {

    private let endpoint: URL?
    private let session: URLSession
    private let timeout: TimeInterval

    init(endpoint: URL? = CloudInferenceConfig.endpoint, session: URLSession = .shared, timeout: TimeInterval = 5) {
        self.endpoint = endpoint
        self.session = session
        self.timeout = timeout
    }

    func predict(window: [CardioVascularMetrics]) async throws -> AIRiskPrediction {
        guard window.count == CardioRiskPredictorConfig.windowSize else {
            throw CardioRiskPredictingError.invalidWindowSize
        }
        guard let endpoint else {
            throw CardioRiskPredictingError.modelUnavailable
        }

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(readings: window.map(Reading.init)))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CardioRiskPredictingError.predictionFailed
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return AIRiskPrediction(riskScore: decoded.riskScore, source: .cloud)
    }

    private struct Reading: Encodable {
        let bpm: Int
        let systolic: Int
        let diastolic: Int

        init(_ metrics: CardioVascularMetrics) {
            bpm = metrics.BPM
            systolic = metrics.Systolic
            diastolic = metrics.Diastolic
        }
    }

    private struct RequestBody: Encodable {
        let readings: [Reading]
    }

    private struct ResponseBody: Decodable {
        let riskScore: Double
    }
}
