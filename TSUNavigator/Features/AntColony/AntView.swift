import SwiftUI
import Combine

final class AntModel: ObservableObject {
    @Published var selectedPlaces: [FoodPlace] = []
    @Published var result: AntResult?
    @Published var isRunning = false

    @Published var antCount: Double = 30
    @Published var iterations: Double = 100
    @Published var evaporation: Double = 0.4

    let allPlaces: [FoodPlace]
    private let gridCols: Int
    private let gridRows: Int
    private let mapW: CGFloat = 838
    private let mapH: CGFloat = 686

    init(places: [FoodPlace], gridCols: Int, gridRows: Int) {
        self.allPlaces = places
        self.gridCols = gridCols
        self.gridRows = gridRows
    }

    var availablePlaces: [FoodPlace] {
        allPlaces.filter { $0.campusBuildingCell != nil }
    }

    func pixelPosition(for place: FoodPlace) -> CGPoint? {
        guard let ref = place.campusBuildingCell else { return nil }
        let cellW = mapW / CGFloat(gridCols)
        let cellH = mapH / CGFloat(gridRows)
        return CGPoint(x: CGFloat(ref.col) * cellW + cellW / 2,
                       y: CGFloat(ref.row) * cellH + cellH / 2)
    }

    func toggle(place: FoodPlace) {
        if let idx = selectedPlaces.firstIndex(where: { $0.id == place.id }) {
            selectedPlaces.remove(at: idx)
        } else {
            selectedPlaces.append(place)
        }
        result = nil
    }

    func isSelected(_ place: FoodPlace) -> Bool {
        selectedPlaces.contains(where: { $0.id == place.id })
    }

    func clear() {
        selectedPlaces = []
        result = nil
    }

    func run() {
        guard selectedPlaces.count >= 3 else { return }
        isRunning = true
        let cities = selectedPlaces.enumerated().compactMap { (i, place) -> AntCity? in
            guard let pos = pixelPosition(for: place) else { return nil }
            return AntCity(id: i, name: place.name, x: Double(pos.x), y: Double(pos.y))
        }
        let ants = Int(antCount)
        let iters = Int(iterations)
        let evap = evaporation

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let algo = AntColonyAlgorithm(antCount: ants, evaporation: evap)
            let res = algo.run(cities: cities, iterations: iters)
            DispatchQueue.main.async {
                self?.result = res
                self?.isRunning = false
            }
        }
    }
}

struct AntView: View {
    let places: [FoodPlace]
    let gridCols: Int
    let gridRows: Int

    @StateObject private var model: AntModel

    init(places: [FoodPlace], gridCols: Int = 711, gridRows: Int = 533) {
        self.places = places
        self.gridCols = gridCols
        self.gridRows = gridRows
        _model = StateObject(wrappedValue: AntModel(
            places: places, gridCols: gridCols, gridRows: gridRows))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if model.availablePlaces.isEmpty {
                    noPlacesView
                } else {
                    placeSelector
                        .frame(height: 120)

                    AntCanvasRepresentable(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    controlPanel
                }
            }
            .navigationTitle("Муравьиный алгоритм")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сбросить") { model.clear() }
                        .font(.caption)
                }
            }
        }
    }

    private var noPlacesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("Нет привязанных заведений")
                .font(.title3.bold())
            Text("Перейдите во вкладку «Еда» и привяжите заведения к зданиям на карте. После этого вы сможете строить оптимальный маршрут обхода.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var placeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Выберите заведения для маршрута")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(model.selectedPlaces.count) выбрано")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.availablePlaces) { place in
                        placePill(place)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func placePill(_ place: FoodPlace) -> some View {
        let selected = model.isSelected(place)
        return Button {
            model.toggle(place: place)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: place.category.icon)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name)
                        .font(.caption2.bold())
                        .lineLimit(1)
                    Text(place.priceLevel.short)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Color.brown.opacity(0.15) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.brown : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var controlPanel: some View {
        VStack(spacing: 8) {
            if let r = model.result {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.brown)
                    Text("Маршрут: \(Int(r.bestDistance)) px · \(r.iterations) итераций")
                        .font(.caption.bold())
                    Spacer()
                }
            }

            VStack(spacing: 3) {
                paramSlider("Муравьи", value: $model.antCount, range: 10...100, step: 5)
                paramSlider("Итерации", value: $model.iterations, range: 20...300, step: 10)
                HStack {
                    Text("Испарение: \(String(format: "%.0f%%", model.evaporation * 100))")
                        .font(.caption2).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
                    Slider(value: $model.evaporation, in: 0.1...0.9, step: 0.05)
                }
            }

            Button {
                model.run()
            } label: {
                HStack {
                    if model.isRunning { ProgressView().tint(.white) }
                    Text(model.isRunning ? "Вычисление..." : "Найти маршрут")
                        .font(.body.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(model.selectedPlaces.count < 3 || model.isRunning ? Color.gray : Color.brown)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(model.selectedPlaces.count < 3 || model.isRunning)

            if model.selectedPlaces.count < 3 {
                Text("Выберите минимум 3 заведения")
                    .font(.caption2).foregroundColor(.secondary)
            }

            if let r = model.result {
                routeOrder(r)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
    }

    private func paramSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text("\(label): \(Int(value.wrappedValue))")
                .font(.caption2).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range, step: step)
        }
    }

    private func routeOrder(_ r: AntResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Порядок обхода:")
                .font(.caption2.bold())
                .foregroundColor(.secondary)
            let names = r.bestRoute.map { idx in
                idx < model.selectedPlaces.count ? model.selectedPlaces[idx].name : "?"
            }
            Text(names.joined(separator: " → "))
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(3)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AntCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var model: AntModel

    private static let canvasSize = CGSize(width: 838, height: 686)

    func makeUIView(context: Context) -> UIScrollView {
        let imgSize = Self.canvasSize

        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 0.4
        scroll.maximumZoomScale = 8.0
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.backgroundColor = .white

        let container = UIView(frame: CGRect(origin: .zero, size: imgSize))
        container.backgroundColor = .clear
        context.coordinator.container = container

        let mapImage = UIImage(named: "mapEatTSU") ?? UIImage()
        let imageView = UIImageView(image: mapImage)
        imageView.frame = CGRect(origin: .zero, size: imgSize)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        container.addSubview(imageView)

        let canvas = AntCanvas(frame: CGRect(origin: .zero, size: imgSize))
        canvas.backgroundColor = .clear
        canvas.isUserInteractionEnabled = false
        canvas.coordinator = context.coordinator
        context.coordinator.canvas = canvas
        container.addSubview(canvas)

        scroll.addSubview(container)
        scroll.contentSize = imgSize

        DispatchQueue.main.async {
            let scaleX = scroll.bounds.width / imgSize.width
            let scaleY = scroll.bounds.height / imgSize.height
            scroll.setZoomScale(min(scaleX, scaleY), animated: false)
            context.coordinator.centerContent(in: scroll)
        }

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.canvas?.setNeedsDisplay()
    }

    func makeCoordinator() -> AntCoordinator { AntCoordinator(model: model) }
}

