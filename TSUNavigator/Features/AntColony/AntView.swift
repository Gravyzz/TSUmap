import SwiftUI
import Combine



private let coworkingMeta: [String: (capacity: Int, comfort: Double)] = [
    "coworking_main":    (30, 0.70),
    "coworking_library": (50, 0.90),
    "studyroom_2nd":     (20, 0.60),
    "coworking_mkc":     (40, 0.80),
    "coworking_iem":     (25, 0.75),
    "library_main":      (60, 0.85)
]



private let mapW: CGFloat = 838
private let mapH: CGFloat = 686

private func pixelPosition(for place: FoodPlace,
                            gridCols: Int, gridRows: Int) -> CGPoint? {
    guard let ref = place.campusBuildingCell else { return nil }
    let cellW = mapW / CGFloat(gridCols)
    let cellH = mapH / CGFloat(gridRows)
    return CGPoint(x: CGFloat(ref.col) * cellW + cellW / 2,
                   y: CGFloat(ref.row) * cellH + cellH / 2)
}

private func pixelToCell(_ pt: CGPoint, gridCols: Int, gridRows: Int) -> Cell {
    let cellW = mapW / CGFloat(gridCols)
    let cellH = mapH / CGFloat(gridRows)
    let col = min(max(Int(pt.x / cellW), 0), gridCols - 1)
    let row = min(max(Int(pt.y / cellH), 0), gridRows - 1)
    return Cell(row: row, col: col)
}

private func cellToPixel(_ cell: Cell, gridCols: Int, gridRows: Int) -> CGPoint {
    let cellW = mapW / CGFloat(gridCols)
    let cellH = mapH / CGFloat(gridRows)
    return CGPoint(x: CGFloat(cell.col) * cellW + cellW / 2,
                   y: CGFloat(cell.row) * cellH + cellH / 2)
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

final class AntTSPModel: ObservableObject {
    @Published var selectedPlaces: [FoodPlace] = []
    @Published var result: AntResult?
    @Published var liveStep: AntStep?
    @Published var isRunning = false
    @Published var statusMessage: String = ""

    @Published var startX: Double = 419
    @Published var startY: Double = 343
    @Published var startPlaced = false

    @Published var antCount: Double = 30
    @Published var iterations: Double = 100

    let landmarks: [FoodPlace]
    let mapModel: MapGridModel
    let gridCols: Int
    let gridRows: Int

    var roadSegments: [String: [CGPoint]] = [:]
    var totalDistanceMeters: Double = 0

    init(places: [FoodPlace], mapModel: MapGridModel) {
        self.landmarks = places.filter {
            $0.category.section == .landmark && $0.campusBuildingCell != nil
        }
        self.mapModel = mapModel
        self.gridCols = mapModel.cols
        self.gridRows = mapModel.rows
    }

    func position(for place: FoodPlace) -> CGPoint? {
        pixelPosition(for: place, gridCols: gridCols, gridRows: gridRows)
    }

    func toggle(_ place: FoodPlace) {
        if let idx = selectedPlaces.firstIndex(where: { $0.id == place.id }) {
            selectedPlaces.remove(at: idx)
        } else {
            selectedPlaces.append(place)
        }
        result = nil
        liveStep = nil
        roadSegments = [:]
    }

    func isSelected(_ place: FoodPlace) -> Bool {
        selectedPlaces.contains(where: { $0.id == place.id })
    }

    func clear() {
        selectedPlaces = []
        result = nil
        liveStep = nil
        roadSegments = [:]
        startPlaced = false
    }

    func run() {
        guard !selectedPlaces.isEmpty, startPlaced else { return }

        isRunning = true
        result = nil
        liveStep = nil
        roadSegments = [:]
        statusMessage = "Прокладка дорог A*..."

        let placesSnap = selectedPlaces
        let ants = Int(antCount)
        let iters = Int(iterations)
        let sx = startX
        let sy = startY
        let snapshot = mapModel.snapshot(grassWalkable: true)
        let cols = gridCols
        let rows = gridRows
        let cellMeters = mapModel.cellMeters

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let (distMatrix, segments) = Self.precomputeRoadPaths(
                places: placesSnap, startX: sx, startY: sy,
                snapshot: snapshot, mapModel: self.mapModel,
                gridCols: cols, gridRows: rows,
                cellMeters: cellMeters)

            DispatchQueue.main.async {
                self.roadSegments = segments
                self.statusMessage = "Муравьиный алгоритм..."
            }

            let algo = AntColonyAlgorithm(antCount: ants, alpha: 1.0, beta: 4.0,
                                          evaporation: 0.5, q: 100.0)
            let res = algo.runOpenTSP(distMatrix: distMatrix, iterations: iters) { step in
                DispatchQueue.main.async {
                    self.liveStep = step
                }
            }

            DispatchQueue.main.async {
                self.result = res
                self.totalDistanceMeters = res.bestDistance
                self.isRunning = false
                self.statusMessage = ""
            }
        }
    }

    static func precomputeRoadPaths(
        places: [FoodPlace],
        startX: Double, startY: Double,
        snapshot: GridSnapshot,
        mapModel: MapGridModel,
        gridCols: Int, gridRows: Int,
        cellMeters: Double
    ) -> ([[Double]], [String: [CGPoint]]) {

        let astar = AStarAlgorithm()
        let n = places.count + 1
        var dist = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var segments: [String: [CGPoint]] = [:]

        let startCell = pixelToCell(CGPoint(x: startX, y: startY),
                                     gridCols: gridCols, gridRows: gridRows)
        let walkableStart = findNearestWalkable(to: startCell, in: snapshot)

        var walkableCells: [Cell] = [walkableStart]
        for place in places {
            guard let pos = pixelPosition(for: place,
                                          gridCols: gridCols, gridRows: gridRows) else {
                walkableCells.append(walkableStart)
                continue
            }
            let candCell = pixelToCell(pos, gridCols: gridCols, gridRows: gridRows)
            let building = mapModel.floodFillBuilding(from: candCell)
            if !building.isEmpty {
                let edge = mapModel.nearestWalkableEdge(of: building,
                                                         to: walkableStart,
                                                         grassWalkable: true)
                walkableCells.append(edge ?? findNearestWalkable(to: candCell, in: snapshot))
            } else {
                walkableCells.append(findNearestWalkable(to: candCell, in: snapshot))
            }
        }

        for i in 0..<n {
            for j in (i + 1)..<n {
                if let path = astar.findPath(in: snapshot,
                                             from: walkableCells[i],
                                             to: walkableCells[j]) {
                    let pathMeters = Double(path.count) * cellMeters
                    dist[i][j] = pathMeters
                    dist[j][i] = pathMeters

                    let step = max(1, path.count / 80)
                    var pixelPath = stride(from: 0, to: path.count, by: step).map {
                        cellToPixel(path[$0], gridCols: gridCols, gridRows: gridRows)
                    }
                    if let last = path.last {
                        let lastPx = cellToPixel(last, gridCols: gridCols, gridRows: gridRows)
                        if pixelPath.last != lastPx { pixelPath.append(lastPx) }
                    }
                    segments["\(i)-\(j)"] = pixelPath
                    segments["\(j)-\(i)"] = pixelPath.reversed()
                } else {
                    let dx = Double(walkableCells[i].col - walkableCells[j].col)
                    let dy = Double(walkableCells[i].row - walkableCells[j].row)
                    let fallback = sqrt(dx * dx + dy * dy) * cellMeters * 2.0
                    dist[i][j] = fallback
                    dist[j][i] = fallback
                }
            }
        }
        return (dist, segments)
    }
}


