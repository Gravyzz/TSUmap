import SwiftUI
import Combine

final class GeneticModel: ObservableObject {

    @Published var selectedDishes: Set<SelectedDish> = []

    @Published var result: GeneticResult?
    @Published var isRunning = false
    @Published var liveStep: GeneticStep?

    @Published var populationSize: Double = 100
    @Published var generations: Double = 300
    @Published var mutationRate: Double = 0.20

    let allPlaces: [FoodPlace]
    let gridCols: Int
    let gridRows: Int
    private let mapW: CGFloat = 838
    private let mapH: CGFloat = 686

    var startX: Double { Double(mapW / 2) }
    var startY: Double { Double(mapH / 2) }

    init(places: [FoodPlace], gridCols: Int, gridRows: Int) {
        self.allPlaces = places
        self.gridCols = gridCols
        self.gridRows = gridRows
    }

    var boundPlaces: [FoodPlace] {
        allPlaces.filter { $0.campusBuildingCell != nil }
    }

    var allDishes: [(category: MenuItemCategory, items: [SelectedDish])] {
        var byCategory: [MenuItemCategory: [SelectedDish]] = [:]
        var seen = Set<String>()
        for place in boundPlaces {
            for item in place.menu {
                guard !seen.contains(item.name) else { continue }
                seen.insert(item.name)
                let dish = SelectedDish(id: item.name, name: item.name, category: item.category)
                byCategory[item.category, default: []].append(dish)
            }
        }
        let order: [MenuItemCategory] = [
            .breakfast, .soup, .hotMeal, .salad, .sandwich,
            .pastry, .dessert, .snack, .coffee, .tea, .drink, .grocery
        ]
        return order.compactMap { cat in
            guard let items = byCategory[cat], !items.isEmpty else { return nil }
            return (category: cat, items: items.sorted { $0.name < $1.name })
        }
    }

    var candidates: [RouteCandidate] {
        let dishNames = Set(selectedDishes.map(\.name))
        return boundPlaces.enumerated().compactMap { (i, place) -> RouteCandidate? in
            let offered = Set(place.menu.map(\.name)).intersection(dishNames)
            guard !offered.isEmpty else { return nil }
            guard let pos = pixelPosition(for: place) else { return nil }

            let closingMin = minutesUntilClosing(place: place)

            return RouteCandidate(
                placeIndex: i, place: place,
                x: Double(pos.x), y: Double(pos.y),
                dishesOffered: offered,
                closingMinutes: closingMin
            )
        }
    }

    func pixelPosition(for place: FoodPlace) -> CGPoint? {
        guard let ref = place.campusBuildingCell else { return nil }
        let cellW = mapW / CGFloat(gridCols)
        let cellH = mapH / CGFloat(gridRows)
        return CGPoint(x: CGFloat(ref.col) * cellW + cellW / 2,
                       y: CGFloat(ref.row) * cellH + cellH / 2)
    }

    func toggleDish(_ dish: SelectedDish) {
        if selectedDishes.contains(dish) {
            selectedDishes.remove(dish)
        } else {
            selectedDishes.insert(dish)
        }
        result = nil
        liveStep = nil
    }

    func clear() {
        selectedDishes = []
        result = nil
        liveStep = nil
    }

