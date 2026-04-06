import Foundation
import CoreLocation
import Combine


// Значения клеток:
//   0 = дорога
//   1 = газон
//   2 = препятствие
//   3 = здание

private struct OriginJSON: Codable {
    let lat: Double
    let lng: Double
}

private struct GridDataJSON: Codable {
    let rows:     Int
    let cols:     Int
    let cellSize: Double
    let origin:   OriginJSON
    let cells:    [[Int]]
}

class MapGridModel: ObservableObject {
    let rows:       Int
    let cols:       Int
    let cellMeters: Double
    let origin:     CLLocationCoordinate2D
    let terrain: [[UInt8]]

    @Published var grid:      [[CellType]]
    @Published var startCell: Cell? = nil
    @Published var endCell:   Cell? = nil

    @Published var selectedStartBuilding: Set<Cell>? = nil
    @Published var selectedEndBuilding:   Set<Cell>? = nil
    @Published var focusedPlaceBuilding:  Set<Cell>? = nil
    @Published var focusedPlace: FoodPlace? = nil
    @Published var focusedPlaceTargetCell: Cell? = nil
    @Published var routeToFocusedPlaceActive = false
    @Published var selectedBuildingPlaces: [FoodPlace] = []
    @Published var bindingPlace: FoodPlace? = nil
    @Published var pendingBindingBuilding: Set<Cell>? = nil
    @Published var pendingBindingCell: Cell? = nil

    @Published var visitedCells:  [Cell] = []
    @Published var frontierCells: Set<Cell> = []
    @Published var pathCells:     [Cell] = []
    @Published var barrierCells:  Set<Cell> = []

    private var availablePlaces: [FoodPlace] = []

    fileprivate init(from raw: GridDataJSON) {
        self.rows       = raw.rows
        self.cols       = raw.cols
        self.cellMeters = raw.cellSize

        let lat = (abs(raw.origin.lat) < 0.001) ? 56.4860 : raw.origin.lat
        let lng = (abs(raw.origin.lng) < 0.001) ? 84.9415 : raw.origin.lng
        self.origin = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        self.terrain = raw.cells.map { row in row.map { UInt8(clamping: $0) } }

        var g = Array(
            repeating: Array(repeating: CellType.road, count: raw.cols),
            count: raw.rows
        )
        for r in 0..<raw.rows {
            for c in 0..<raw.cols {
                switch raw.cells[r][c] {
                case 0: g[r][c] = .road
                case 1: g[r][c] = .grass
                case 2: g[r][c] = .obstacle
                case 3: g[r][c] = .building
                default: g[r][c] = .road
                }
            }
        }
        self.grid = g
    }

    init(rows: Int = 30, cols: Int = 30, cellMeters: Double = 3,
         lat: Double = 56.4860, lng: Double = 84.9415) {
        self.rows       = rows
        self.cols       = cols
        self.cellMeters = cellMeters
        self.origin     = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        self.terrain    = Array(repeating: Array(repeating: 0, count: cols), count: rows)
        self.grid       = Array(
            repeating: Array(repeating: .road, count: cols),
            count: rows
        )
    }

    func setAvailablePlaces(_ places: [FoodPlace]) {
        availablePlaces = places
    }


    func terrainCellType(_ r: Int, _ c: Int) -> CellType {
        switch terrain[r][c] {
        case 0: return .road
        case 1: return .grass
        case 2: return .obstacle
        case 3: return .building
        default: return .road
        }
    }
    
    func cell(for coordinate: CLLocationCoordinate2D) -> Cell? {
        let mpLat = 111_000.0
        let mpLng = 111_000.0 * cos(origin.latitude * .pi / 180)

        let dLat = origin.latitude  - coordinate.latitude
        let dLng = coordinate.longitude - origin.longitude

        let row = Int(dLat * mpLat / cellMeters)
        let col = Int(dLng * mpLng / cellMeters)

        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return Cell(row: row, col: col)
    }

