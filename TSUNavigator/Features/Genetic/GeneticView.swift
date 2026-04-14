import SwiftUI
import Combine

final class GeneticModel: ObservableObject {

    @Published var selectedDishes: Set<SelectedDish> = []

    @Published var result: GeneticResult?
    @Published var isRunning = false
    @Published var liveStep: GeneticStep?
    @Published var statusMessage: String = ""

    @Published var populationSize: Double = 100
    @Published var generations: Double = 300
    @Published var mutationRate: Double = 0.20

    let allPlaces: [FoodPlace]
    let mapModel: MapGridModel
    let gridCols: Int
    let gridRows: Int
    private let mapW: CGFloat = 838
    private let mapH: CGFloat = 686

    @Published var startX: Double = 419
    @Published var startY: Double = 343
    @Published var startPlaced = false

    var roadSegments: [String: [CGPoint]] = [:]

    init(places: [FoodPlace], mapModel: MapGridModel) {
        self.allPlaces = places
        self.mapModel = mapModel
        self.gridCols = mapModel.cols
        self.gridRows = mapModel.rows
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

    func pixelToCell(_ pt: CGPoint) -> Cell {
        let cellW = mapW / CGFloat(gridCols)
        let cellH = mapH / CGFloat(gridRows)
        let col = min(max(Int(pt.x / cellW), 0), gridCols - 1)
        let row = min(max(Int(pt.y / cellH), 0), gridRows - 1)
        return Cell(row: row, col: col)
    }

    func cellToPixel(_ cell: Cell) -> CGPoint {
        let cellW = mapW / CGFloat(gridCols)
        let cellH = mapH / CGFloat(gridRows)
        return CGPoint(x: CGFloat(cell.col) * cellW + cellW / 2,
                       y: CGFloat(cell.row) * cellH + cellH / 2)
    }

    func toggleDish(_ dish: SelectedDish) {
        if selectedDishes.contains(dish) {
            selectedDishes.remove(dish)
        } else {
            selectedDishes.insert(dish)
        }
        result = nil
        liveStep = nil
        roadSegments = [:]
    }

    func clear() {
        selectedDishes = []
        result = nil
        liveStep = nil
        roadSegments = [:]
        startPlaced = false
    }

    func run() {
        let cands = candidates
        guard !cands.isEmpty else { return }
        isRunning = true
        liveStep = nil
        roadSegments = [:]

        let dishNames = Set(selectedDishes.map(\.name))
        let popSize = Int(populationSize)
        let gens = Int(generations)
        let mutRate = mutationRate
        let sx = startX
        let sy = startY
        let snapshot = mapModel.snapshot(grassWalkable: true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.statusMessage = "Прокладка дорог A*..."
            }

            let (distMatrix, segments) = self.precomputeRoadPaths(
                candidates: cands, startX: sx, startY: sy, snapshot: snapshot)

            DispatchQueue.main.async {
                self.roadSegments = segments
                self.statusMessage = "Генетический алгоритм..."
            }

            let algo = GeneticAlgorithm(populationSize: popSize, mutationRate: mutRate)
            let res = algo.run(
                candidates: cands,
                selectedDishes: dishNames,
                startX: sx, startY: sy,
                generations: gens,
                externalDistMatrix: distMatrix
            ) { step in
                DispatchQueue.main.async {
                    self.liveStep = step
                }
            }
            DispatchQueue.main.async {
                self.result = res
                self.isRunning = false
                self.statusMessage = ""
            }
        }
    }