final class AntCoworkingModel: ObservableObject {
    @Published var startX: Double = 419
    @Published var startY: Double = 343
    @Published var startPlaced = false

    @Published var studentCount: Int = 30
    @Published var result: CoworkingResult? = nil
    @Published var isRunning = false
    @Published var statusMessage: String = ""

    @Published var antCount: Double = 40
    @Published var iterations: Double = 80

    let spots: [CoworkingSpot]
    let coworkingPlaces: [FoodPlace]
    let mapModel: MapGridModel
    let gridCols: Int
    let gridRows: Int

    var roadSegments: [Int: [CGPoint]] = [:]

    init(places: [FoodPlace], mapModel: MapGridModel) {
        self.mapModel = mapModel
        self.gridCols = mapModel.cols
        self.gridRows = mapModel.rows

        let coworkings = places.filter {
            $0.category.section == .coworking && $0.campusBuildingCell != nil
        }
        self.coworkingPlaces = coworkings
        self.spots = coworkings.enumerated().compactMap { (i, place) -> CoworkingSpot? in
            guard let pos = pixelPosition(for: place,
                                          gridCols: mapModel.cols,
                                          gridRows: mapModel.rows) else { return nil }
            let meta = coworkingMeta[place.id] ?? (30, 0.70)
            return CoworkingSpot(id: i, name: place.name, position: pos,
                                 capacity: meta.capacity, comfort: meta.comfort)
        }
    }

    func clear() {
        startPlaced = false
        result = nil
        roadSegments = [:]
    }