    func coordinate(for cell: Cell) -> CLLocationCoordinate2D {
        let mpLat = 111_000.0
        let mpLng = 111_000.0 * cos(origin.latitude * .pi / 180)

        let lat = origin.latitude  - (Double(cell.row) + 0.5) * cellMeters / mpLat
        let lng = origin.longitude + (Double(cell.col) + 0.5) * cellMeters / mpLng

        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    func floodFillBuilding(from start: Cell) -> Set<Cell> {
        guard start.row >= 0, start.row < rows,
              start.col >= 0, start.col < cols,
              terrain[start.row][start.col] == 3 else { return [] }

        var result = Set<Cell>()
        var queue  = [start]
        result.insert(start)

        let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            for (dr, dc) in dirs {
                let nr = cur.row + dr
                let nc = cur.col + dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                let neighbor = Cell(row: nr, col: nc)
                guard terrain[nr][nc] == 3, !result.contains(neighbor) else { continue }
                result.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return result
    }

    func showPlace(_ place: FoodPlace) {
        clearPath()
        startCell = nil
        endCell = nil
        selectedStartBuilding = nil
        selectedEndBuilding = nil
        bindingPlace = nil
        pendingBindingBuilding = nil
        pendingBindingCell = nil
        focusedPlace = place
        selectedBuildingPlaces = []
        routeToFocusedPlaceActive = false

        guard let reference = place.campusBuildingCell else {
            focusedPlaceBuilding = nil
            focusedPlaceTargetCell = nil
            return
        }

        let seedCell = Cell(row: reference.row, col: reference.col)
        focusedPlaceBuilding = floodFillBuilding(from: seedCell)
        focusedPlaceTargetCell = seedCell
    }

    func beginRouteToFocusedPlace() {
        guard focusedPlace != nil,
              let targetCell = focusedPlaceTargetCell else { return }

        clearPath()
        startCell = nil
        selectedStartBuilding = nil
        endCell = targetCell
        selectedEndBuilding = focusedPlaceBuilding
        routeToFocusedPlaceActive = true
    }

    func clearStartSelection() {
        if let startCell, grid[startCell.row][startCell.col] == .start {
            grid[startCell.row][startCell.col] = terrainCellType(startCell.row, startCell.col)
        }
        startCell = nil
        selectedStartBuilding = nil
        if focusedPlace == nil {
            selectedBuildingPlaces = []
        }
    }

    func clearEndSelection() {
        if let endCell, grid[endCell.row][endCell.col] == .end {
            grid[endCell.row][endCell.col] = terrainCellType(endCell.row, endCell.col)
        }
        endCell = nil
        selectedEndBuilding = nil
        if focusedPlace == nil {
            selectedBuildingPlaces = []
        }
    }

    func clearFocusedPlaceMode() {
        clearPath()
        clearStartSelection()
        clearEndSelection()
        focusedPlaceBuilding = nil
        focusedPlace = nil
        focusedPlaceTargetCell = nil
        selectedBuildingPlaces = []
        routeToFocusedPlaceActive = false
    }

    func beginBinding(for place: FoodPlace) {
        clearPath()
        startCell = nil
        endCell = nil
        selectedStartBuilding = nil
        selectedEndBuilding = nil
        focusedPlaceBuilding = nil
        focusedPlace = nil
        focusedPlaceTargetCell = nil
        selectedBuildingPlaces = []
        routeToFocusedPlaceActive = false
        bindingPlace = place
        if let reference = place.campusBuildingCell {
            let cell = Cell(row: reference.row, col: reference.col)
            pendingBindingBuilding = floodFillBuilding(from: cell)
            pendingBindingCell = cell
        } else {
            pendingBindingBuilding = nil
            pendingBindingCell = nil
        }
    }

    func selectBindingBuilding(from cell: Cell) {
        let buildingCells = floodFillBuilding(from: cell)
        guard !buildingCells.isEmpty else { return }
        pendingBindingBuilding = buildingCells
        pendingBindingCell = cell
    }

    func cancelBinding() {
        bindingPlace = nil
        pendingBindingBuilding = nil
        pendingBindingCell = nil
    }

    func completeBinding() {
        bindingPlace = nil
        pendingBindingBuilding = nil
        pendingBindingCell = nil
    }

    func places(in buildingCells: Set<Cell>) -> [FoodPlace] {
        availablePlaces
            .filter { place in
                guard let reference = place.campusBuildingCell else { return false }
                return buildingCells.contains(Cell(row: reference.row, col: reference.col))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func updateSelectedBuildingPlaces(for buildingCells: Set<Cell>) {
        selectedBuildingPlaces = places(in: buildingCells)
    }
    
    func nearestWalkableEdge(of buildingCells: Set<Cell>,
                             to target: Cell,
                             grassWalkable: Bool) -> Cell? {
        let dirs = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]
        var bestCell: Cell? = nil
        var bestDist = Int.max

        for bc in buildingCells {
            for (dr, dc) in dirs {
                let nr = bc.row + dr
                let nc = bc.col + dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                let neighbor = Cell(row: nr, col: nc)
                guard !buildingCells.contains(neighbor) else { continue }

                let t = grid[nr][nc]
                let walkable = (t == .road || (t == .grass && grassWalkable))
                guard walkable else { continue }

                let dist = abs(nr - target.row) + abs(nc - target.col)
                if dist < bestDist {
                    bestDist = dist
                    bestCell = neighbor
                }
            }
        }
        return bestCell
    }

    func reset(removeBarriers: Bool) {
        for r in 0..<rows {
            for c in 0..<cols {
                switch grid[r][c] {
                case .start, .end, .path, .visited:
                    grid[r][c] = terrainCellType(r, c)
                case .barrier where removeBarriers:
                    grid[r][c] = terrainCellType(r, c)
                default: break
                }
            }
        }
        startCell = nil
        endCell   = nil
        selectedStartBuilding = nil
        selectedEndBuilding   = nil
        focusedPlaceBuilding  = nil
        focusedPlace          = nil
        focusedPlaceTargetCell = nil
        routeToFocusedPlaceActive = false
        bindingPlace          = nil
        pendingBindingBuilding = nil
        pendingBindingCell     = nil
        visitedCells  = []
        frontierCells = []
        pathCells     = []
        if removeBarriers { barrierCells = [] }
    }

    func clearPath() {
        for r in 0..<rows {
            for c in 0..<cols {
                if grid[r][c] == .path || grid[r][c] == .visited {
                    grid[r][c] = terrainCellType(r, c)
                }
            }
        }
        visitedCells  = []
        frontierCells = []
        pathCells     = []
    }

    func setCell(row: Int, col: Int, type: CellType) {
        guard row >= 0, row < rows, col >= 0, col < cols else { return }
        grid[row][col] = type
    }

    func snapshot(grassWalkable: Bool = false) -> GridSnapshot {
        GridSnapshot(rows: rows, cols: cols, grid: grid, grassWalkable: grassWalkable)
    }
}

func loadGridModel(filename: String) -> MapGridModel {
    guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
          let data = try? Data(contentsOf: url)
    else {
        print("⚠️ '\(filename).json' не найден в Bundle — используем пустую сетку")
        return MapGridModel()
    }

    let decoder = JSONDecoder()
    guard let decoded = try? decoder.decode(GridDataJSON.self, from: data) else {
        print("⚠️ Не удалось декодировать '\(filename).json'")
        return MapGridModel()
    }

    let origin = decoded.origin
    print("✅ Сетка: \(decoded.rows)×\(decoded.cols), ячейка=\(decoded.cellSize)м, origin=(\(origin.lat), \(origin.lng))")
    return MapGridModel(from: decoded)
}