    private func precomputeRoadPaths(
        candidates: [RouteCandidate],
        startX: Double, startY: Double,
        snapshot: GridSnapshot
    ) -> ([[Double]], [String: [CGPoint]]) {

        let algo = AStarAlgorithm()
        let n = candidates.count + 1
        var dist = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var segments: [String: [CGPoint]] = [:]
        let metersPerPixel = 7.3

        let startPx = CGPoint(x: startX, y: startY)
        let startCell = pixelToCell(startPx)
        let walkableStart = findNearestWalkable(to: startCell, in: snapshot)

        var walkableCells: [Cell] = [walkableStart]
        for cand in candidates {
            let candCell = pixelToCell(CGPoint(x: cand.x, y: cand.y))
            let building = mapModel.floodFillBuilding(from: candCell)
            if !building.isEmpty {
                let edge = mapModel.nearestWalkableEdge(
                    of: building, to: walkableStart, grassWalkable: true)
                walkableCells.append(edge ?? findNearestWalkable(to: candCell, in: snapshot))
            } else {
                walkableCells.append(findNearestWalkable(to: candCell, in: snapshot))
            }
        }

        for i in 0..<n {
            for j in (i+1)..<n {
                if let path = algo.findPath(in: snapshot, from: walkableCells[i], to: walkableCells[j]) {
                    let pathLen = Double(path.count) * metersPerPixel *
                        (Double(mapW) / Double(gridCols))
                    let cellSize = mapModel.cellMeters
                    let pathMeters = Double(path.count) * cellSize
                    dist[i][j] = pathMeters
                    dist[j][i] = pathMeters

                    let step = max(1, path.count / 80)
                    var pixelPath = stride(from: 0, to: path.count, by: step).map {
                        cellToPixel(path[$0])
                    }
                    if let last = path.last {
                        let lastPx = cellToPixel(last)
                        if pixelPath.last != lastPx { pixelPath.append(lastPx) }
                    }

                    segments["\(i)-\(j)"] = pixelPath
                    segments["\(j)-\(i)"] = pixelPath.reversed()
                } else {
                    let dx = Double(walkableCells[i].col - walkableCells[j].col)
                    let dy = Double(walkableCells[i].row - walkableCells[j].row)
                    let fallback = sqrt(dx*dx + dy*dy) * mapModel.cellMeters * 2.0
                    dist[i][j] = fallback
                    dist[j][i] = fallback
                }
            }
        }

        return (dist, segments)
    }

    private func findNearestWalkable(to cell: Cell, in snapshot: GridSnapshot) -> Cell {
        if snapshot.isWalkable(row: cell.row, col: cell.col) { return cell }
        for radius in 1...30 {
            for dr in -radius...radius {
                for dc in -radius...radius {
                    guard abs(dr) == radius || abs(dc) == radius else { continue }
                    let r = cell.row + dr, c = cell.col + dc
                    if snapshot.isWalkable(row: r, col: c) {
                        return Cell(row: r, col: c)
                    }
                }
            }
        }
        return cell
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
    case pickStart
    case results
}

struct GeneticView: View {
    let places: [FoodPlace]
    let mapModel: MapGridModel

    @StateObject private var model: GeneticModel
    @State private var viewStep: ViewStep = .selectDishes

    init(places: [FoodPlace], mapModel: MapGridModel) {
        self.places = places
        self.mapModel = mapModel
        _model = StateObject(wrappedValue: GeneticModel(
            places: places, mapModel: mapModel))
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

                    case .pickStart:
                        pickStartView

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
                if viewStep == .pickStart {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Назад") { viewStep = .selectDishes }
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
                    viewStep = .pickStart
                } label: {
                    Text("Выбрать стартовую точку")
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

    private var pickStartView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: model.startPlaced ? "checkmark.circle.fill" : "mappin.circle")
                    .foregroundColor(model.startPlaced ? .green : .blue)
                Text(model.startPlaced ? "Старт выбран — нажмите «Построить маршрут»" : "Нажмите на карту, чтобы указать, где вы находитесь")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            StartPickerCanvasRepresentable(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                viewStep = .results
                model.run()
            } label: {
                Text("Построить маршрут")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(model.startPlaced ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!model.startPlaced)
            .padding(12)
        }
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
                    Text(model.statusMessage.isEmpty ? "Запуск..." : model.statusMessage)
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

struct StartPickerCanvasRepresentable: UIViewRepresentable {
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

        let overlay = StartPickerOverlay(frame: CGRect(origin: .zero, size: imgSize))
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = true
        overlay.coordinator = context.coordinator
        context.coordinator.overlay = overlay
        container.addSubview(overlay)

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
        context.coordinator.overlay?.setNeedsDisplay()
    }

    func makeCoordinator() -> StartPickerCoordinator { StartPickerCoordinator(model: model) }
}

final class StartPickerCoordinator: NSObject, UIScrollViewDelegate {
    var model: GeneticModel
    weak var overlay: StartPickerOverlay?
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