    func run() {
        guard startPlaced, !spots.isEmpty else { return }
        isRunning = true
        result = nil
        roadSegments = [:]
        statusMessage = "Прокладка дорог A*..."

        let spotsSnap = spots
        let count = studentCount
        let ants = Int(antCount)
        let iters = Int(iterations)
        let sx = startX
        let sy = startY
        let snapshot = mapModel.snapshot(grassWalkable: true)
        let cols = gridCols
        let rows = gridRows
        let cellMeters = mapModel.cellMeters

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let (distances, segments) = Self.precomputeRoadDistances(
                spots: spotsSnap, startX: sx, startY: sy,
                snapshot: snapshot, mapModel: self.mapModel,
                gridCols: cols, gridRows: rows,
                cellMeters: cellMeters)

            DispatchQueue.main.async {
                self.roadSegments = segments
                self.statusMessage = "Муравьиный алгоритм..."
            }

            let algo = AntColonyAlgorithm(antCount: ants, alpha: 1.0, beta: 3.0,
                                          evaporation: 0.4, q: 100.0)
            let res = algo.runCoworking(distances: distances,
                                        spots: spotsSnap,
                                        studentCount: count,
                                        iterations: iters)

            DispatchQueue.main.async {
                self.result = res
                self.isRunning = false
                self.statusMessage = ""
            }
        }
    }

    static func precomputeRoadDistances(
        spots: [CoworkingSpot],
        startX: Double, startY: Double,
        snapshot: GridSnapshot,
        mapModel: MapGridModel,
        gridCols: Int, gridRows: Int,
        cellMeters: Double
    ) -> ([Double], [Int: [CGPoint]]) {

        let astar = AStarAlgorithm()
        let startCell = pixelToCell(CGPoint(x: startX, y: startY),
                                     gridCols: gridCols, gridRows: gridRows)
        let walkableStart = findNearestWalkable(to: startCell, in: snapshot)

        var distances = Array(repeating: 0.0, count: spots.count)
        var segments: [Int: [CGPoint]] = [:]

        for (j, spot) in spots.enumerated() {
            let cell = pixelToCell(spot.position, gridCols: gridCols, gridRows: gridRows)
            let building = mapModel.floodFillBuilding(from: cell)
            let target: Cell
            if !building.isEmpty {
                target = mapModel.nearestWalkableEdge(of: building,
                                                       to: walkableStart,
                                                       grassWalkable: true)
                    ?? findNearestWalkable(to: cell, in: snapshot)
            } else {
                target = findNearestWalkable(to: cell, in: snapshot)
            }

            if let path = astar.findPath(in: snapshot,
                                         from: walkableStart, to: target) {
                distances[j] = Double(path.count) * cellMeters

                let step = max(1, path.count / 80)
                var pixelPath = stride(from: 0, to: path.count, by: step).map {
                    cellToPixel(path[$0], gridCols: gridCols, gridRows: gridRows)
                }
                if let last = path.last {
                    let lastPx = cellToPixel(last, gridCols: gridCols, gridRows: gridRows)
                    if pixelPath.last != lastPx { pixelPath.append(lastPx) }
                }
                segments[j] = pixelPath
            } else {
                let dx = Double(walkableStart.col - target.col)
                let dy = Double(walkableStart.row - target.row)
                distances[j] = sqrt(dx * dx + dy * dy) * cellMeters * 2.0
            }
        }
        return (distances, segments)
    }
}

private enum AntStepView {
    case selectLandmarks
    case pickStart
    case results
}

struct AntView: View {
    let places: [FoodPlace]
    let mapModel: MapGridModel

    @State private var mode: AntMode = .walk
    @StateObject private var tspModel: AntTSPModel
    @StateObject private var cwModel: AntCoworkingModel

    @State private var walkStep: AntStepView = .selectLandmarks
    @State private var coworkingStep: AntStepView = .pickStart

    enum AntMode { case walk, coworking }

