import SwiftUI
import Combine

private let kGridSize = 50

final class NeuralNetModel: ObservableObject {
    @Published var grid: [[Bool]] = Array(repeating: Array(repeating: false, count: kGridSize), count: kGridSize)
    @Published var prediction: (digit: Int, confidence: Double, all: [Double])?
    @Published var isTrained = false
    @Published var isTraining = false
    @Published var trainingProgress: String = ""
    @Published var progressFraction: Double = 0
    @Published var dataSource: String = ""
    @Published var trainedEpochs: Int = 0
    @Published var finalLoss: Double = 0
    @Published var trainingSamples: Int = 0

    private var net = SimpleNeuralNet(inputSize: kGridSize * kGridSize, hiddenSize: 128)
    private var cancelRequested = false
    private let brushRadius = 2

    init() {
        if net.loadWeights() {
            isTrained = true
            trainedEpochs = net.trainedEpochs
            finalLoss = net.finalLoss
            trainingSamples = net.trainingSamples
            trainingProgress = "Загружено из кэша"
        }
    }

    func train() {
        isTraining = true
        cancelRequested = false
        progressFraction = 0
        trainingProgress = "Подготовка данных..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let data = DigitTrainingData.generate()

            DispatchQueue.main.async {
                self.dataSource = data.source
                self.trainingSamples = data.inputs.count
                self.trainingProgress = "Источник: \(data.source)"
            }

            let startTime = Date()
            self.net.train(
                inputs: data.inputs, labels: data.labels,
                epochs: 25, learningRate: 0.01,
                shouldStop: { [weak self] in self?.cancelRequested ?? false }
            ) { [weak self] epoch, totalEpochs, loss in
                let elapsed = Date().timeIntervalSince(startTime)
                let perEpoch = elapsed / Double(epoch)
                let remaining = perEpoch * Double(totalEpochs - epoch)
                DispatchQueue.main.async {
                    self?.progressFraction = Double(epoch) / Double(totalEpochs)
                    self?.trainingProgress = "Эпоха \(epoch)/\(totalEpochs) · loss=\(String(format: "%.3f", loss)) · ~\(Int(remaining))с"
                }
            }

            self.net.saveWeights()

            DispatchQueue.main.async {
                self.isTrained = true
                self.isTraining = false
                self.progressFraction = 1
                self.trainedEpochs = self.net.trainedEpochs
                self.finalLoss = self.net.finalLoss
                self.trainingProgress = self.cancelRequested ? "Остановлено" : "Готово!"
            }
        }
    }

    func cancelTraining() {
        cancelRequested = true
    }

    func retrain() {
        SimpleNeuralNet.deleteSavedWeights()
        net = SimpleNeuralNet(inputSize: kGridSize * kGridSize, hiddenSize: 128)
        isTrained = false
        prediction = nil
        train()
    }

    func classify() {
        let input = grid.flatMap { row in row.map { $0 ? 1.0 : 0.0 } }
        prediction = net.classify(input: input)
    }

    func clearGrid() {
        grid = Array(repeating: Array(repeating: false, count: kGridSize), count: kGridSize)
        prediction = nil
    }

    func paint(row: Int, col: Int) {
        var changed = false
        let r = brushRadius
        for dr in -r...r {
            for dc in -r...r {
                guard dr * dr + dc * dc <= r * r else { continue }
                let nr = row + dr
                let nc = col + dc
                guard nr >= 0, nr < kGridSize, nc >= 0, nc < kGridSize else { continue }
                if !grid[nr][nc] {
                    grid[nr][nc] = true
                    changed = true
                }
            }
        }
        if changed && isTrained {
            classify()
        }
    }
}

struct NeuralNetView: View {
    @StateObject private var model = NeuralNetModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isTraining || !model.isTrained {
                        trainingSection
                    } else {
                        trainedStatusBar
                    }

                    drawingGrid

                    if let pred = model.prediction {
                        resultSection(pred)
                    }

                    buttonRow

