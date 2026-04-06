import SwiftUI
import UIKit
import Combine

private let clusterUIColors: [UIColor] = [
    .systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple,
    .systemPink, .systemCyan, .brown
]

private let clusterSwiftColors: [Color] = [
    .red, .blue, .green, .orange, .purple, .pink, .cyan, .brown
]


final class ClusteringModel: ObservableObject {
    @Published var points: [ClusterPoint] = []
    @Published var result: KMeansResult?

    func addPoint(x: Double, y: Double) {
        points.append(ClusterPoint(x: x, y: y))
        result = nil
    }

    func removeLastPoint() {
        guard !points.isEmpty else { return }
        points.removeLast()
        result = nil
    }

    func clearAll() {
        points.removeAll()
        result = nil
    }
}


struct ClusteringView: View {
    let places: [FoodPlace]

    @StateObject private var clusterModel = ClusteringModel()
    @State private var k = 3
    @State private var mode = 0
    @State private var elbowData: [(k: Int, wcss: Double)] = []

    private let algo = KMeansAlgorithm()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Режим", selection: $mode) {
                    Text("Карта").tag(0)
                    Text("Шаги").tag(1)
                    Text("Локоть").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                switch mode {
                case 0:  mapTab
                case 1:  stepsTab
                default: elbowTab
                }
            }
            .navigationTitle("Кластеризация")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var mapTab: some View {
        VStack(spacing: 0) {
            hintBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            kSlider
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            ClusterMapUIView(clusterModel: clusterModel)
                .ignoresSafeArea(edges: .horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlButtons
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if let result = clusterModel.result {
                legendBar(result: result)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
    }

    private var hintBar: some View {
        HStack(spacing: 6) {
            Image(systemName: clusterModel.result != nil ? "checkmark.circle.fill" : "hand.tap")
                .foregroundColor(clusterModel.result != nil ? .green : .blue)
            if clusterModel.points.isEmpty {
                Text("Нажимайте на карту, чтобы расставить точки")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if clusterModel.result != nil {
                Text("Точек: \(clusterModel.points.count) · K=\(clusterModel.result!.k) · Итераций: \(clusterModel.result!.iterations)")
                    .font(.caption)
            } else {
                Text("Точек: \(clusterModel.points.count) — нажмите «Кластеризовать»")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var kSlider: some View {
        HStack {
            Text("K = \(k)")
                .font(.subheadline.bold().monospacedDigit())
                .frame(width: 50)
            Slider(value: Binding(
                get: { Double(k) },
                set: { k = max(2, Int($0)) }
            ), in: 2...7, step: 1)
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            Button {
                runClustering()
            } label: {
                Label("Кластеризовать", systemImage: "sparkles")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(canRun ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!canRun)

            Button {
                clusterModel.removeLastPoint()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.bold())
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(clusterModel.points.isEmpty)

            Button {
                clusterModel.clearAll()
                elbowData = []
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.bold())
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color(.systemGray5))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(clusterModel.points.isEmpty)
        }
    }

    private var canRun: Bool {
        clusterModel.points.count >= k
    }

    private func legendBar(result: KMeansResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            let groups = Dictionary(grouping: result.points.filter { $0.cluster >= 0 }) { $0.cluster }
            ForEach(groups.keys.sorted(), id: \.self) { clusterIdx in
                HStack(spacing: 6) {
                    Circle()
                        .fill(clusterSwiftColors[clusterIdx % clusterSwiftColors.count])
                        .frame(width: 10, height: 10)
                    Text("Кластер \(clusterIdx + 1)")
                        .font(.caption.bold())
                    Text("\(groups[clusterIdx]?.count ?? 0) точек")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Spacer()
                Text("WCSS: \(String(format: "%.1f", result.wcss))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }


    private var stepsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                theoryCard

                if let result = clusterModel.result {
                    ForEach(result.steps) { step in
                        StepCard(step: step)
                    }
                } else {
                    Text("Сначала расставьте точки и запустите кластеризацию")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
        }
    }

    private var theoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Алгоритм K-Means", systemImage: "graduationcap")
                .font(.headline)
            Text("Итеративный алгоритм кластеризации. Разбивает N точек на K групп, минимизируя суммарное расстояние до центроидов.")
                .font(.caption)
                .foregroundColor(.secondary)

            FormulaBlock(title: "Цель:",
                         text: "min WCSS = \u{2211}\u{1D62} \u{2211}(x\u{2208}C\u{1D62}) ||x - \u{03BC}\u{1D62}||\u{00B2}")
            FormulaBlock(title: "Шаги:",
                         text: "1. Инициализация K центроидов (K-Means++)\n2. Назначение точек → ближайший центроид\n3. Пересчёт центроидов = среднее кластера\n4. Повторять 2-3 до сходимости")
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var elbowTab: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Метод локтя", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Text("WCSS для разных K. Оптимальное K — в точке «изгиба».")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if clusterModel.points.count < 2 {
                Spacer()
                Text("Сначала расставьте минимум 2 точки на карте")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else if elbowData.isEmpty {
                Spacer()
                Button {
                    elbowData = algo.elbowData(points: clusterModel.points,
                                                maxK: min(7, clusterModel.points.count))
                } label: {
                    Label("Рассчитать", systemImage: "play.fill")
                        .font(.body.bold())
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                Spacer()
            } else {
                ElbowChartView(data: elbowData)
                    .frame(height: 200)
                    .padding(.horizontal)

                VStack(spacing: 2) {
                    HStack {
                        Text("K").font(.caption.bold()).frame(width: 30)
                        Text("WCSS").font(.caption.bold())
                        Spacer()
                    }
                    ForEach(elbowData, id: \.k) { item in
                        HStack {
                            Text("\(item.k)").font(.caption).frame(width: 30)
                            Text(String(format: "%.1f", item.wcss))
                                .font(.system(size: 10, design: .monospaced))
                            Spacer()
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                Spacer()
            }
        }
    }


    private func runClustering() {
        guard canRun else { return }
        clusterModel.result = algo.run(points: clusterModel.points, k: k)
        elbowData = []
    }
}


private struct ClusterMapUIView: UIViewRepresentable {
    @ObservedObject var clusterModel: ClusteringModel

    private static let mapImageSize = CGSize(width: 838, height: 686)

    func makeUIView(context: Context) -> UIScrollView {
        let imgSize = Self.mapImageSize

        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 0.4
        scroll.maximumZoomScale = 15.0
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.backgroundColor = UIColor(white: 0.93, alpha: 1)

        let container = UIView(frame: CGRect(origin: .zero, size: imgSize))
        context.coordinator.container = container

        let mapImage = UIImage(named: "mapEatTSU") ?? UIImage()
        let imageView = UIImageView(image: mapImage)
        imageView.frame = CGRect(origin: .zero, size: imgSize)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        container.addSubview(imageView)

        let canvas = ClusterCanvas(frame: CGRect(origin: .zero, size: imgSize))
        canvas.backgroundColor = .clear
        canvas.isUserInteractionEnabled = true
        canvas.coordinator = context.coordinator
        context.coordinator.canvas = canvas
        container.addSubview(canvas)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        canvas.addGestureRecognizer(tap)

        scroll.addSubview(container)
        scroll.contentSize = imgSize

        DispatchQueue.main.async {
            context.coordinator.fitMap(in: scroll)
        }

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.clusterModel = clusterModel
        context.coordinator.canvas?.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(clusterModel: clusterModel)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var clusterModel: ClusteringModel

        weak var canvas: ClusterCanvas?
        weak var container: UIView?

        init(clusterModel: ClusteringModel) {
            self.clusterModel = clusterModel
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let c = container else { return }
            let offsetX = max((scrollView.bounds.width  - c.frame.width)  / 2, 0)
            let offsetY = max((scrollView.bounds.height - c.frame.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: offsetY, left: offsetX, bottom: offsetY, right: offsetX
            )
        }

        func fitMap(in scroll: UIScrollView) {
            guard scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            let imgSize = ClusterMapUIView.mapImageSize
            let scale = min(scroll.bounds.width / imgSize.width,
                            scroll.bounds.height / imgSize.height)
            scroll.setZoomScale(scale, animated: false)
            scrollViewDidZoom(scroll)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let pt = gesture.location(in: canvas)
            // Добавляем точку в пиксельных координатах карты
            clusterModel.addPoint(x: pt.x, y: pt.y)
            canvas?.setNeedsDisplay()
        }
    }
}


private final class ClusterCanvas: UIView {
    weak var coordinator: ClusterMapUIView.Coordinator?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }

        let model = coord.clusterModel
        let result = model.result

        if let result = result {
            drawClustered(ctx: ctx, result: result)
        } else {
            drawUnclustered(ctx: ctx, points: model.points)
        }
    }

    private func drawUnclustered(ctx: CGContext, points: [ClusterPoint]) {
        for (i, p) in points.enumerated() {
            let r: CGFloat = 6

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                          color: UIColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(UIColor.systemGray.cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r,
                                       width: r * 2, height: r * 2))
            ctx.restoreGState()

            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r,
                                         width: r * 2, height: r * 2))

            let font = UIFont.systemFont(ofSize: 7, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: UIColor.white
            ]
            let label = "\(i + 1)" as NSString
            let sz = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: p.x - sz.width / 2,
                                   y: p.y - sz.height / 2),
                       withAttributes: attrs)
        }
    }

    private func drawClustered(ctx: CGContext, result: KMeansResult) {
        let points = result.points
        let centroids = result.centroids

        for (clusterIdx, _) in centroids.enumerated() {
            let color = clusterUIColors[clusterIdx % clusterUIColors.count]
            ctx.setFillColor(color.withAlphaComponent(0.08).cgColor)

            let members = points.filter { $0.cluster == clusterIdx }
            for p in members {
                let radius: CGFloat = 30
                ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius,
                                           width: radius * 2, height: radius * 2))
            }
        }

        for (clusterIdx, centroid) in centroids.enumerated() {
            let color = clusterUIColors[clusterIdx % clusterUIColors.count]
            ctx.setStrokeColor(color.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1.0)
            ctx.setLineDash(phase: 0, lengths: [3, 3])

            let members = points.filter { $0.cluster == clusterIdx }
            for p in members {
                ctx.move(to: CGPoint(x: p.x, y: p.y))
                ctx.addLine(to: CGPoint(x: centroid.x, y: centroid.y))
            }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        for p in points {
            guard p.cluster >= 0 else { continue }
            let color = clusterUIColors[p.cluster % clusterUIColors.count]
            let r: CGFloat = 6

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                          color: UIColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r,
                                       width: r * 2, height: r * 2))
            ctx.restoreGState()

            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r,
                                         width: r * 2, height: r * 2))
        }

        for (i, c) in centroids.enumerated() {
            let color = clusterUIColors[i % clusterUIColors.count]
            let s: CGFloat = 9

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                          color: UIColor.black.withAlphaComponent(0.4).cgColor)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - s, y: c.y - s,
                                       width: s * 2, height: s * 2))
            ctx.restoreGState()

            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(2.5)
            let d: CGFloat = s * 0.5
            ctx.move(to: CGPoint(x: c.x - d, y: c.y - d))
            ctx.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            ctx.move(to: CGPoint(x: c.x + d, y: c.y - d))
            ctx.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
            ctx.strokePath()
        }
    }
}