    init(places: [FoodPlace], mapModel: MapGridModel) {
        self.places = places
        self.mapModel = mapModel
        _tspModel = StateObject(wrappedValue: AntTSPModel(places: places, mapModel: mapModel))
        _cwModel = StateObject(wrappedValue: AntCoworkingModel(places: places, mapModel: mapModel))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Режим", selection: $mode) {
                    Text("Прогулка").tag(AntMode.walk)
                    Text("Коворкинг").tag(AntMode.coworking)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onChange(of: mode) { _, newValue in
                    if newValue == .walk {
                        walkStep = tspModel.selectedPlaces.isEmpty ? .selectLandmarks
                                : (tspModel.startPlaced ? .results : .pickStart)
                    } else {
                        coworkingStep = cwModel.startPlaced ? .results : .pickStart
                    }
                }

                if mode == .walk {
                    walkContent
                } else {
                    coworkingContent
                }
            }
            .navigationTitle(mode == .walk ? "Прогулка" : "Коворкинг")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if mode == .walk && walkStep != .selectLandmarks {
                        Button("Назад") {
                            switch walkStep {
                            case .pickStart: walkStep = .selectLandmarks
                            case .results: walkStep = .pickStart
                            default: break
                            }
                            tspModel.result = nil
                            tspModel.liveStep = nil
                        }
                        .font(.caption)
                    } else if mode == .coworking && coworkingStep == .results {
                        Button("Назад") {
                            coworkingStep = .pickStart
                            cwModel.result = nil
                        }
                        .font(.caption)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сбросить") {
                        if mode == .walk {
                            tspModel.clear()
                            walkStep = .selectLandmarks
                        } else {
                            cwModel.clear()
                            coworkingStep = .pickStart
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }


    @ViewBuilder
    private var walkContent: some View {
        if tspModel.landmarks.isEmpty {
            emptyView(icon: "building.columns",
                      title: "Нет достопримечательностей",
                      hint: "Достопримечательности должны быть привязаны к корпусу на карте.")
        } else {
            switch walkStep {
            case .selectLandmarks:
                walkSelectionView
            case .pickStart:
                walkPickStartView
            case .results:
                walkResultsView
            }
        }
    }

    private var walkSelectionView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Маршрут по университетской роще")
                    .font(.title3.bold())
                Text("Выберите достопримечательности для обхода")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(tspModel.landmarks) { place in
                        landmarkRow(place)
                    }
                }
                .padding(12)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("\(tspModel.selectedPlaces.count) выбрано")
                        .font(.caption.bold())
                    Spacer()
                    if !tspModel.selectedPlaces.isEmpty {
                        Button("Очистить") {
                            tspModel.selectedPlaces = []
                            tspModel.result = nil
                        }
                        .font(.caption2)
                        .foregroundColor(.purple)
                    }
                }

                Button {
                    walkStep = .pickStart
                } label: {
                    Text("Указать стартовую точку")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(tspModel.selectedPlaces.isEmpty ? Color.gray : Color.purple)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(tspModel.selectedPlaces.isEmpty)

                if tspModel.selectedPlaces.isEmpty {
                    Text("Выберите хотя бы одну достопримечательность")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
        }
    }

    private func landmarkRow(_ place: FoodPlace) -> some View {
        let selected = tspModel.isSelected(place)
        return Button { tspModel.toggle(place) } label: {
            HStack(spacing: 10) {
                Image(systemName: place.category.icon)
                    .font(.body)
                    .foregroundColor(selected ? .white : .purple)
                    .frame(width: 32, height: 32)
                    .background(selected ? Color.purple : Color.purple.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.body.bold()).foregroundColor(.primary)
                    Text(place.category.label).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.purple)
                }
            }
            .padding(10)
            .background(selected ? Color.purple.opacity(0.08) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.purple : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var walkPickStartView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: tspModel.startPlaced ? "checkmark.circle.fill" : "mappin.circle")
                    .foregroundColor(tspModel.startPlaced ? .green : .purple)
                Text(tspModel.startPlaced
                     ? "Старт выбран — нажмите «Построить маршрут»"
                     : "Нажмите на карту, чтобы указать, где вы находитесь")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            AntStartPickerCanvas(model: tspModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(spacing: 8) {
                    DisclosureGroup("Параметры муравьиного алгоритма") {
                        VStack(spacing: 4) {
                            paramSlider("Муравьи",
                                        value: Binding(
                                            get: { tspModel.antCount },
                                            set: { tspModel.antCount = $0 }),
                                        range: 10...100, step: 5)
                            paramSlider("Итерации",
                                        value: Binding(
                                            get: { tspModel.iterations },
                                            set: { tspModel.iterations = $0 }),
                                        range: 20...300, step: 10)
                        }
                    }
                    .font(.caption2).foregroundColor(.secondary)

                    Button {
                        walkStep = .results
                        tspModel.run()
                    } label: {
                        Text("Построить маршрут")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(tspModel.startPlaced ? Color.purple : Color.gray)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!tspModel.startPlaced)
                }
                .padding(12)
            }
            .frame(maxHeight: 200)
            .background(Color(.systemBackground))
        }
    }

    private var walkResultsView: some View {
        VStack(spacing: 0) {
            walkStatusBar
                .padding(.horizontal, 12).padding(.vertical, 6)

            AntTSPCanvas(model: tspModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let r = tspModel.result {
                walkRouteSummary(r)
                    .padding(12)
            } else if tspModel.isRunning {
                walkLiveSummary
                    .padding(12)
            }
        }
    }

    private var walkStatusBar: some View {
        HStack(spacing: 6) {
            if tspModel.isRunning {
                ProgressView().controlSize(.small)
                if let step = tspModel.liveStep {
                    Text("Поколение \(step.iteration) · лучший \(Int(step.bestDistance)) м")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text(tspModel.statusMessage.isEmpty ? "Запуск..." : tspModel.statusMessage)
                        .font(.caption).foregroundColor(.secondary)
                }
            } else if tspModel.result != nil {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.purple)
                Text("Маршрут найден").font(.caption.bold())
            }
            Spacer()
        }
    }

    private var walkLiveSummary: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(tspModel.liveStep?.iteration ?? 0),
                         total: tspModel.iterations)
                .tint(.purple)
            HStack {
                Text("Итерация \(tspModel.liveStep?.iteration ?? 0)/\(Int(tspModel.iterations))")
                Spacer()
                if let d = tspModel.liveStep?.bestDistance, d.isFinite {
                    Text("\(Int(d)) м")
                }
            }
            .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func walkRouteSummary(_ r: AntResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                statItem("Длина", value: "\(Int(r.bestDistance)) м",
                         icon: "ruler", color: .purple)
                statItem("Точек", value: "\(tspModel.selectedPlaces.count)",
                         icon: "mappin", color: .blue)
                let minutes = r.bestDistance / (5000.0 / 60.0)
                statItem("Время", value: "≈\(Int(minutes)) мин",
                         icon: "clock", color: .green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Порядок обхода:")
                    .font(.caption2.bold()).foregroundColor(.secondary)
                ForEach(Array(r.bestRoute.enumerated()), id: \.offset) { i, idx in
                    let placeIdx = idx - 1
                    if placeIdx >= 0, placeIdx < tspModel.selectedPlaces.count {
                        let place = tspModel.selectedPlaces[placeIdx]
                        HStack(spacing: 6) {
                            Text("\(i + 1).")
                                .font(.caption2.bold()).foregroundColor(.purple)
                                .frame(width: 18)
                            Image(systemName: place.category.icon)
                                .font(.caption2).foregroundColor(.purple)
                            Text(place.name).font(.caption2.bold())
                            Spacer()
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }


    @ViewBuilder
    private var coworkingContent: some View {
        if cwModel.spots.isEmpty {
            emptyView(icon: "laptopcomputer",
                      title: "Нет коворкингов",
                      hint: "Коворкинги должны быть привязаны к корпусам на карте.")
        } else {
            switch coworkingStep {
            case .pickStart, .selectLandmarks:
                coworkingPickStartView
            case .results:
                coworkingResultsView
            }
        }
    }

    private var coworkingPickStartView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: cwModel.startPlaced ? "checkmark.circle.fill" : "mappin.circle")
                    .foregroundColor(cwModel.startPlaced ? .green : .teal)
                Text(cwModel.startPlaced
                     ? "Точка студентов выбрана"
                     : "Нажмите на карту — где сейчас находится группа")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            CoworkingStartPickerCanvas(model: cwModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(.teal)
                        Text("Студентов: \(cwModel.studentCount)")
                            .font(.body.bold())
                        Spacer()
                        Stepper("", value: $cwModel.studentCount, in: 1...500, step: 1)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 4)

                    let totalCap = cwModel.spots.reduce(0) { $0 + $1.capacity }
                    HStack {
                        Image(systemName: "chair.lounge")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Всего мест: \(totalCap)")
                            .font(.caption2).foregroundColor(.secondary)
                        if cwModel.studentCount > totalCap {
                            Spacer()
                            Text("Не хватает \(cwModel.studentCount - totalCap) мест")
                                .font(.caption2).foregroundColor(.orange)
                        }
                    }

                    DisclosureGroup("Параметры муравьиного алгоритма") {
                        VStack(spacing: 4) {
                            paramSlider("Муравьи",
                                        value: Binding(
                                            get: { cwModel.antCount },
                                            set: { cwModel.antCount = $0 }),
                                        range: 10...100, step: 5)
                            paramSlider("Итерации",
                                        value: Binding(
                                            get: { cwModel.iterations },
                                            set: { cwModel.iterations = $0 }),
                                        range: 20...200, step: 10)
                        }
                    }
                    .font(.caption2).foregroundColor(.secondary)

                    Button {
                        coworkingStep = .results
                        cwModel.run()
                    } label: {
                        Text("Распределить студентов")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(cwModel.startPlaced ? Color.teal : Color.gray)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!cwModel.startPlaced)
                }
                .padding(12)
            }
            .frame(maxHeight: 280)
            .background(Color(.systemBackground))
        }
    }

    private var coworkingResultsView: some View {
        VStack(spacing: 0) {
            coworkingStatusBar
                .padding(.horizontal, 12).padding(.vertical, 6)

            CoworkingCanvas(model: cwModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let r = cwModel.result {
                coworkingAllocationSummary(r)
                    .padding(12)
            }
        }
    }

    private var coworkingStatusBar: some View {
        HStack(spacing: 6) {
            if cwModel.isRunning {
                ProgressView().controlSize(.small)
                Text(cwModel.statusMessage.isEmpty ? "Запуск..." : cwModel.statusMessage)
                    .font(.caption).foregroundColor(.secondary)
            } else if cwModel.result != nil {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.teal)
                Text("Распределение готово").font(.caption.bold())
            }
            Spacer()
        }
    }

    private func coworkingAllocationSummary(_ r: CoworkingResult) -> some View {
        let placed = r.allocations.reduce(0, +) - r.overflow
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                statItem("Размещено", value: "\(placed)",
                         icon: "person.3.fill", color: .teal)
                if r.overflow > 0 {
                    statItem("Переполнение", value: "+\(r.overflow)",
                             icon: "exclamationmark.triangle.fill", color: .orange)
                }
                let used = r.allocations.enumerated().filter { $0.element > 0 }.count
                statItem("Точек", value: "\(used)",
                         icon: "checkmark.seal", color: .green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Распределение:")
                    .font(.caption2.bold()).foregroundColor(.secondary)
                ForEach(Array(zip(cwModel.spots, r.allocations)), id: \.0.id) { spot, count in
                    let dist = Int(r.distances[spot.id])
                    let isOver = count > spot.capacity
                    HStack(spacing: 6) {
                        Image(systemName: count > 0 ? "laptopcomputer.fill" : "laptopcomputer")
                            .font(.caption2).foregroundColor(count > 0 ? .teal : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(spot.name).font(.caption2.bold()).lineLimit(1)
                            Text("\(dist) м · комфорт \(Int(spot.comfort * 100))%")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(count)/\(spot.capacity)")
                            .font(.caption2.bold())
                            .foregroundColor(isOver ? .orange : (count > 0 ? .teal : .secondary))
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }


    private func emptyView(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 50)).foregroundColor(.secondary)
            Text(title).font(.title3.bold())
            Text(hint).font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statItem(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundColor(color)
            Text(value).font(.caption.bold())
            Text(label).font(.caption2).foregroundColor(.secondary)
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


struct AntStartPickerCanvas: UIViewRepresentable {
    @ObservedObject var model: AntTSPModel
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

        let imageView = UIImageView(image: UIImage(named: "mapEatTSU") ?? UIImage())
        imageView.frame = CGRect(origin: .zero, size: imgSize)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        container.addSubview(imageView)

        let overlay = AntStartOverlay(frame: CGRect(origin: .zero, size: imgSize))
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

    func makeCoordinator() -> AntStartCoordinator { AntStartCoordinator(model: model) }
}

final class AntStartCoordinator: NSObject, UIScrollViewDelegate {
    var model: AntTSPModel
    weak var overlay: AntStartOverlay?
    weak var container: UIView?

    init(model: AntTSPModel) { self.model = model }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent(in: scrollView) }

    func centerContent(in scrollView: UIScrollView) {
        guard let c = container else { return }
        let offsetX = max((scrollView.bounds.width - c.frame.width) / 2, 0)
        let offsetY = max((scrollView.bounds.height - c.frame.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX,
                                                bottom: offsetY, right: offsetX)
    }

    func handleTap(at pt: CGPoint) {
        model.startX = Double(pt.x)
        model.startY = Double(pt.y)
        model.startPlaced = true
        overlay?.setNeedsDisplay()
    }
}

final class AntStartOverlay: UIView {
    weak var coordinator: AntStartCoordinator?

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        coordinator?.handleTap(at: touch.location(in: self))
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }
        let model = coord.model

        for place in model.selectedPlaces {
            guard let pos = model.position(for: place) else { continue }
            ctx.setFillColor(UIColor.systemPurple.withAlphaComponent(0.7).cgColor)
            ctx.fillEllipse(in: CGRect(x: pos.x - 8, y: pos.y - 8, width: 16, height: 16))
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: pos.x - 8, y: pos.y - 8, width: 16, height: 16))

            let name = place.name as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7, weight: .semibold),
                .foregroundColor: UIColor.black,
                .backgroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let sz = name.size(withAttributes: attrs)
            name.draw(at: CGPoint(x: pos.x - sz.width / 2, y: pos.y + 10), withAttributes: attrs)
        }

        guard model.startPlaced else { return }
        drawStartMarker(ctx: ctx, x: model.startX, y: model.startY)
    }
}