    func handleTap(at point: CGPoint) {
        model.startX = Double(point.x)
        model.startY = Double(point.y)
        model.startPlaced = true
        overlay?.setNeedsDisplay()
    }
}

final class StartPickerOverlay: UIView {
    weak var coordinator: StartPickerCoordinator?

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pt = touch.location(in: self)
        coordinator?.handleTap(at: pt)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }
        let model = coord.model

        let cands = model.candidates
        let mapW: CGFloat = 838
        let cellW = mapW / CGFloat(model.gridCols)
        let cellH: CGFloat = 686 / CGFloat(model.gridRows)

        for cand in cands {
            let pos = CGPoint(x: cand.x, y: cand.y)
            ctx.setFillColor(UIColor.systemOrange.withAlphaComponent(0.7).cgColor)
            ctx.fillEllipse(in: CGRect(x: pos.x - 8, y: pos.y - 8, width: 16, height: 16))
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: pos.x - 8, y: pos.y - 8, width: 16, height: 16))

            let name = cand.place.name as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7, weight: .semibold),
                .foregroundColor: UIColor.black,
                .backgroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let sz = name.size(withAttributes: attrs)
            name.draw(at: CGPoint(x: pos.x - sz.width / 2, y: pos.y + 10), withAttributes: attrs)
        }

        guard model.startPlaced else { return }
        let startPt = CGPoint(x: model.startX, y: model.startY)
        let r: CGFloat = 14

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4,
                      color: UIColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setFillColor(UIColor.systemBlue.cgColor)
        ctx.fillEllipse(in: CGRect(x: startPt.x - r, y: startPt.y - r, width: 2*r, height: 2*r))
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: startPt.x - r, y: startPt.y - r, width: 2*r, height: 2*r))

        let icon = UIImage(systemName: "figure.stand")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        if let icon = icon {
            let s: CGFloat = 16
            icon.draw(in: CGRect(x: startPt.x - s/2, y: startPt.y - s/2, width: s, height: s))
        }

        let label = "Вы здесь" as NSString
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 9),
            .foregroundColor: UIColor.systemBlue,
            .backgroundColor: UIColor.white.withAlphaComponent(0.9)
        ]
        let labelSz = label.size(withAttributes: labelAttrs)
        label.draw(at: CGPoint(x: startPt.x - labelSz.width / 2, y: startPt.y + r + 3),
                   withAttributes: labelAttrs)
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
        let segments = model.roadSegments

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

            var prevIdx = 0
            for candIdx in routeIndices {
                guard candIdx < cands.count else { continue }
                let toIdx = candIdx + 1
                let key = "\(prevIdx)-\(toIdx)"

                if let path = segments[key], path.count >= 2 {
                    ctx.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.5).cgColor)
                    ctx.setLineWidth(4.0)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.move(to: path[0])
                    for pt in path.dropFirst() { ctx.addLine(to: pt) }
                    ctx.strokePath()

                    ctx.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.9).cgColor)
                    ctx.setLineWidth(2.5)
                    ctx.move(to: path[0])
                    for pt in path.dropFirst() { ctx.addLine(to: pt) }
                    ctx.strokePath()

                    let mid = path[path.count / 2]
                    let prev = path[max(0, path.count / 2 - 3)]
                    drawArrow(ctx: ctx, from: prev, to: mid, color: .systemGreen)
                } else {
                    let fromPt = prevIdx == 0 ? startPt : CGPoint(x: cands[prevIdx - 1].x, y: cands[prevIdx - 1].y)
                    let toPt = CGPoint(x: cands[candIdx].x, y: cands[candIdx].y)
                    ctx.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.9).cgColor)
                    ctx.setLineWidth(2.5)
                    ctx.setLineDash(phase: 0, lengths: [6, 4])
                    ctx.move(to: fromPt)
                    ctx.addLine(to: toPt)
                    ctx.strokePath()
                    ctx.setLineDash(phase: 0, lengths: [])
                    drawArrow(ctx: ctx, from: fromPt, to: toPt, color: .systemGreen)
                }

                prevIdx = toIdx
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
    GeneticView(places: loadPlaces(), mapModel: loadGridModel(filename: "campus-grid"))
}
