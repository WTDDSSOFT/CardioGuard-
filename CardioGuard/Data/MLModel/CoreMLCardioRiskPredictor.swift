//
//  CoreMLCardioRiskPredictor.swift
//  CardioGuard
//
//  Loads CardioRiskPredictor.mlpackage (see MLPipeline/) and runs it on the
//  last N BLE readings to produce an early-warning probability.
//
//  Deliberately uses the generic MLModel API (rather than the class Xcode
//  auto-generates from the .mlpackage) so this file compiles even before the
//  model is bundled into CardioGuard/Resources/MLModels/ - loading only fails
//  at runtime, and it fails soft (see `predict`), never crashing the app.
//

import CoreML
import Foundation

final class CoreMLCardioRiskPredictor: CardioRiskPredicting {

    private let inputFeatureName = "readings"
    private let outputFeatureName = "risk_score"
    private let featuresPerReading = 3 // [BPM, Systolic, Diastolic]

    private let model: MLModel?

    /// - Parameter modelName: base name of the .mlpackage bundled in
    ///   CardioGuard/Resources/MLModels/ (defaults to what
    ///   MLPipeline/prune_and_convert.py produces).
    init(modelName: String = "CardioRiskPredictor") {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            self.model = try? MLModel(contentsOf: compiledURL, configuration: configuration)
        } else if let packageURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
            self.model = try? MLModel(contentsOf: packageURL, configuration: configuration)
        } else {
            self.model = nil
        }
    }

    func predict(window: [CardioVascularMetrics]) async throws -> AIRiskPrediction {
        guard window.count == CardioRiskPredictorConfig.windowSize else {
            throw CardioRiskPredictingError.invalidWindowSize
        }
        guard let model else {
            throw CardioRiskPredictingError.modelUnavailable
        }

        let inputArray = try makeMultiArray(from: window)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            inputFeatureName: MLFeatureValue(multiArray: inputArray)
        ])

        let output = try await model.prediction(from: input)
        guard let riskArray = output.featureValue(for: outputFeatureName)?.multiArrayValue,
              riskArray.count > 0 else {
            throw CardioRiskPredictingError.predictionFailed
        }

        let score = Double(truncating: riskArray[0])
        return AIRiskPrediction(riskScore: score)
    }

    private func makeMultiArray(from window: [CardioVascularMetrics]) throws -> MLMultiArray {
        let shape: [NSNumber] = [1, NSNumber(value: CardioRiskPredictorConfig.windowSize), NSNumber(value: featuresPerReading)]
        let array = try MLMultiArray(shape: shape, dataType: .float32)

        for (index, metrics) in window.enumerated() {
            array[[0, NSNumber(value: index), 0]] = NSNumber(value: metrics.BPM)
            array[[0, NSNumber(value: index), 1]] = NSNumber(value: metrics.SystoliC)
            array[[0, NSNumber(value: index), 2]] = NSNumber(value: metrics.Diastolic)
        }

        return array
    }
}