struct AntTSPCanvas: UIViewRepresentable {
    @ObservedObject var model: AntTSPModel
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

        let imageView = UIImageView(image: UIImage(named: "mapEatTSU") ?? UIImage())
        imageView.frame = CGRect(origin: .zero, size: imgSize)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        container.addSubview(imageView)

        let canvas = AntTSPCanvasView(frame: CGRect(origin: .zero, size: imgSize))
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

    func makeCoordinator() -> AntTSPCoordinator { AntTSPCoordinator(model: model) }
}

final class AntTSPCoordinator: NSObject, UIScrollViewDelegate {
    var model: AntTSPModel
    weak var canvas: AntTSPCanvasView?
    weak var container: UIView?

    init(model: AntTSPModel) { self.model = model }

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

final class AntTSPCanvasView: UIView {
    weak var coordinator: AntTSPCoordinator?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }
        let model = coord.model
        let places = model.selectedPlaces

        let route: [Int]
        if let r = model.result { route = r.bestRoute }
        else if let s = model.liveStep { route = s.bestRoute }
        else { route = [] }

        let segments = model.roadSegments

        if let pher = model.result?.pheromoneMatrix, !pher.isEmpty {
            let maxPher = pher.flatMap { $0 }.max() ?? 1.0
            for i in 0..<pher.count {
                for j in (i + 1)..<pher.count {
                    let intensity = CGFloat(pher[i][j] / maxPher)
                    guard intensity > 0.1 else { continue }
                    if let path = segments["\(i)-\(j)"], path.count >= 2 {
                        ctx.setStrokeColor(UIColor.systemPurple
                            .withAlphaComponent(intensity * 0.18).cgColor)
                        ctx.setLineWidth(max(intensity * 2.5, 0.5))
                        ctx.move(to: path[0])
                        for pt in path.dropFirst() { ctx.addLine(to: pt) }
                        ctx.strokePath()
                    }
                }
            }
        }

