import Foundation

final class SimpleNeuralNet {

    let inputSize:  Int
    let hiddenSize: Int
    let outputSize = 10

    private var weightsIH: [[Double]]
    private var biasH:     [Double]
    private var weightsHO: [[Double]]
    private var biasO:     [Double]

    private var hiddenValues: [Double] = []

    var trainingSamples: Int = 0
    var trainedEpochs: Int = 0
    var finalLoss: Double = 0

    init(inputSize: Int = 2500, hiddenSize: Int = 128) {
        self.inputSize  = inputSize
        self.hiddenSize = hiddenSize

        let rangeIH = sqrt(2.0 / Double(inputSize))
        let rangeHO = sqrt(2.0 / Double(hiddenSize))
        let outSize = 10

        weightsIH = (0..<inputSize).map { _ in
            (0..<hiddenSize).map { _ in Double.random(in: -rangeIH...rangeIH) }
        }
        biasH = [Double](repeating: 0, count: hiddenSize)

        weightsHO = (0..<hiddenSize).map { _ in
            (0..<outSize).map { _ in Double.random(in: -rangeHO...rangeHO) }
        }
        biasO = [Double](repeating: 0, count: outSize)
    }

    func predict(input: [Double]) -> [Double] {
        var hidden = [Double](repeating: 0, count: hiddenSize)
        for j in 0..<hiddenSize {
            var sum = biasH[j]
            for i in 0..<inputSize {
                if input[i] != 0 {
                    sum += input[i] * weightsIH[i][j]
                }
            }
            hidden[j] = relu(sum)
        }
        hiddenValues = hidden

        var raw = [Double](repeating: 0, count: outputSize)
        for k in 0..<outputSize {
            var sum = biasO[k]
            for j in 0..<hiddenSize {
                sum += hidden[j] * weightsHO[j][k]
            }
            raw[k] = sum
        }

        return softmax(raw)
    }

    func classify(input: [Double]) -> (digit: Int, confidence: Double, all: [Double]) {
        let out = predict(input: input)
        let maxIdx = out.indices.max(by: { out[$0] < out[$1] }) ?? 0
        return (digit: maxIdx, confidence: out[maxIdx], all: out)
    }

    func train(inputs: [[Double]], labels: [Int],
               epochs: Int = 25, learningRate: Double = 0.01,
               shouldStop: (() -> Bool)? = nil,
               onProgress: ((Int, Int, Double) -> Void)? = nil) {

        trainingSamples = inputs.count

        for epoch in 0..<epochs {
            if shouldStop?() == true { break }
            var totalLoss = 0.0

            let indices = (0..<inputs.count).shuffled()

            for idx in indices {
                let input = inputs[idx]
                let label = labels[idx]
                let output = predict(input: input)

                var target = [Double](repeating: 0, count: outputSize)
                target[label] = 1.0

                totalLoss -= log(max(output[label], 1e-10))

                var outputDelta = [Double](repeating: 0, count: outputSize)
                for k in 0..<outputSize {
                    outputDelta[k] = output[k] - target[k]
                }

                var hiddenDelta = [Double](repeating: 0, count: hiddenSize)
                for j in 0..<hiddenSize {
                    var err = 0.0
                    for k in 0..<outputSize {
                        err += outputDelta[k] * weightsHO[j][k]
                    }
                    hiddenDelta[j] = hiddenValues[j] > 0 ? err : 0
                }

                for j in 0..<hiddenSize {
                    if hiddenValues[j] == 0 { continue }
                    for k in 0..<outputSize {
                        weightsHO[j][k] -= learningRate * outputDelta[k] * hiddenValues[j]
                    }
                }
                for k in 0..<outputSize {
                    biasO[k] -= learningRate * outputDelta[k]
                }

                for i in 0..<inputSize {
                    if input[i] == 0 { continue }
                    for j in 0..<hiddenSize {
                        weightsIH[i][j] -= learningRate * hiddenDelta[j] * input[i]
                    }
                }
                for j in 0..<hiddenSize {
                    biasH[j] -= learningRate * hiddenDelta[j]
                }
            }

            let avgLoss = totalLoss / Double(inputs.count)
            trainedEpochs = epoch + 1
            finalLoss = avgLoss

            onProgress?(epoch + 1, epochs, avgLoss)
        }
    }

