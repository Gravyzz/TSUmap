import Foundation
import Combine
import SwiftUI

struct TestSample: Codable {
    let inputVector: [Float]
    let expectedClass: Int
    let expectedProbabilities: [Float]

    enum CodingKeys: String, CodingKey {
        case inputVector = "input_vector"
        case expectedClass = "expected_class"
        case expectedProbabilities = "expected_probabilities"
    }
}

struct ValidationReport {
    let predictedClass: Int
    let expectedClass: Int
    let maxProbabilityDelta: Float
    let probabilitiesMatch: Bool
}

@MainActor
final class PredictionViewModel: ObservableObject {
    @Published var predictedDigit: Int?
    @Published var confidence: Float?
    @Published var probabilities: [Float] = []
    @Published var errorMessage: String?
    @Published var modelStatus: String = "Загрузка модели..."
    @Published var validationMessage: String?

    private let preprocessor = ImagePreprocessor()
    private(set) var model: DigitModel?

    init() {
        loadModel()
    }

    func predictLive(from image: UIImage?, isCanvasEmpty: Bool) {
        guard !isCanvasEmpty, let image else {
            errorMessage = nil
            clearPrediction()
            return
        }

        do {
            let input = try preprocessor.preprocess(image)
            let result = try requireModel().predict(input)
            predictedDigit = result.predictedClass
            confidence = result.confidence
            probabilities = result.probabilities
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            clearPrediction()
        }
    }

    func clearPrediction() {
        predictedDigit = nil
        confidence = nil
        probabilities = []
    }

    func clearMessages() {
        errorMessage = nil
        validationMessage = nil
    }

    func loadModel(bundle: Bundle = .main) {
        do {
            let loadedModel = try DigitModelBundleExample.loadModel(bundle: bundle)
            model = loadedModel
            modelStatus = "Модель загружена: \(loadedModel.inputSize)→\(loadedModel.hiddenSize)→\(loadedModel.outputSize)"
            errorMessage = nil
        } catch {
            model = nil
            modelStatus = "Модель не загружена"
            errorMessage = error.localizedDescription
        }
    }

    func runLocalValidation(bundle: Bundle = .main) {
        validationMessage = nil

        do {
            guard let url = bundle.url(forResource: "test_sample", withExtension: "json") else {
                throw DigitModelError.resourceNotFound("test_sample.json")
            }

            let data = try Data(contentsOf: url)
            let sample = try JSONDecoder().decode(TestSample.self, from: data)
            let prediction = try requireModel().predict(sample.inputVector)
            let report = compare(prediction: prediction, against: sample)

            validationMessage = """
            Validation: class \(report.predictedClass), expected \(report.expectedClass), \
            max |Δp| = \(String(format: "%.6f", report.maxProbabilityDelta)) \
            (\(report.probabilitiesMatch ? "OK" : "Mismatch"))
            """
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func requireModel() throws -> DigitModel {
        guard let model else {
            throw DigitModelError.invalidData("Модель не загружена.")
        }
        return model
    }

    private func compare(prediction: DigitPrediction, against sample: TestSample) -> ValidationReport {
        guard prediction.probabilities.count == sample.expectedProbabilities.count else {
            return ValidationReport(
                predictedClass: prediction.predictedClass,
                expectedClass: sample.expectedClass,
                maxProbabilityDelta: .infinity,
                probabilitiesMatch: false
            )
        }

        let deltas = zip(prediction.probabilities, sample.expectedProbabilities).map { abs($0 - $1) }
        let maxDelta = deltas.max() ?? .infinity
        let probabilitiesMatch = sample.expectedClass == prediction.predictedClass && maxDelta < 0.0001
        return ValidationReport(
            predictedClass: prediction.predictedClass,
            expectedClass: sample.expectedClass,
            maxProbabilityDelta: maxDelta,
            probabilitiesMatch: probabilitiesMatch
        )
    }
}
