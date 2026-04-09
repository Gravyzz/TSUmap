import SwiftUI
import CoreLocation
import Combine

enum EditMode { case navigate, addBarrier }

@MainActor
final class LocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }
}

extension LocationManager: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {}
}

struct AStarView: View {

    @ObservedObject var model: MapGridModel
    var onConfirmBinding: ((FoodPlace, CampusBuildingReference) -> Void)? = nil
    var onRatePlace: ((FoodPlace) -> Void)? = nil
    var onResetRating: ((FoodPlace) -> Void)? = nil
    @StateObject private var locationManager = LocationManager()

    @State private var editMode:          EditMode = .navigate
    @State private var grassWalkable:     Bool     = false
    @State private var pathLength:        Int      = 0
    @State private var pathDistanceMeters: Double  = 0
    @State private var noPath:            Bool     = false
    @State private var isRunning:         Bool     = false
    @State private var visitedCount:      Int      = 0
    @State private var animationGen:      Int      = 0
    @State private var brushRadius:       Double   = 5
    @State private var showBuildingPlacesList = false
    @State private var presentedPlaceCard: FoodPlace? = nil

    private let algo = AStarAlgorithm()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                hintBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                if let place = model.focusedPlace {
                    focusedPlaceCard(place)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                } else if !model.selectedBuildingPlaces.isEmpty {
                    selectedBuildingPlacesCard
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }

                statusBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                AStarMapView(model: model, editMode: editMode, brushRadius: Int(brushRadius))
                    .ignoresSafeArea(edges: .horizontal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if editMode == .addBarrier {
                    brushSlider
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }

                if model.bindingPlace == nil {
                    grassToggle
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }

                controlButtons
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                legendBar
                    .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
            .navigationTitle("A* — Маршрут")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $presentedPlaceCard) { place in
                PlaceCardView(place: place) {
                    model.showPlace(place)
                } onBindBuilding: {
                    model.beginBinding(for: place)
                } onRatePlace: {
                    onRatePlace?(place)
                } onResetRating: {
                    onResetRating?(place)
                }
                .presentationDetents([.medium, .large])
            }
            .onChange(of: model.selectedBuildingPlaces.map(\.id)) { _, newValue in
                if newValue.isEmpty {
                    showBuildingPlacesList = false
                } else if newValue.count == 1 {
                    showBuildingPlacesList = false
                }
            }
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Picker("", selection: $editMode) {
                Image(systemName: "mappin").tag(EditMode.navigate)
                Image(systemName: "pencil").tag(EditMode.addBarrier)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .disabled(model.bindingPlace != nil)
        }
    }

    var brushSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "paintbrush.pointed")
                .foregroundColor(.orange)
                .font(.caption)
            Text("Кисть: \(Int(brushRadius))")
                .font(.caption)
                .foregroundColor(.orange)
                .frame(width: 65, alignment: .leading)
            Slider(value: $brushRadius, in: 1...20, step: 1)
                .tint(.orange)
        }
    }

    var grassToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: grassWalkable ? "leaf.fill" : "leaf")
                .foregroundColor(grassWalkable ? .green : .secondary)
                .font(.caption)
            Text(grassWalkable ? "По газону: можно" : "По газону: нельзя")
                .font(.caption)
                .foregroundColor(grassWalkable ? .green : .secondary)
            Spacer()
            Toggle("", isOn: $grassWalkable)
                .labelsHidden()
                .tint(.green)
        }
    }

    var hintBar: some View {
        HStack(spacing: 6) {
            if let place = model.bindingPlace {
                Image(systemName: "building.2.crop.circle")
                    .foregroundColor(.cyan)
                Text("Выберите на карте здание для «\(place.name)»")
                    .font(.caption)
                    .foregroundColor(.cyan)
            } else if model.focusedPlace != nil, !model.routeToFocusedPlaceActive {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundColor(.blue)
                Text("Тапните в пустое место, чтобы выйти из режима заведения")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if editMode == .addBarrier {
                Image(systemName: "paintbrush.pointed").foregroundColor(.orange)
                Text("Зажми и води пальцем — рисуй/стирай барьеры")
                    .font(.caption).foregroundColor(.orange)
            } else {
                Image(systemName: "mappin").foregroundColor(.blue)
                Text(
                    model.startCell == nil ? "Тапни на карту или здание — СТАРТ" :
                    model.endCell   == nil ? "Тапни на карту или здание — ФИНИШ" :
                                             "Нажми «Найти путь»"
                )
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    var statusBar: some View {
        Group {
            if isRunning {
                HStack {
                    ProgressView()
                    Text("Ищу путь… просмотрено \(visitedCount) клеток")
                        .font(.caption2).foregroundColor(.secondary)
                }
            } else if noPath {
                Label("Путь не найден", systemImage: "xmark.circle")
                    .foregroundColor(.red).font(.caption).bold()
            } else if pathLength > 0 {
                let timeMin = pathDistanceMeters / 83.33
                Label(
                    "Путь: \(Int(pathDistanceMeters)) м · ~\(String(format: "%.0f", timeMin)) мин · просмотрено \(visitedCount)",
                    systemImage: "checkmark.circle"
                )
                .foregroundColor(.green).font(.caption).bold()
            } else {
                Color.clear.frame(height: 16)
            }
        }
    }

    var controlButtons: some View {
        Group {
            if let place = model.bindingPlace {
                bindingControls(for: place)
            } else if let place = model.focusedPlace, !model.routeToFocusedPlaceActive {
                placeControls(for: place)
            } else {
                routeControls
            }
        }
    }

    func focusedPlaceCard(_ place: FoodPlace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.name)
                .font(.headline)
            Text(place.address)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    var selectedBuildingPlacesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            buildingPlaceRow(model.selectedBuildingPlaces[0])

            if model.selectedBuildingPlaces.count > 1 {
                Button {
                    showBuildingPlacesList.toggle()
                } label: {
                    HStack {
                        Text(showBuildingPlacesList ? "Скрыть список заведений" : "Посмотреть еще \(model.selectedBuildingPlaces.count - 1)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: showBuildingPlacesList ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                }
                .buttonStyle(.plain)

                if showBuildingPlacesList {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(model.selectedBuildingPlaces.dropFirst())) { place in
                                buildingPlaceRow(place)
                            }
                        }
                    }
                    .frame(maxHeight: 170)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    func buildingPlaceRow(_ place: FoodPlace) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(categoryColor(for: place).opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: place.category.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(categoryColor(for: place))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(place.category.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showBuildingPlacesList = false
                presentedPlaceCard = place
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    func bindingControls(for place: FoodPlace) -> some View {
        VStack(spacing: 8) {
            Text(place.address)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    confirmBinding()
                } label: {
                    Label("Подтвердить здание", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(MapActionButtonStyle())
                .disabled(model.pendingBindingCell == nil)

                Button {
                    model.cancelBinding()
                } label: {
                    Label("Отмена", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(MapSecondaryButtonStyle())
            }
        }
    }

    func placeControls(for place: FoodPlace) -> some View {
        VStack(spacing: 8) {
            Button {
                model.beginRouteToFocusedPlace()
            } label: {
                Label("Проложить маршрут", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(MapActionButtonStyle())
            .disabled(place.campusBuildingCell == nil)
        }
    }

    var routeControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    runAStar()
                } label: {
                    Label("Найти путь", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(MapActionButtonStyle())
                .disabled(model.startCell == nil || model.endCell == nil || isRunning)

                Button {
                    resetMapState()
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(MapTrashButtonStyle())
                .disabled(isRunning)
            }

            if model.startCell == nil {
                Button {
                    locationManager.requestLocation()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard let loc = locationManager.location,
                              let cell = model.cell(for: loc.coordinate) else { return }
                        let cellType = model.grid[cell.row][cell.col]
                        guard cellType != .building, cellType != .obstacle else { return }
                        model.startCell = cell
                        model.grid[cell.row][cell.col] = .start
                        locationManager.stop()
                    }
                } label: {
                    Label("Моя позиция — СТАРТ", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(MapSecondaryButtonStyle())
            }
        }
    }

    var legendBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                legendItem(.green,                          "Старт")
                legendItem(.red,                            "Финиш")
                legendItem(Color.black.opacity(0.55),       "Здание")
                legendItem(Color.green.opacity(0.35),       "Газон")
                legendItem(Color.orange.opacity(0.55),      "Барьер")
                legendItem(Color.orange.opacity(0.45),      "Анализ")
                legendItem(.blue.opacity(0.25),             "Просмотрено")
                legendItem(Color(red: 0.25, green: 0.56, blue: 1.0), "Маршрут")
            }
            .padding(.horizontal, 12)
        }
        .font(.caption2)
    }

    func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )
            Text(label)
        }
    }

    func cancelAnimations() {
        animationGen += 1
        isRunning = false
    }

    func confirmBinding() {
        guard let place = model.bindingPlace,
              let cell = model.pendingBindingCell else { return }
        onConfirmBinding?(place, CampusBuildingReference(row: cell.row, col: cell.col))
        model.completeBinding()
    }

    func resetMapState() {
        cancelAnimations()
        model.reset(removeBarriers: false)
        pathLength = 0
        pathDistanceMeters = 0
        noPath = false
        visitedCount = 0
    }

    func categoryColor(for place: FoodPlace) -> Color {
        switch place.category {
        case .vending:    return .purple
        case .buffet:     return .orange
        case .cafeteria:  return .blue
        case .canteen:    return .green
        case .coffeeshop: return .brown
        case .cafe:       return .red
        case .fastfood:   return .red
        case .gastrohall: return .yellow
        case .shop:       return .teal
        }
    }

    func runAStar() {
        guard let start = model.startCell,
              let end   = model.endCell else { return }

        isRunning         = true
        noPath            = false
        visitedCount      = 0
        pathDistanceMeters = 0
        model.clearPath()

        let generation = animationGen + 1
        animationGen   = generation

        var actualStart = start
        var actualEnd   = end

        if let startBuilding = model.selectedStartBuilding {
            if let edge = model.nearestWalkableEdge(of: startBuilding,
                                                     to: end,
                                                     grassWalkable: grassWalkable) {
                actualStart = edge
            }
        }
        if let endBuilding = model.selectedEndBuilding {
            if let edge = model.nearestWalkableEdge(of: endBuilding,
                                                     to: start,
                                                     grassWalkable: grassWalkable) {
                actualEnd = edge
            }
        }

        let snapshot = model.snapshot(grassWalkable: grassWalkable)
        let capturedStart = actualStart
        let capturedEnd   = actualEnd
        let cellMeters    = model.cellMeters

        DispatchQueue.global(qos: .userInitiated).async {
            var events: [AStarEvent] = []
            events.reserveCapacity(100_000)

            let path = algo.findPath(in: snapshot, from: capturedStart, to: capturedEnd) { event in
                events.append(event)
            } ?? []

            var distMeters: Double = 0
            for i in 1..<max(1, path.count) {
                let dr = abs(path[i].row - path[i-1].row)
                let dc = abs(path[i].col - path[i-1].col)
                let step: Double = (dr != 0 && dc != 0) ? 1.41421 : 1.0
                distMeters += step * cellMeters
            }

            DispatchQueue.main.async {
                guard generation == self.animationGen else { return }

                guard !path.isEmpty else {
                    self.noPath    = true
                    self.isRunning = false
                    return
                }

                let batchSize = max(events.count / 80, 100)
                let totalBatches = (events.count + batchSize - 1) / batchSize

                for batchIdx in 0..<totalBatches {
                    let batchStart = batchIdx * batchSize
                    let batchEnd   = min(batchStart + batchSize, events.count)

                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(batchIdx) * 0.03) {
                        guard generation == self.animationGen else { return }
                        for i in batchStart..<batchEnd {
                            switch events[i] {
                            case .visited(let cell):
                                self.model.frontierCells.remove(cell)
                                let t = self.model.grid[cell.row][cell.col]
                                if t == .road || t == .grass {
                                    self.model.visitedCells.append(cell)
                                }
                            case .frontier(let cell):
                                let t = self.model.grid[cell.row][cell.col]
                                if t == .road || t == .grass {
                                    self.model.frontierCells.insert(cell)
                                }
                            }
                        }
                        self.visitedCount = self.model.visitedCells.count
                    }
                }

                let visitedDelay = Double(totalBatches) * 0.03 + 0.1

                DispatchQueue.main.asyncAfter(deadline: .now() + visitedDelay - 0.05) {
                    guard generation == self.animationGen else { return }
                    self.model.frontierCells.removeAll()
                }

                let pathBatchSize = max(path.count / 40, 10)
                let pathBatches   = (path.count + pathBatchSize - 1) / pathBatchSize

                for batchIdx in 0..<pathBatches {
                    let batchStart = batchIdx * pathBatchSize
                    let batchEnd   = min(batchStart + pathBatchSize, path.count)

                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + visitedDelay + Double(batchIdx) * 0.04
                    ) {
                        guard generation == self.animationGen else { return }
                        for i in batchStart..<batchEnd {
                            self.model.pathCells.append(path[i])
                        }
                        if batchEnd == path.count {
                            self.pathLength         = path.count - 1
                            self.pathDistanceMeters = distMeters
                            self.isRunning          = false
                        }
                    }
                }
            }
        }
    }
}

private struct MapActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

private struct MapSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.systemGray4), lineWidth: configuration.isPressed ? 0.5 : 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct MapTrashButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

#Preview { AStarView(model: loadGridModel(filename: "campus-grid")) }