                    if model.isTrained && model.prediction == nil {
                        Text("Рисуйте цифру пальцем на сетке 50×50")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Нейронная сеть")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var trainingSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 44))
                .foregroundColor(.purple)

            Text("Перцептрон 2500→128→10")
                .font(.title3.bold())

            Text("Нейросеть распознаёт цифры 0–9, нарисованные на сетке 50×50 пикселей.\nОбучается методом обратного распространения ошибки (backpropagation).\n\nПосле первого обучения веса сохраняются в файл — повторное обучение не нужно.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if model.isTraining {
                ProgressView(value: model.progressFraction)
                    .progressViewStyle(.linear)
                    .tint(.purple)
                Text(model.trainingProgress)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button(role: .destructive) {
                    model.cancelTraining()
                } label: {
                    Label("Остановить", systemImage: "stop.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    model.train()
                } label: {
                    Label("Обучить сеть", systemImage: "play.fill")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Обучение займёт ~15–60 секунд. Это произойдёт только один раз.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private var trainedStatusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Сеть обучена")
                    .font(.caption.bold())
                Text("\(model.trainedEpochs) эпох · \(model.trainingSamples) обр. · loss=\(String(format: "%.3f", model.finalLoss))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                model.retrain()
            } label: {
                Label("Переобучить", systemImage: "arrow.clockwise")
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var drawingGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Нарисуйте цифру пальцем")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("50×50 px")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 6)

            DrawingGridView(model: model)
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                )
        }
    }

    private func resultSection(_ pred: (digit: Int, confidence: Double, all: [Double])) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Text("\(pred.digit)")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Распознано")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", pred.confidence * 100))%")
                        .font(.title2.bold())
                        .foregroundColor(pred.confidence > 0.7 ? .green : .orange)
                }
            }

            VStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { digit in
                    HStack(spacing: 6) {
                        Text("\(digit)")
                            .font(.caption2.bold())
                            .frame(width: 14)
                            .foregroundColor(digit == pred.digit ? .purple : .secondary)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(.systemGray5))

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(digit == pred.digit ? Color.purple : Color.purple.opacity(0.3))
                                    .frame(width: max(2, geo.size.width * CGFloat(pred.all[digit])))
                            }
                        }
                        .frame(height: 12)

                        Text("\(String(format: "%.0f", pred.all[digit] * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private var buttonRow: some View {
        HStack(spacing: 12) {
            Button {
                model.clearGrid()
            } label: {
                Label("Очистить", systemImage: "trash")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if model.isTrained {
                Button {
                    model.classify()
                } label: {
                    Label("Распознать", systemImage: "sparkle.magnifyingglass")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

struct DrawingGridView: UIViewRepresentable {
    @ObservedObject var model: NeuralNetModel

    func makeUIView(context: Context) -> DrawingGridUIView {
        let view = DrawingGridUIView()
        view.model = model
        view.backgroundColor = .white

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                          action: #selector(DrawingGridCoordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(DrawingGridCoordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: DrawingGridUIView, context: Context) {
        uiView.model = model
        uiView.setNeedsDisplay()
    }

    func makeCoordinator() -> DrawingGridCoordinator {
        DrawingGridCoordinator(model: model)
    }
}

final class DrawingGridCoordinator: NSObject {
    var model: NeuralNetModel
    weak var view: DrawingGridUIView?

    init(model: NeuralNetModel) { self.model = model }

    private func cellAt(_ point: CGPoint) -> (row: Int, col: Int)? {
        guard let v = view else { return nil }
        let cellW = v.bounds.width / CGFloat(kGridSize)
        let cellH = v.bounds.height / CGFloat(kGridSize)
        let col = Int(point.x / cellW)
        let row = Int(point.y / cellH)
        guard row >= 0, row < kGridSize, col >= 0, col < kGridSize else { return nil }
        return (row, col)
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let pt = gesture.location(in: view)
        if let cell = cellAt(pt) {
            model.paint(row: cell.row, col: cell.col)
            view?.setNeedsDisplay()
        }
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        let pt = gesture.location(in: view)
        if let cell = cellAt(pt) {
            model.paint(row: cell.row, col: cell.col)
            view?.setNeedsDisplay()
        }
    }
}

final class DrawingGridUIView: UIView {
    var model: NeuralNetModel?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let model = model else { return }

        let n = kGridSize
        let cellW = bounds.width / CGFloat(n)
        let cellH = bounds.height / CGFloat(n)

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(bounds)

        ctx.setFillColor(UIColor.systemPurple.cgColor)
        for row in 0..<n {
            for col in 0..<n {
                if model.grid[row][col] {
                    ctx.fill(CGRect(x: CGFloat(col) * cellW,
                                    y: CGFloat(row) * cellH,
                                    width: cellW, height: cellH))
                }
            }
        }

        ctx.setStrokeColor(UIColor.systemGray4.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        for i in stride(from: 0, through: n, by: 10) {
            let x = CGFloat(i) * cellW
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: bounds.height))

            let y = CGFloat(i) * cellH
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        ctx.strokePath()

        ctx.setStrokeColor(UIColor.systemGray3.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(bounds)
    }
}

#Preview {
    NeuralNetView()
}
