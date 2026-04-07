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
    @Published var comparison: MetricComparison?

    func addPoint(x: Double, y: Double) {
        points.append(ClusterPoint(x: x, y: y))
        result = nil
        comparison = nil
    }

    func removeLastPoint() {
        guard !points.isEmpty else { return }
        points.removeLast()
        result = nil
        comparison = nil
    }

    func clearAll() {
        points.removeAll()
        result = nil
        comparison = nil
    }
}

struct ClusteringView: View {
    let places: [FoodPlace]

    @StateObject private var clusterModel = ClusteringModel()
    @State private var k = 3

    private let algo = KMeansAlgorithm()

    var body: some View {
        NavigationView {
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

                if let cmp = clusterModel.comparison {
                    comparisonLegend(cmp: cmp)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                } else if let result = clusterModel.result {
                    simpleLegend(result: result)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            }
            .navigationTitle("Кластеризация")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var hintBar: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            Text(statusText)
                .font(.caption)
                .foregroundColor(clusterModel.result != nil ? .primary : .secondary)
            Spacer()
        }
    }

    private var statusIcon: String {
        if clusterModel.comparison != nil { return "arrow.triangle.branch" }
        if clusterModel.result != nil { return "checkmark.circle.fill" }
        return "hand.tap"
    }
    private var statusColor: Color {
        if clusterModel.comparison != nil { return .purple }
        if clusterModel.result != nil { return .green }
        return .blue
    }
    private var statusText: String {
        if let cmp = clusterModel.comparison {
            return "Сравнение метрик · Конфликтов: \(cmp.conflictIndices.count) из \(clusterModel.points.count)"
        }
        if let r = clusterModel.result {
            return "Точек: \(clusterModel.points.count) · K=\(r.k) · \(r.metric.rawValue)"
        }
        if clusterModel.points.isEmpty {
            return "Нажимайте на карту, чтобы расставить точки"
        }
        return "Точек: \(clusterModel.points.count) — нажмите кнопку"
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
        VStack(spacing: 8) {

            HStack(spacing: 8) {
                Button {
                    clusterModel.comparison = nil
                    clusterModel.result = algo.run(points: clusterModel.points, k: k, metric: .euclidean)
                } label: {
                    Text("Евклидово")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(canRun ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canRun)

                Button {
                    clusterModel.comparison = nil
                    clusterModel.result = algo.run(points: clusterModel.points, k: k, metric: .manhattan)
                } label: {
                    Text("Манхэттен")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(canRun ? Color.orange : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canRun)
            }

            HStack(spacing: 8) {

                Button {
                    let cmp = algo.compare(points: clusterModel.points, k: k)
                    clusterModel.result = cmp.euclidean
                    clusterModel.comparison = cmp
                } label: {
                    Label("Сравнить метрики", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(canRun ? Color.purple : Color.gray.opacity(0.3))
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
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(clusterModel.points.isEmpty)

                Button {
                    clusterModel.clearAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.bold())
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray5))
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(clusterModel.points.isEmpty)
            }
        }
    }

    private var canRun: Bool {
        clusterModel.points.count >= k
    }

    private func simpleLegend(result: KMeansResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Метрика: \(result.metric.rawValue)")
                    .font(.caption.bold())
                Spacer()
                Text("Итераций: \(result.iterations)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            let groups = Dictionary(grouping: result.points.filter { $0.cluster >= 0 }) { $0.cluster }
            ForEach(groups.keys.sorted(), id: \.self) { idx in
                HStack(spacing: 6) {
                    Circle()
                        .fill(clusterSwiftColors[idx % clusterSwiftColors.count])
                        .frame(width: 10, height: 10)
                    Text("Кластер \(idx + 1)")
                        .font(.caption.bold())
                    Text("\(groups[idx]?.count ?? 0) точек")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func comparisonLegend(cmp: MetricComparison) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if cmp.conflicts.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Обе метрики дали одинаковый результат!")
                        .font(.caption.bold())
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("\(cmp.conflicts.count) точек попали в разные кластеры")
                        .font(.caption.bold())
                }

                ForEach(cmp.conflicts, id: \.index) { c in
                    HStack(spacing: 4) {
                        Text("Точка \(c.index + 1):")
                            .font(.caption2)
                        Circle()
                            .fill(clusterSwiftColors[c.eucCluster % clusterSwiftColors.count])
                            .frame(width: 8, height: 8)
                        Text("Евкл. → \(c.eucCluster + 1)")
                            .font(.caption2)
                        Circle()
                            .fill(clusterSwiftColors[c.manCluster % clusterSwiftColors.count])
                            .frame(width: 8, height: 8)
                        Text("Манх. → \(c.manCluster + 1)")
                            .font(.caption2)
                    }
                }

                Text("Конфликтные точки обведены пунктиром на карте")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            let ox = max((scrollView.bounds.width  - c.frame.width)  / 2, 0)
            let oy = max((scrollView.bounds.height - c.frame.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: oy, left: ox, bottom: oy, right: ox)
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

        if let cmp = model.comparison {
            drawComparison(ctx: ctx, cmp: cmp)
        } else if let result = model.result {
            drawClustered(ctx: ctx, result: result, conflicts: nil)
        } else {
            drawUnclustered(ctx: ctx, points: model.points)
        }
    }

    private func drawUnclustered(ctx: CGContext, points: [ClusterPoint]) {
        for (i, p) in points.enumerated() {
            drawDot(ctx: ctx, x: p.x, y: p.y, color: .systemGray, radius: 6)
            drawLabel(ctx: ctx, text: "\(i + 1)",
                      at: CGPoint(x: p.x, y: p.y), color: .white, fontSize: 7)
        }
    }

    private func drawClustered(ctx: CGContext, result: KMeansResult,
                                conflicts: Set<Int>?) {
        let points = result.points
        let centroids = result.centroids

        for ci in 0..<centroids.count {
            let color = clusterUIColors[ci % clusterUIColors.count]
            ctx.setFillColor(color.withAlphaComponent(0.08).cgColor)
            for p in points where p.cluster == ci {
                ctx.fillEllipse(in: CGRect(x: p.x - 30, y: p.y - 30, width: 60, height: 60))
            }
        }

        for (ci, centroid) in centroids.enumerated() {
            let color = clusterUIColors[ci % clusterUIColors.count]
            ctx.setStrokeColor(color.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1.0)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            for p in points where p.cluster == ci {
                ctx.move(to: CGPoint(x: p.x, y: p.y))
                ctx.addLine(to: CGPoint(x: centroid.x, y: centroid.y))
            }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        for (i, p) in points.enumerated() where p.cluster >= 0 {
            let color = clusterUIColors[p.cluster % clusterUIColors.count]
            drawDot(ctx: ctx, x: p.x, y: p.y, color: color, radius: 6)

            if let conflicts = conflicts, conflicts.contains(i) {
                ctx.setStrokeColor(UIColor.systemYellow.cgColor)
                ctx.setLineWidth(2.5)
                ctx.setLineDash(phase: 0, lengths: [3, 2])
                ctx.strokeEllipse(in: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20))
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }

        for (i, c) in centroids.enumerated() {
            drawCentroid(ctx: ctx, x: c.x, y: c.y,
                         color: clusterUIColors[i % clusterUIColors.count])
        }
    }

    private func drawComparison(ctx: CGContext, cmp: MetricComparison) {

        drawClustered(ctx: ctx, result: cmp.euclidean, conflicts: cmp.conflictIndices)

        for conflict in cmp.conflicts {
            let p = cmp.euclidean.points[conflict.index]
            let manColor = clusterUIColors[conflict.manCluster % clusterUIColors.count]

            let offsetX: CGFloat = 10
            let offsetY: CGFloat = -10
            let sr: CGFloat = 4

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 0.5), blur: 1,
                          color: UIColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(manColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x + offsetX - sr, y: p.y + offsetY - sr,
                                       width: sr * 2, height: sr * 2))
            ctx.restoreGState()

            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.0)
            ctx.strokeEllipse(in: CGRect(x: p.x + offsetX - sr, y: p.y + offsetY - sr,
                                         width: sr * 2, height: sr * 2))

            let font = UIFont.systemFont(ofSize: 5, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let str = "M" as NSString
            let sz = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(x: p.x + offsetX - sz.width / 2,
                                 y: p.y + offsetY - sz.height / 2),
                     withAttributes: attrs)
        }
    }

    private func drawDot(ctx: CGContext, x: Double, y: Double,
                         color: UIColor, radius: CGFloat) {
        let r = radius
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                      color: UIColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private func drawCentroid(ctx: CGContext, x: Double, y: Double, color: UIColor) {
        let s: CGFloat = 9
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                      color: UIColor.black.withAlphaComponent(0.4).cgColor)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2))
        ctx.restoreGState()

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2.5)
        let d: CGFloat = s * 0.5
        ctx.move(to: CGPoint(x: x - d, y: y - d))
        ctx.addLine(to: CGPoint(x: x + d, y: y + d))
        ctx.move(to: CGPoint(x: x + d, y: y - d))
        ctx.addLine(to: CGPoint(x: x - d, y: y + d))
        ctx.strokePath()
    }

    private func drawLabel(ctx: CGContext, text: String, at pt: CGPoint,
                           color: UIColor, fontSize: CGFloat) {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = text as NSString
        let sz = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: pt.x - sz.width / 2, y: pt.y - sz.height / 2),
                 withAttributes: attrs)
    }
}

#Preview {
    ClusteringView(places: loadPlaces())
}