    private struct WeightsSnapshot: Codable {
        let inputSize: Int
        let hiddenSize: Int
        let outputSize: Int
        let weightsIH: [[Double]]
        let biasH: [Double]
        let weightsHO: [[Double]]
        let biasO: [Double]
        let trainedEpochs: Int
        let trainingSamples: Int
        let finalLoss: Double
    }

    static func weightsURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("nn-weights.json")
    }

    @discardableResult
    func saveWeights() -> Bool {
        let snap = WeightsSnapshot(
            inputSize: inputSize, hiddenSize: hiddenSize, outputSize: outputSize,
            weightsIH: weightsIH, biasH: biasH,
            weightsHO: weightsHO, biasO: biasO,
            trainedEpochs: trainedEpochs,
            trainingSamples: trainingSamples,
            finalLoss: finalLoss
        )
        guard let data = try? JSONEncoder().encode(snap) else { return false }
        do {
            try data.write(to: Self.weightsURL(), options: .atomic)
            print("✅ Веса нейросети сохранены (\(data.count / 1024) КБ)")
            return true
        } catch {
            print("⚠️ Не удалось сохранить веса: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func loadWeights() -> Bool {
        let url = Self.weightsURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(WeightsSnapshot.self, from: data),
              snap.inputSize == inputSize,
              snap.hiddenSize == hiddenSize,
              snap.outputSize == outputSize
        else { return false }

        weightsIH = snap.weightsIH
        biasH = snap.biasH
        weightsHO = snap.weightsHO
        biasO = snap.biasO
        trainedEpochs = snap.trainedEpochs
        trainingSamples = snap.trainingSamples
        finalLoss = snap.finalLoss
        print("✅ Веса нейросети загружены (\(snap.trainedEpochs) эпох, \(snap.trainingSamples) обр., loss=\(String(format: "%.3f", snap.finalLoss)))")
        return true
    }

    static func deleteSavedWeights() {
        try? FileManager.default.removeItem(at: weightsURL())
    }

    func evaluate(inputs: [[Double]], labels: [Int]) -> Double {
        var correct = 0
        for (input, label) in zip(inputs, labels) {
            let result = classify(input: input)
            if result.digit == label { correct += 1 }
        }
        return Double(correct) / Double(inputs.count)
    }

    private func relu(_ x: Double) -> Double {
        max(0, x)
    }

    private func softmax(_ x: [Double]) -> [Double] {
        let maxVal = x.max() ?? 0
        let exps = x.map { exp($0 - maxVal) }
        let sum = exps.reduce(0, +)
        return exps.map { $0 / sum }
    }
}

struct MNISTLoader {

    static func loadImages(filename: String) -> [[UInt8]]? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil),
              let data = try? Data(contentsOf: url) else {
            print("⚠️ MNIST файл '\(filename)' не найден в бандле")
            return nil
        }

        let bytes = [UInt8](data)
        guard bytes.count > 16 else { return nil }

        let magic = readInt32(bytes, offset: 0)
        guard magic == 2051 else {
            print("⚠️ Неверный magic number для images: \(magic)")
            return nil
        }

        let count = readInt32(bytes, offset: 4)
        let rows  = readInt32(bytes, offset: 8)
        let cols  = readInt32(bytes, offset: 12)
        let imgSize = rows * cols

        print("✅ MNIST images: \(count) изображений \(rows)×\(cols)")

        var images: [[UInt8]] = []
        images.reserveCapacity(count)

        for i in 0..<count {
            let offset = 16 + i * imgSize
            guard offset + imgSize <= bytes.count else { break }
            let img = Array(bytes[offset..<(offset + imgSize)])
            images.append(img)
        }

        return images
    }

    static func loadLabels(filename: String) -> [Int]? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil),
              let data = try? Data(contentsOf: url) else {
            print("⚠️ MNIST файл '\(filename)' не найден в бандле")
            return nil
        }

        let bytes = [UInt8](data)
        guard bytes.count > 8 else { return nil }

        let magic = readInt32(bytes, offset: 0)
        guard magic == 2049 else {
            print("⚠️ Неверный magic number для labels: \(magic)")
            return nil
        }

        let count = readInt32(bytes, offset: 4)
        print("✅ MNIST labels: \(count) меток")

        var labels: [Int] = []
        labels.reserveCapacity(count)

        for i in 0..<count {
            let offset = 8 + i
            guard offset < bytes.count else { break }
            labels.append(Int(bytes[offset]))
        }

        return labels
    }

    static func preprocessMNIST(image: [UInt8], from srcSize: Int = 28,
                                 to dstSize: Int = 50) -> [Double] {
        var result = [Double](repeating: 0, count: dstSize * dstSize)
        let scale = Double(srcSize) / Double(dstSize)

        for r in 0..<dstSize {
            for c in 0..<dstSize {
                let srcR = Double(r) * scale
                let srcC = Double(c) * scale
                let r0 = min(Int(srcR), srcSize - 1)
                let c0 = min(Int(srcC), srcSize - 1)
                let r1 = min(r0 + 1, srcSize - 1)
                let c1 = min(c0 + 1, srcSize - 1)

                let dr = srcR - Double(r0)
                let dc = srcC - Double(c0)

                let v00 = Double(image[r0 * srcSize + c0]) / 255.0
                let v01 = Double(image[r0 * srcSize + c1]) / 255.0
                let v10 = Double(image[r1 * srcSize + c0]) / 255.0
                let v11 = Double(image[r1 * srcSize + c1]) / 255.0

                let value = v00 * (1 - dr) * (1 - dc) +
                            v01 * (1 - dr) * dc +
                            v10 * dr * (1 - dc) +
                            v11 * dr * dc

                result[r * dstSize + c] = value > 0.3 ? 1.0 : 0.0
            }
        }
        return result
    }

    static func loadSubset(imagesFile: String, labelsFile: String,
                            maxPerDigit: Int = 200,
                            targetSize: Int = 50) -> (inputs: [[Double]], labels: [Int])? {
        guard let images = loadImages(filename: imagesFile),
              let labels = loadLabels(filename: labelsFile),
              images.count == labels.count else { return nil }

        var inputs: [[Double]] = []
        var resultLabels: [Int] = []
        var countPerDigit = [Int](repeating: 0, count: 10)

        for (img, label) in zip(images, labels) {
            guard label >= 0, label <= 9 else { continue }
            guard countPerDigit[label] < maxPerDigit else { continue }

            let processed = preprocessMNIST(image: img, to: targetSize)
            inputs.append(processed)
            resultLabels.append(label)
            countPerDigit[label] += 1

            if countPerDigit.allSatisfy({ $0 >= maxPerDigit }) { break }
        }

        print("✅ MNIST подмножество: \(inputs.count) образцов (\(countPerDigit))")
        return (inputs, resultLabels)
    }

    private static func readInt32(_ bytes: [UInt8], offset: Int) -> Int {
        return Int(bytes[offset])     << 24 |
               Int(bytes[offset + 1]) << 16 |
               Int(bytes[offset + 2]) << 8  |
               Int(bytes[offset + 3])
    }
}