        if !route.isEmpty {
            var prevIdx = 0
            for nodeIdx in route {
                let key = "\(prevIdx)-\(nodeIdx)"
                if let path = segments[key], path.count >= 2 {
                    ctx.setStrokeColor(UIColor.systemPurple.withAlphaComponent(0.5).cgColor)
                    ctx.setLineWidth(5.0)
                    ctx.setLineCap(.round); ctx.setLineJoin(.round)
                    ctx.move(to: path[0])
                    for pt in path.dropFirst() { ctx.addLine(to: pt) }
                    ctx.strokePath()

                    ctx.setStrokeColor(UIColor.systemPurple.withAlphaComponent(0.95).cgColor)
                    ctx.setLineWidth(2.5)
                    ctx.move(to: path[0])
                    for pt in path.dropFirst() { ctx.addLine(to: pt) }
                    ctx.strokePath()

                    let mid = path[path.count / 2]
                    let prev = path[max(0, path.count / 2 - 3)]
                    drawArrow(ctx: ctx, from: prev, to: mid, color: .systemPurple)
                } else {
                    let from: CGPoint = prevIdx == 0
                        ? CGPoint(x: model.startX, y: model.startY)
                        : (model.position(for: places[prevIdx - 1]) ?? .zero)
                    let to = model.position(for: places[nodeIdx - 1]) ?? .zero
                    ctx.setStrokeColor(UIColor.systemPurple.withAlphaComponent(0.85).cgColor)
                    ctx.setLineWidth(2.0)
                    ctx.setLineDash(phase: 0, lengths: [6, 4])
                    ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
                    ctx.setLineDash(phase: 0, lengths: [])
                }
                prevIdx = nodeIdx
            }
        }

        for (i, place) in places.enumerated() {
            guard let pos = model.position(for: place) else { continue }
            let inRoute = route.firstIndex(of: i + 1)
            let color: UIColor = inRoute != nil ? .systemPurple : .systemGray
            drawPlaceDot(ctx: ctx, pos: pos, place: place, color: color,
                         index: inRoute.map { $0 + 1 })
        }


        drawStartMarker(ctx: ctx, x: model.startX, y: model.startY)
    }
}



struct CoworkingStartPickerCanvas: UIViewRepresentable {
    @ObservedObject var model: AntCoworkingModel
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

