import Foundation

enum DigitModelError: LocalizedError {
    case resourceNotFound(String)
    case invalidData(String)
    case invalidInputSize(expected: Int, received: Int)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "Файл \(name) не найден в Bundle."
        case .invalidData(let message):
            return message
        case .invalidInputSize(let expected, let received):
            return "Ожидался вектор длины \(expected), получено \(received)."
        }
    }
}

struct DigitPrediction {
    let predictedClass: Int
    let confidence: Float
    let probabilities: [Float]
}

struct DigitModel: Codable {
    private enum CodingKeys: String, CodingKey {
        case inputSize
        case hiddenSize
        case outputSize
        case W1
        case b1
        case W2
        case b2
    }

    let inputSize: Int
    let hiddenSize: Int
    let outputSize: Int
    let W1: [Float]
    let b1: [Float]
    let W2: [Float]
    let b2: [Float]

    init(fromBundleResource resourceName: String = "model", bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw DigitModelError.resourceNotFound("\(resourceName).json")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let model = try decoder.decode(DigitModel.self, from: data)
        try model.validate()
        self = model
    }

    init(
        inputSize: Int,
        hiddenSize: Int,
        outputSize: Int,
        W1: [Float],
        b1: [Float],
        W2: [Float],
        b2: [Float]
    ) {
        self.inputSize = inputSize
        self.hiddenSize = hiddenSize
        self.outputSize = outputSize
        self.W1 = W1
        self.b1 = b1
        self.W2 = W2
        self.b2 = b2
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputSize = try container.decode(Int.self, forKey: .inputSize)
        hiddenSize = try container.decode(Int.self, forKey: .hiddenSize)
        outputSize = try container.decode(Int.self, forKey: .outputSize)
        b1 = try container.decode([Float].self, forKey: .b1)
        b2 = try container.decode([Float].self, forKey: .b2)
        W1 = try Self.decodeMatrix(from: container, forKey: .W1)
        W2 = try Self.decodeMatrix(from: container, forKey: .W2)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputSize, forKey: .inputSize)
        try container.encode(hiddenSize, forKey: .hiddenSize)
        try container.encode(outputSize, forKey: .outputSize)
        try container.encode(W1, forKey: .W1)
        try container.encode(b1, forKey: .b1)
        try container.encode(W2, forKey: .W2)
        try container.encode(b2, forKey: .b2)
    }

    func predictProba(_ input: [Float]) throws -> [Float] {
        guard input.count == inputSize else {
            throw DigitModelError.invalidInputSize(expected: inputSize, received: input.count)
        }

        var hidden = [Float](repeating: 0, count: hiddenSize)
        for hiddenIndex in 0..<hiddenSize {
            var sum = b1[hiddenIndex]
            for inputIndex in 0..<inputSize {
                sum += input[inputIndex] * W1[inputIndex * hiddenSize + hiddenIndex]
            }
            hidden[hiddenIndex] = relu(sum)
        }

        var logits = [Float](repeating: 0, count: outputSize)
        for outputIndex in 0..<outputSize {
            var sum = b2[outputIndex]
            for hiddenIndex in 0..<hiddenSize {
                sum += hidden[hiddenIndex] * W2[hiddenIndex * outputSize + outputIndex]
            }
            logits[outputIndex] = sum
        }

        return try softmax(logits)
    }

    func predict(_ input: [Float]) throws -> DigitPrediction {
        let probabilities = try predictProba(input)
        let predictedClass = probabilities.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let confidence = probabilities[predictedClass]
        return DigitPrediction(
            predictedClass: predictedClass,
            confidence: confidence,
            probabilities: probabilities
        )
    }

    func validate() throws {
        guard inputSize == 2500 else {
            throw DigitModelError.invalidData("inputSize должен быть равен 2500.")
        }
        guard hiddenSize == 128 else {
            throw DigitModelError.invalidData("hiddenSize должен быть равен 128.")
        }
        guard outputSize == 10 else {
            throw DigitModelError.invalidData("outputSize должен быть равен 10.")
        }
        guard W1.count == inputSize * hiddenSize else {
            throw DigitModelError.invalidData("Размер W1 не совпадает с inputSize * hiddenSize.")
        }
        guard b1.count == hiddenSize else {
            throw DigitModelError.invalidData("Размер b1 не совпадает с hiddenSize.")
        }
        guard W2.count == hiddenSize * outputSize else {
            throw DigitModelError.invalidData("Размер W2 не совпадает с hiddenSize * outputSize.")
        }
        guard b2.count == outputSize else {
            throw DigitModelError.invalidData("Размер b2 не совпадает с outputSize.")
        }
    }

    private func relu(_ value: Float) -> Float {
        max(0, value)
    }

    private func softmax(_ values: [Float]) throws -> [Float] {
        let maxValue = values.max() ?? 0
        let exponentials = values.map { Foundation.exp($0 - maxValue) }
        let sum = exponentials.reduce(0, +)
        guard sum > 0 else {
            throw DigitModelError.invalidData("Softmax получил некорректные logits.")
        }
        return exponentials.map { $0 / sum }
    }

    private static func decodeMatrix(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [Float] {
        if let flat = try? container.decode([Float].self, forKey: key) {
            return flat
        }

        if let nested = try? container.decode([[Float]].self, forKey: key) {
            return nested.flatMap { $0 }
        }

        throw DigitModelError.invalidData("Не удалось декодировать \(key.stringValue).")
    }
}

struct DigitModelBundleExample {
    static func loadModel(bundle: Bundle = .main) throws -> DigitModel {
        try DigitModel(fromBundleResource: "model", bundle: bundle)
    }
}