struct DrawingPreprocessor {
    static func centerDrawing(_ grid: [[Bool]], size: Int) -> [Double] {
        var sumR = 0.0, sumC = 0.0, count = 0.0
        var minR = size, maxR = 0, minC = size, maxC = 0

        for r in 0..<size {
            for c in 0..<size {
                if grid[r][c] {
                    sumR += Double(r)
                    sumC += Double(c)
                    count += 1
                    minR = min(minR, r)
                    maxR = max(maxR, r)
                    minC = min(minC, c)
                    maxC = max(maxC, c)
                }
            }
        }

        guard count > 0 else {
            return [Double](repeating: 0, count: size * size)
        }

        let centerR = sumR / count
        let centerC = sumC / count
        let targetCenter = Double(size) / 2.0

        let shiftR = Int(round(targetCenter - centerR))
        let shiftC = Int(round(targetCenter - centerC))

        var result = [Double](repeating: 0, count: size * size)
        for r in 0..<size {
            for c in 0..<size {
                let srcR = r - shiftR
                let srcC = c - shiftC
                if srcR >= 0, srcR < size, srcC >= 0, srcC < size, grid[srcR][srcC] {
                    result[r * size + c] = 1.0
                }
            }
        }

        return result
    }
}

struct DigitTrainingData {

    private static let gridSize = 50