        let imageView = UIImageView(image: UIImage(named: "mapEatTSU") ?? UIImage())
        imageView.frame = CGRect(origin: .zero, size: imgSize)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        container.addSubview(imageView)

        let overlay = CoworkingStartOverlay(frame: CGRect(origin: .zero, size: imgSize))
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

    func makeCoordinator() -> CoworkingStartCoordinator { CoworkingStartCoordinator(model: model) }
}

final class CoworkingStartCoordinator: NSObject, UIScrollViewDelegate {
    var model: AntCoworkingModel
    weak var overlay: CoworkingStartOverlay?
    weak var container: UIView?

    init(model: AntCoworkingModel) { self.model = model }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent(in: scrollView) }

    func centerContent(in scrollView: UIScrollView) {
        guard let c = container else { return }
        let offsetX = max((scrollView.bounds.width - c.frame.width) / 2, 0)
        let offsetY = max((scrollView.bounds.height - c.frame.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX,
                                                bottom: offsetY, right: offsetX)
    }

    func handleTap(at pt: CGPoint) {
        model.startX = Double(pt.x)
        model.startY = Double(pt.y)
        model.startPlaced = true
        overlay?.setNeedsDisplay()
    }
}

final class CoworkingStartOverlay: UIView {
    weak var coordinator: CoworkingStartCoordinator?

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        coordinator?.handleTap(at: touch.location(in: self))
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }
        let model = coord.model

        for spot in model.spots {
            drawCoworkingDot(ctx: ctx, spot: spot, count: 0, isOver: false, faded: true)
        }
        guard model.startPlaced else { return }
        drawGroupMarker(ctx: ctx, x: model.startX, y: model.startY,
                        count: model.studentCount)
    }
}


struct CoworkingCanvas: UIViewRepresentable {
    @ObservedObject var model: AntCoworkingModel
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

        let imageView = UIImageView(image: UIImage(named: "mapEatTSU") ?? UIImage())
        imageView.frame = CGRect(origin: .zero, size: imgSize)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        container.addSubview(imageView)

        let canvas = CoworkingCanvasView(frame: CGRect(origin: .zero, size: imgSize))
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

    func makeCoordinator() -> CoworkingResultCoordinator { CoworkingResultCoordinator(model: model) }
}

final class CoworkingResultCoordinator: NSObject, UIScrollViewDelegate {
    var model: AntCoworkingModel
    weak var canvas: CoworkingCanvasView?
    weak var container: UIView?

    init(model: AntCoworkingModel) { self.model = model }

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

final class CoworkingCanvasView: UIView {
    weak var coordinator: CoworkingResultCoordinator?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }
        let model = coord.model
        let result = model.result

        if let r = result {
            for (j, spot) in model.spots.enumerated() {
                let count = r.allocations[j]
                guard count > 0, let path = model.roadSegments[j], path.count >= 2 else { continue }
                let intensity = min(1.0, Double(count) / Double(max(spot.capacity, 1)))
                let thickness = max(2.0, CGFloat(intensity) * 6.0)

                ctx.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.4).cgColor)
                ctx.setLineWidth(thickness + 2)
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                ctx.move(to: path[0])
                for pt in path.dropFirst() { ctx.addLine(to: pt) }
                ctx.strokePath()

                ctx.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.9).cgColor)
                ctx.setLineWidth(thickness)
                ctx.move(to: path[0])
                for pt in path.dropFirst() { ctx.addLine(to: pt) }
                ctx.strokePath()

                let mid = path[path.count / 2]
                let prev = path[max(0, path.count / 2 - 3)]
                drawArrow(ctx: ctx, from: prev, to: mid, color: .systemTeal)
            }
        } else {
            for j in 0..<model.spots.count {
                guard let path = model.roadSegments[j], path.count >= 2 else { continue }
                ctx.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.25).cgColor)
                ctx.setLineWidth(1.0)
                ctx.setLineDash(phase: 0, lengths: [4, 4])
                ctx.move(to: path[0])
                for pt in path.dropFirst() { ctx.addLine(to: pt) }
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }

    
        for (j, spot) in model.spots.enumerated() {
            let count = result?.allocations[j] ?? 0
            let isOver = count > spot.capacity
            drawCoworkingDot(ctx: ctx, spot: spot, count: count, isOver: isOver, faded: false)
        }

    
        drawGroupMarker(ctx: ctx, x: model.startX, y: model.startY,
                        count: model.studentCount)
    }
}


private func drawStartMarker(ctx: CGContext, x: Double, y: Double) {
    let pos = CGPoint(x: x, y: y)
    let r: CGFloat = 14
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4,
                  color: UIColor.black.withAlphaComponent(0.3).cgColor)
    ctx.setFillColor(UIColor.systemBlue.cgColor)
    ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()
    ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(3)
    ctx.strokeEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))

    if let icon = UIImage(systemName: "figure.stand")?
        .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        .withTintColor(.white, renderingMode: .alwaysOriginal) {
        let s: CGFloat = 16
        icon.draw(in: CGRect(x: pos.x - s / 2, y: pos.y - s / 2, width: s, height: s))
    }

    let label = "Вы здесь" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 9),
        .foregroundColor: UIColor.systemBlue,
        .backgroundColor: UIColor.white.withAlphaComponent(0.9)
    ]
    let sz = label.size(withAttributes: attrs)
    label.draw(at: CGPoint(x: pos.x - sz.width / 2, y: pos.y + r + 3),
               withAttributes: attrs)
}