    func run() {
        let cands = candidates
        guard !cands.isEmpty else { return }
        isRunning = true
        liveStep = nil

        let dishNames = Set(selectedDishes.map(\.name))
        let popSize = Int(populationSize)
        let gens = Int(generations)
        let mutRate = mutationRate
        let sx = startX
        let sy = startY

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let algo = GeneticAlgorithm(populationSize: popSize, mutationRate: mutRate)
            let res = algo.run(
                candidates: cands,
                selectedDishes: dishNames,
                startX: sx, startY: sy,
                generations: gens
            ) { step in
                DispatchQueue.main.async {
                    self?.liveStep = step
                }
            }
            DispatchQueue.main.async {
                self?.result = res
                self?.isRunning = false
            }
        }
    }

    private func minutesUntilClosing(place: FoodPlace) -> Double? {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let isWeekend = (weekday == 1 || weekday == 7)

        let timeStr: String?
        if isWeekend {
            timeStr = place.schedule.weekends
        } else {
            timeStr = place.schedule.weekdays
        }

        guard let schedule = timeStr else {

            if place.schedule.note?.lowercased().contains("круглосуточно") == true {
                return nil
            }
            return nil
        }

        let parts = schedule.replacingOccurrences(of: " ", with: "")
            .components(separatedBy: CharacterSet(charactersIn: "–-—"))
        guard parts.count == 2 else { return nil }

        guard let closingTime = parseTime(parts[1]) else { return nil }

        let nowMinutes = Double(calendar.component(.hour, from: now)) * 60.0 +
                         Double(calendar.component(.minute, from: now))
        let diff = closingTime - nowMinutes

        return diff > 0 ? diff : 0
    }

    private func parseTime(_ str: String) -> Double? {
        let comps = str.components(separatedBy: ":")
        guard comps.count == 2,
              let h = Double(comps[0]),
              let m = Double(comps[1]) else { return nil }
        return h * 60.0 + m
    }
}

private enum ViewStep {
    case selectDishes
    case results
}

struct GeneticView: View {
    let places: [FoodPlace]
    let gridCols: Int
    let gridRows: Int

    @StateObject private var model: GeneticModel
    @State private var viewStep: ViewStep = .selectDishes