    static func generate() -> (inputs: [[Double]], labels: [Int], source: String) {
        if let mnist = MNISTLoader.loadSubset(
            imagesFile: "train-images-idx3-ubyte",
            labelsFile: "train-labels-idx1-ubyte",
            maxPerDigit: 50, targetSize: gridSize) {
            return (mnist.inputs, mnist.labels, "MNIST train (\(mnist.inputs.count) обр.)")
        }

        if let mnist = MNISTLoader.loadSubset(
            imagesFile: "t10k-images-idx3-ubyte",
            labelsFile: "t10k-labels-idx1-ubyte",
            maxPerDigit: 50, targetSize: gridSize) {
            return (mnist.inputs, mnist.labels, "MNIST test (\(mnist.inputs.count) обр.)")
        }

        let (inputs, labels) = generateBuiltinPatterns()
        return (inputs, labels, "Встроенные шаблоны (\(inputs.count) обр.)")
    }

    static func generateBuiltinPatterns() -> (inputs: [[Double]], labels: [Int]) {
        var inputs: [[Double]] = []
        var labels: [Int] = []

        for digit in 0...9 {
            guard let pattern10 = patterns[digit] else { continue }
            let base = upscale(pattern10, from: 10, to: gridSize)
            let dilated = dilate(base, size: gridSize)
            let dilated2 = dilate(dilated, size: gridSize)

            for src in [base, dilated, dilated2] {
                inputs.append(src); labels.append(digit)

                for (dx, dy) in [(-3, 0), (3, 0), (0, -3), (0, 3), (-3, -3), (3, 3)] {
                    inputs.append(shift(src, dx: dx, dy: dy))
                    labels.append(digit)
                }

                var noisy = src
                for _ in 0..<25 {
                    let idx = Int.random(in: 0..<(gridSize * gridSize))
                    noisy[idx] = noisy[idx] > 0.5 ? 0 : 1
                }
                inputs.append(noisy); labels.append(digit)
            }
        }

        return (inputs, labels)
    }