final class AntCoordinator: NSObject, UIScrollViewDelegate {
    var model: AntModel
    weak var canvas: AntCanvas?
    weak var container: UIView?

    init(model: AntModel) { self.model = model }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent(in: scrollView) }

    func centerContent(in scrollView: UIScrollView) {
        guard let c = container else { return }
        let offsetX = max((scrollView.bounds.width - c.frame.width) / 2, 0)
        let offsetY = max((scrollView.bounds.height - c.frame.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX,
                                                bottom: offsetY, right: offsetX)
    }
}

final class AntCanvas: UIView {
    weak var coordinator: AntCoordinator?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }

        let model = coord.model
        let places = model.selectedPlaces

        var positions: [CGPoint] = []
        for place in places {
            if let pos = model.pixelPosition(for: place) {
                positions.append(pos)
            }
        }

        guard !positions.isEmpty else { return }

        if let result = model.result, !result.pheromoneMatrix.isEmpty {
            let maxPher = result.pheromoneMatrix.flatMap { $0 }.max() ?? 1.0

            for i in 0..<positions.count {
                for j in (i+1)..<positions.count {
                    guard i < result.pheromoneMatrix.count, j < result.pheromoneMatrix[i].count else { continue }
                    let pher = result.pheromoneMatrix[i][j]
                    let intensity = CGFloat(pher / maxPher)
                    guard intensity > 0.05 else { continue }

                    ctx.setStrokeColor(UIColor.systemBrown.withAlphaComponent(intensity * 0.4).cgColor)
                    ctx.setLineWidth(max(intensity * 3.0, 0.5))
                    ctx.move(to: positions[i])
                    ctx.addLine(to: positions[j])
                    ctx.strokePath()
                }
            }
        }

        if let result = model.result {
            let route = result.bestRoute
            guard route.count >= 2 else { return }

            ctx.setStrokeColor(UIColor.systemBrown.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(3.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            ctx.move(to: positions[route[0]])
            for i in 1..<route.count {
                ctx.addLine(to: positions[route[i]])
            }
            ctx.addLine(to: positions[route[0]])
            ctx.strokePath()

            for i in 0..<route.count {
                let from = positions[route[i]]
                let to = positions[route[(i + 1) % route.count]]
                drawArrow(ctx: ctx, from: from, to: to, color: .systemBrown)
            }
        }

        for (i, pos) in positions.enumerated() {
            let place = places[i]
            let r: CGFloat = 14

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                          color: UIColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(UIColor.systemIndigo.cgColor)
            ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))
            ctx.restoreGState()

            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))

            let icon = UIImage(systemName: place.category.icon)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            if let icon = icon {
                let iconSize: CGFloat = 14
                icon.draw(in: CGRect(x: pos.x - iconSize / 2, y: pos.y - iconSize / 2,
                                     width: iconSize, height: iconSize))
            }

            if let result = model.result,
               let routeIdx = result.bestRoute.firstIndex(of: i) {
                let label = "\(routeIdx + 1)" as NSString
                let font = UIFont.boldSystemFont(ofSize: 9)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor.systemBrown
                ]
                label.draw(at: CGPoint(x: pos.x + r - 2, y: pos.y - r - 2),
                           withAttributes: attrs)
            }

            let name = place.name as NSString
            let nameFont = UIFont.systemFont(ofSize: 7, weight: .semibold)
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: UIColor.black,
                .backgroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            let nameSz = name.size(withAttributes: nameAttrs)
            name.draw(at: CGPoint(x: pos.x - nameSz.width / 2, y: pos.y + r + 2),
                      withAttributes: nameAttrs)
        }
    }

    private func drawArrow(ctx: CGContext, from: CGPoint, to: CGPoint, color: UIColor) {
        let mx = (from.x + to.x) / 2
        let my = (from.y + to.y) / 2
        let angle = atan2(to.y - from.y, to.x - from.x)

        ctx.saveGState()
        ctx.translateBy(x: mx, y: my)
        ctx.rotate(by: angle)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 6, y: 0))
        path.addLine(to: CGPoint(x: -4, y: -4))
        path.addLine(to: CGPoint(x: -4, y: 4))
        path.closeSubpath()
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.restoreGState()
    }
}

#Preview {
    AntView(places: loadPlaces())
}