    init(places: [FoodPlace], gridCols: Int = 711, gridRows: Int = 533) {
        self.places = places
        self.gridCols = gridCols
        self.gridRows = gridRows
        _model = StateObject(wrappedValue: GeneticModel(
            places: places, gridCols: gridCols, gridRows: gridRows))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if model.boundPlaces.isEmpty {
                    noPlacesView
                } else {
                    switch viewStep {
                    case .selectDishes:
                        dishSelectionView

                    case .results:
                        resultsView
                    }
                }
            }
            .navigationTitle("Маршрут за обедом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewStep == .results {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Блюда") {
                            viewStep = .selectDishes
                            model.result = nil
                            model.liveStep = nil
                        }
                        .font(.caption)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сбросить") {
                        model.clear()
                        viewStep = .selectDishes
                    }
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
            Text("Перейдите во вкладку «Еда» и привяжите заведения к зданиям на карте.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var dishSelectionView: some View {
        VStack(spacing: 0) {

            VStack(spacing: 4) {
                Text("Что вы хотите?")
                    .font(.title3.bold())
                Text("Выберите блюда, которые хотите приобрести")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.allDishes, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: group.category.icon)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text(group.category.label)
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                            }

                            FlowLayout(spacing: 6) {
                                ForEach(group.items) { dish in
                                    dishChip(dish)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }

            VStack(spacing: 8) {
                if !model.selectedDishes.isEmpty {
                    let cands = model.candidates
                    HStack {
                        Text("\(model.selectedDishes.count) блюд из \(cands.count) заведений")
                            .font(.caption.bold())
                        Spacer()
                        let now = Date()
                        Text(now, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                DisclosureGroup("Параметры алгоритма") {
                    VStack(spacing: 3) {
                        paramSlider("Популяция", value: $model.populationSize, range: 40...200, step: 10)
                        paramSlider("Поколения", value: $model.generations, range: 100...500, step: 50)
                        HStack {
                            Text("Мутация: \(String(format: "%.0f%%", model.mutationRate * 100))")
                                .font(.caption2).foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            Slider(value: $model.mutationRate, in: 0.05...0.5, step: 0.05)
                        }
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                Button {
                    viewStep = .results
                    model.run()
                } label: {
                    Text("Построить маршрут")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(model.selectedDishes.isEmpty ? Color.gray : Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model.selectedDishes.isEmpty)
            }
            .padding(12)
            .background(Color(.systemBackground))
        }
    }

    private func dishChip(_ dish: SelectedDish) -> some View {
        let selected = model.selectedDishes.contains(dish)
        return Button { model.toggleDish(dish) } label: {
            Text(dish.name)
                .font(.caption2)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.green.opacity(0.2) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.green : Color.clear, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundColor(selected ? .green : .primary)
        }
        .buttonStyle(.plain)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {

            statusBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            GeneticCanvasRepresentable(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let result = model.result {
                resultDetails(result)
                    .padding(12)
            } else if let step = model.liveStep {
                liveStepBar(step)
                    .padding(12)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            if model.isRunning {
                ProgressView().controlSize(.small)
                if let step = model.liveStep {
                    Text("Поколение \(step.generation) · \(String(format: "%.0f%%", step.coverage * 100)) блюд · \(String(format: "%.0f", step.bestTime)) мин")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Запуск алгоритма...")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else if let r = model.result {
                Image(systemName: r.missingDishes.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(r.missingDishes.isEmpty ? .green : .orange)
                Text("Маршрут найден")
                    .font(.caption.bold())
            }
            Spacer()
        }
    }

    private func liveStepBar(_ step: GeneticStep) -> some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(step.generation), total: model.generations)
                .tint(.green)
            HStack {
                Text("Поколение \(step.generation)/\(Int(model.generations))")
                    .font(.caption2)
                Spacer()
                Text("\(step.bestRoute.count) мест · \(String(format: "%.0f", step.bestDistance)) м")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
    }

    private func resultDetails(_ r: GeneticResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 16) {
                statItem("Время", value: "\(String(format: "%.0f", r.bestTime)) мин",
                         icon: "clock", color: .blue)
                statItem("Путь", value: "\(Int(r.bestDistance)) м",
                         icon: "figure.walk", color: .green)
                statItem("Мест", value: "\(r.totalPlaces)",
                         icon: "building.2", color: .orange)
            }

            if !r.bestRoute.isEmpty {
                let cands = model.candidates
                VStack(alignment: .leading, spacing: 4) {
                    Text("Порядок обхода:")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    ForEach(Array(r.bestRoute.enumerated()), id: \.offset) { i, candIdx in
                        if candIdx < cands.count {
                            let place = cands[candIdx].place
                            let dishes = cands[candIdx].dishesOffered.intersection(
                                Set(model.selectedDishes.map(\.name)))
                            HStack(spacing: 6) {
                                Text("\(i + 1).")
                                    .font(.caption2.bold())
                                    .foregroundColor(.green)
                                    .frame(width: 16)
                                Image(systemName: place.category.icon)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(place.name)
                                        .font(.caption2.bold())
                                    Text(dishes.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let closing = cands[candIdx].closingMinutes {
                                    Text("\(Int(closing))м")
                                        .font(.caption2)
                                        .foregroundColor(closing < 30 ? .red : .secondary)
                                }
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !r.missingDishes.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Не найдено: \(r.missingDishes.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func statItem(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func paramSlider(_ label: String, value: Binding<Double>,
                              range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text("\(label): \(Int(value.wrappedValue))")
                .font(.caption2).foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Slider(value: value, in: range, step: step)
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (idx, pos) in result.positions.enumerated() {
            subviews[idx].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                                proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, positions: [CGPoint]) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var maxX: CGFloat = 0

        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, sz.height)
            x += sz.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowH), positions)
    }
}

struct GeneticCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var model: GeneticModel

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

        let canvas = GeneticCanvas(frame: CGRect(origin: .zero, size: imgSize))
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

    func makeCoordinator() -> GeneticCoordinator { GeneticCoordinator(model: model) }
}

final class GeneticCoordinator: NSObject, UIScrollViewDelegate {
    var model: GeneticModel
    weak var canvas: GeneticCanvas?
    weak var container: UIView?

    init(model: GeneticModel) { self.model = model }

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

final class GeneticCanvas: UIView {
    weak var coordinator: GeneticCoordinator?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }

        let model = coord.model
        let cands = model.candidates

        let routeIndices: [Int]
        if let result = model.result {
            routeIndices = result.bestRoute
        } else if let step = model.liveStep {
            routeIndices = step.bestRoute
        } else {
            routeIndices = []
        }

        let startPt = CGPoint(x: model.startX, y: model.startY)

        for (i, cand) in cands.enumerated() {
            let pos = CGPoint(x: cand.x, y: cand.y)
            let isInRoute = routeIndices.contains(i)
            if !isInRoute {
                drawPlaceDot(ctx: ctx, pos: pos, place: cand.place,
                            color: .systemGray, index: nil, closing: cand.closingMinutes)
            }
        }

        if !routeIndices.isEmpty {

            ctx.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(3.0)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            ctx.move(to: startPt)
            for candIdx in routeIndices {
                guard candIdx < cands.count else { continue }
                ctx.addLine(to: CGPoint(x: cands[candIdx].x, y: cands[candIdx].y))
            }
            ctx.strokePath()

            var prevPt = startPt
            for candIdx in routeIndices {
                guard candIdx < cands.count else { continue }
                let nextPt = CGPoint(x: cands[candIdx].x, y: cands[candIdx].y)
                drawArrow(ctx: ctx, from: prevPt, to: nextPt, color: .systemGreen)
                prevPt = nextPt
            }

            for (step, candIdx) in routeIndices.enumerated() {
                guard candIdx < cands.count else { continue }
                let cand = cands[candIdx]
                let pos = CGPoint(x: cand.x, y: cand.y)
                drawPlaceDot(ctx: ctx, pos: pos, place: cand.place,
                            color: .systemGreen, index: step + 1,
                            closing: cand.closingMinutes)
            }
        }

        drawStartDot(ctx: ctx, pos: startPt)
    }

    private func drawPlaceDot(ctx: CGContext, pos: CGPoint, place: FoodPlace,
                               color: UIColor, index: Int?, closing: Double?) {
        let r: CGFloat = 14

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                      color: UIColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))

        let icon = UIImage(systemName: place.category.icon)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        if let icon = icon {
            let s: CGFloat = 14
            icon.draw(in: CGRect(x: pos.x - s / 2, y: pos.y - s / 2, width: s, height: s))
        }

        if let idx = index {
            let label = "\(idx)" as NSString
            let font = UIFont.boldSystemFont(ofSize: 9)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.systemGreen
            ]
            label.draw(at: CGPoint(x: pos.x + r - 2, y: pos.y - r - 4),
                       withAttributes: attrs)
        }

        var nameStr = place.name
        if let closing = closing, closing < 60 {
            nameStr += " (\(Int(closing))м)"
        }
        let name = nameStr as NSString
        let nameFont = UIFont.systemFont(ofSize: 7, weight: .semibold)
        let nameColor: UIColor = (closing ?? 999) < 30 ? .systemRed : .black
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont, .foregroundColor: nameColor,
            .backgroundColor: UIColor.white.withAlphaComponent(0.85)
        ]
        let nameSz = name.size(withAttributes: nameAttrs)
        name.draw(at: CGPoint(x: pos.x - nameSz.width / 2, y: pos.y + r + 2),
                  withAttributes: nameAttrs)
    }

    private func drawStartDot(ctx: CGContext, pos: CGPoint) {
        let r: CGFloat = 10
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                      color: UIColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setFillColor(UIColor.systemBlue.cgColor)
        ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))

        let icon = UIImage(systemName: "figure.stand")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        if let icon = icon {
            let s: CGFloat = 12
            icon.draw(in: CGRect(x: pos.x - s / 2, y: pos.y - s / 2, width: s, height: s))
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
        path.move(to: CGPoint(x: 7, y: 0))
        path.addLine(to: CGPoint(x: -5, y: -5))
        path.addLine(to: CGPoint(x: -5, y: 5))
        path.closeSubpath()
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.restoreGState()
    }
}

#Preview {
    GeneticView(places: loadPlaces())
}