    private static let patterns: [Int: [[Int]]] = [
        0: [
            [0,0,1,1,1,1,1,1,0,0],
            [0,1,1,0,0,0,0,1,1,0],
            [1,1,0,0,0,0,0,0,1,1],
            [1,1,0,0,0,0,0,0,1,1],
            [1,1,0,0,0,0,0,0,1,1],
            [1,1,0,0,0,0,0,0,1,1],
            [1,1,0,0,0,0,0,0,1,1],
            [1,1,0,0,0,0,0,0,1,1],
            [0,1,1,0,0,0,0,1,1,0],
            [0,0,1,1,1,1,1,1,0,0]
        ],
        1: [
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,1,1,1,0,0,0,0],
            [0,0,1,1,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,1,1,1,1,1,1,1,1,0]
        ],
        2: [
            [0,0,1,1,1,1,1,1,0,0],
            [0,1,1,0,0,0,0,1,1,0],
            [1,1,0,0,0,0,0,0,1,1],
            [0,0,0,0,0,0,0,1,1,0],
            [0,0,0,0,0,0,1,1,0,0],
            [0,0,0,0,0,1,1,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,1,1,0,0,0,0,0],
            [0,0,1,1,0,0,0,0,0,0],
            [1,1,1,1,1,1,1,1,1,1]
        ],
        3: [
            [0,1,1,1,1,1,1,1,0,0],
            [0,0,0,0,0,0,0,1,1,0],
            [0,0,0,0,0,0,0,0,1,1],
            [0,0,0,0,0,0,0,1,1,0],
            [0,0,0,1,1,1,1,1,0,0],
            [0,0,0,0,0,0,0,1,1,0],
            [0,0,0,0,0,0,0,0,1,1],
            [0,0,0,0,0,0,0,0,1,1],
            [0,0,0,0,0,0,0,1,1,0],
            [0,1,1,1,1,1,1,1,0,0]
        ],
        4: [
            [0,0,0,0,0,0,1,1,0,0],
            [0,0,0,0,0,1,1,1,0,0],
            [0,0,0,0,1,1,1,1,0,0],
            [0,0,0,1,1,0,1,1,0,0],
            [0,0,1,1,0,0,1,1,0,0],
            [0,1,1,0,0,0,1,1,0,0],
            [1,1,1,1,1,1,1,1,1,1],
            [0,0,0,0,0,0,1,1,0,0],
            [0,0,0,0,0,0,1,1,0,0],
            [0,0,0,0,0,0,1,1,0,0]
        ],
        5: [
            [1,1,1,1,1,1,1,1,1,1],
            [1,1,0,0,0,0,0,0,0,0],
            [1,1,0,0,0,0,0,0,0,0],
            [1,1,1,1,1,1,1,0,0,0],
            [0,0,0,0,0,0,1,1,0,0],
            [0,0,0,0,0,0,0,1,1,0],
            [0,0,0,0,0,0,0,1,1,0],
            [0,0,0,0,0,0,0,1,1,0],
            [1,0,0,0,0,0,1,1,0,0],
            [0,1,1,1,1,1,1,0,0,0]
        ],
        6: [
            [0,0,0,1,1,1,1,1,0,0],
            [0,0,1,1,0,0,0,0,0,0],
            [0,1,1,0,0,0,0,0,0,0],
            [1,1,0,0,0,0,0,0,0,0],
            [1,1,0,1,1,1,1,0,0,0],
            [1,1,1,0,0,0,1,1,0,0],
            [1,1,0,0,0,0,0,1,1,0],
            [1,1,0,0,0,0,0,1,1,0],
            [0,1,1,0,0,0,1,1,0,0],
            [0,0,1,1,1,1,1,0,0,0]
        ],
        7: [
            [1,1,1,1,1,1,1,1,1,1],
            [0,0,0,0,0,0,0,0,1,1],
            [0,0,0,0,0,0,0,1,1,0],
            [0,0,0,0,0,0,1,1,0,0],
            [0,0,0,0,0,1,1,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,1,1,0,0,0,0]
        ],
        8: [
            [0,0,1,1,1,1,1,1,0,0],
            [0,1,1,0,0,0,0,1,1,0],
            [0,1,1,0,0,0,0,1,1,0],
            [0,1,1,0,0,0,0,1,1,0],
            [0,0,1,1,1,1,1,1,0,0],
            [0,1,1,0,0,0,0,1,1,0],
            [1,1,0,0,0,0,0,0,1,1],
            [1,1,0,0,0,0,0,0,1,1],
            [0,1,1,0,0,0,0,1,1,0],
            [0,0,1,1,1,1,1,1,0,0]
        ],
        9: [
            [0,0,1,1,1,1,1,0,0,0],
            [0,1,1,0,0,0,1,1,0,0],
            [1,1,0,0,0,0,0,1,1,0],
            [1,1,0,0,0,0,0,1,1,0],
            [0,1,1,0,0,0,1,1,1,0],
            [0,0,1,1,1,1,0,1,1,0],
            [0,0,0,0,0,0,0,1,1,0],
            [0,0,0,0,0,0,1,1,0,0],
            [0,0,0,0,0,1,1,0,0,0],
            [0,0,1,1,1,1,0,0,0,0]
        ]
    ]

    private static func upscale(_ pattern: [[Int]], from srcSize: Int, to dstSize: Int) -> [Double] {
        var result = [Double](repeating: 0, count: dstSize * dstSize)
        let scale = Double(dstSize) / Double(srcSize)
        for r in 0..<dstSize {
            for c in 0..<dstSize {
                let sr = min(Int(Double(r) / scale), srcSize - 1)
                let sc = min(Int(Double(c) / scale), srcSize - 1)
                result[r * dstSize + c] = Double(pattern[sr][sc])
            }
        }
        return result
    }

    private static func shift(_ img: [Double], dx: Int, dy: Int) -> [Double] {
        let n = gridSize
        var result = [Double](repeating: 0, count: n * n)
        for r in 0..<n {
            for c in 0..<n {
                let sr = r - dy
                let sc = c - dx
                if sr >= 0, sr < n, sc >= 0, sc < n {
                    result[r * n + c] = img[sr * n + sc]
                }
            }
        }
        return result
    }

    private static func dilate(_ img: [Double], size n: Int) -> [Double] {
        var result = img
        for r in 0..<n {
            for c in 0..<n {
                if img[r * n + c] > 0.5 {
                    for dr in -1...1 {
                        for dc in -1...1 {
                            let nr = r + dr
                            let nc = c + dc
                            if nr >= 0, nr < n, nc >= 0, nc < n {
                                result[nr * n + nc] = 1.0
                            }
                        }
                    }
                }
            }
        }
        return result
    }
}