private func drawGroupMarker(ctx: CGContext, x: Double, y: Double, count: Int) {
    let pos = CGPoint(x: x, y: y)
    let r: CGFloat = 16
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4,
                  color: UIColor.black.withAlphaComponent(0.4).cgColor)
    ctx.setFillColor(UIColor.systemOrange.cgColor)
    ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()
    ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(2.5)
    ctx.strokeEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))

    let label = "\(count)" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 11),
        .foregroundColor: UIColor.white
    ]
    let sz = label.size(withAttributes: attrs)
    label.draw(at: CGPoint(x: pos.x - sz.width / 2, y: pos.y - sz.height / 2),
               withAttributes: attrs)

    let title = "Группа" as NSString
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 9),
        .foregroundColor: UIColor.systemOrange,
        .backgroundColor: UIColor.white.withAlphaComponent(0.9)
    ]
    let tsz = title.size(withAttributes: titleAttrs)
    title.draw(at: CGPoint(x: pos.x - tsz.width / 2, y: pos.y + r + 3),
               withAttributes: titleAttrs)
}

private func drawPlaceDot(ctx: CGContext, pos: CGPoint, place: FoodPlace,
                           color: UIColor, index: Int?) {
    let r: CGFloat = 14
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                  color: UIColor.black.withAlphaComponent(0.3).cgColor)
    ctx.setFillColor(color.cgColor)
    ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()
    ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(2)
    ctx.strokeEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))

    if let icon = UIImage(systemName: place.category.icon)?
        .withConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))
        .withTintColor(.white, renderingMode: .alwaysOriginal) {
        let s: CGFloat = 14
        icon.draw(in: CGRect(x: pos.x - s / 2, y: pos.y - s / 2, width: s, height: s))
    }

    if let idx = index {
        let label = "\(idx)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 9),
            .foregroundColor: UIColor.white,
            .backgroundColor: UIColor.systemPurple
        ]
        label.draw(at: CGPoint(x: pos.x + r - 2, y: pos.y - r - 4),
                   withAttributes: attrs)
    }

    let name = place.name as NSString
    let nameAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 7, weight: .semibold),
        .foregroundColor: UIColor.black,
        .backgroundColor: UIColor.white.withAlphaComponent(0.85)
    ]
    let sz = name.size(withAttributes: nameAttrs)
    name.draw(at: CGPoint(x: pos.x - sz.width / 2, y: pos.y + r + 2),
              withAttributes: nameAttrs)
}

private func drawCoworkingDot(ctx: CGContext, spot: CoworkingSpot,
                               count: Int, isOver: Bool, faded: Bool) {
    let pos = spot.position
    let r: CGFloat = 14
    let fillColor: UIColor
    if faded {
        fillColor = UIColor.systemTeal.withAlphaComponent(0.4)
    } else if isOver {
        fillColor = .systemOrange
    } else if count > 0 {
        fillColor = .systemTeal
    } else {
        fillColor = .systemGray3
    }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                  color: UIColor.black.withAlphaComponent(0.3).cgColor)
    ctx.setFillColor(fillColor.cgColor)
    ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()
    ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(2)
    ctx.strokeEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))

    if let icon = UIImage(systemName: "laptopcomputer")?
        .withConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))
        .withTintColor(.white, renderingMode: .alwaysOriginal) {
        let s: CGFloat = 14
        icon.draw(in: CGRect(x: pos.x - s / 2, y: pos.y - s / 2, width: s, height: s))
    }

    if count > 0 {
        let badge = "\(count)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.white,
            .backgroundColor: isOver ? UIColor.systemOrange : UIColor.systemTeal
        ]
        badge.draw(at: CGPoint(x: pos.x + r - 4, y: pos.y - r - 4),
                   withAttributes: attrs)
    }

    let name = spot.name as NSString
    let nameAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 7, weight: .semibold),
        .foregroundColor: UIColor.black,
        .backgroundColor: UIColor.white.withAlphaComponent(0.85)
    ]
    let sz = name.size(withAttributes: nameAttrs)
    name.draw(at: CGPoint(x: pos.x - sz.width / 2, y: pos.y + r + 2),
              withAttributes: nameAttrs)

    let cap = "≤\(spot.capacity)" as NSString
    cap.draw(at: CGPoint(x: pos.x - 8, y: pos.y + r + 12),
             withAttributes: [.font: UIFont.systemFont(ofSize: 6),
                              .foregroundColor: UIColor.systemTeal])
}

private func drawArrow(ctx: CGContext, from: CGPoint, to: CGPoint, color: UIColor) {
    let mx = (from.x + to.x) / 2
    let my = (from.y + to.y) / 2
    let angle = atan2(to.y - from.y, to.x - from.x)
    ctx.saveGState()
    ctx.translateBy(x: mx, y: my); ctx.rotate(by: angle)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 7, y: 0))
    path.addLine(to: CGPoint(x: -5, y: -5))
    path.addLine(to: CGPoint(x: -5, y: 5))
    path.closeSubpath()
    ctx.setFillColor(color.cgColor); ctx.addPath(path); ctx.fillPath()
    ctx.restoreGState()
}

#Preview {
    AntView(places: loadPlaces(), mapModel: loadGridModel(filename: "campus-grid"))
}