private struct StepCard: View {
    let step: KMeansStep

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(step.phase.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(phaseColor.opacity(0.2))
                    .foregroundColor(phaseColor)
                    .clipShape(Capsule())

                if step.iteration > 0 {
                    Text("Итерация \(step.iteration)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Text(step.description)
                .font(.caption)

            if step.phase == .assign || step.phase == .converged {
                let groups = Dictionary(grouping: step.points.filter { $0.cluster >= 0 }) { $0.cluster }
                HStack(spacing: 12) {
                    ForEach(groups.keys.sorted(), id: \.self) { cl in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(clusterSwiftColors[cl % clusterSwiftColors.count])
                                .frame(width: 8, height: 8)
                            Text("\(groups[cl]?.count ?? 0)")
                                .font(.caption2.bold())
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var phaseColor: Color {
        switch step.phase {
        case .initial:   return .purple
        case .assign:    return .blue
        case .update:    return .orange
        case .converged: return .green
        }
    }
}


private struct ElbowChartView: View {
    let data: [(k: Int, wcss: Double)]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pad: CGFloat = 40
            let maxWCSS = data.map(\.wcss).max() ?? 1
            let minK = data.map(\.k).min() ?? 1
            let maxK = data.map(\.k).max() ?? 8

            Canvas { ctx, _ in
                var axis = Path()
                axis.move(to: CGPoint(x: pad, y: pad / 2))
                axis.addLine(to: CGPoint(x: pad, y: h - pad))
                axis.addLine(to: CGPoint(x: w - 10, y: h - pad))
                ctx.stroke(axis, with: .color(.secondary), lineWidth: 1)

                let pts: [CGPoint] = data.map { item in
                    let xp = pad + (CGFloat(item.k - minK) / CGFloat(max(1, maxK - minK))) * (w - pad - 10)
                    let yp = (h - pad) - (item.wcss / maxWCSS) * (h - pad - pad / 2)
                    return CGPoint(x: xp, y: yp)
                }

                if pts.count > 1 {
                    var line = Path()
                    line.move(to: pts[0])
                    for p in pts.dropFirst() { line.addLine(to: p) }
                    ctx.stroke(line, with: .color(.blue), lineWidth: 2)
                }

                for (i, p) in pts.enumerated() {
                    ctx.fill(Circle().path(in: CGRect(x: p.x - 5, y: p.y - 5,
                                                      width: 10, height: 10)),
                             with: .color(.blue))
                    ctx.draw(Text("\(data[i].k)").font(.system(size: 10)),
                             at: CGPoint(x: p.x, y: h - pad + 14))
                }

                ctx.draw(Text("K").font(.caption.bold()), at: CGPoint(x: w / 2, y: h - 5))
                ctx.draw(Text("WCSS").font(.caption.bold()), at: CGPoint(x: 14, y: h / 2))
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct FormulaBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold())
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

#Preview {
    ClusteringView(places: loadPlaces())
}
