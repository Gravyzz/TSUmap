import Foundation
import SwiftUI
import Combine

struct Cell: Hashable, Equatable, Sendable {
    let row: Int
    let col: Int

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(row)
        hasher.combine(col)
    }

    nonisolated static func == (lhs: Cell, rhs: Cell) -> Bool {
        lhs.row == rhs.row && lhs.col == rhs.col
    }
}

enum CellType: Sendable {
    case road
    case grass
    case obstacle
    case building
    case barrier
    case start
    case end
    case path
    case visited
}

class MapGrid: ObservableObject {
    let rows: Int
    let cols: Int

    @Published var grid: [[CellType]]
    @Published var startCell: Cell? = nil
    @Published var endCell:   Cell? = nil

    init(rows: Int, cols: Int, buildings: Set<Cell> = []) {
        self.rows = rows
        self.cols = cols
        self.grid = Array(repeating: Array(repeating: .road, count: cols), count: rows)
        for cell in buildings {
            guard cell.row >= 0, cell.row < rows,
                  cell.col >= 0, cell.col < cols else { continue }
            grid[cell.row][cell.col] = .building
        }
    }

    func tapCell(row: Int, col: Int) {
        guard row >= 0, row < rows, col >= 0, col < cols else { return }
        let type = grid[row][col]
        guard type != .building, type != .obstacle, type != .barrier else { return }

        let tapped = Cell(row: row, col: col)
        if startCell == nil {
            startCell = tapped
            grid[row][col] = .start
        } else if endCell == nil && tapped != startCell {
            endCell = tapped
            grid[row][col] = .end
        }
    }

    func toggleBarrier(row: Int, col: Int) {
        guard row >= 0, row < rows, col >= 0, col < cols else { return }
        let type = grid[row][col]
        guard type != .building, type != .obstacle, type != .start, type != .end else { return }
        grid[row][col] = (type == .barrier) ? .road : .barrier
    }

    func isWalkable(row: Int, col: Int) -> Bool {
        guard row >= 0, row < rows, col >= 0, col < cols else { return false }
        let t = grid[row][col]
        return t != .building && t != .obstacle && t != .barrier
    }

    func reset(removeBarriers: Bool) {
        for r in 0..<rows {
            for c in 0..<cols {
                switch grid[r][c] {
                case .start, .end, .path, .visited:
                    grid[r][c] = .road
                case .barrier where removeBarriers:
                    grid[r][c] = .road
                default: break
                }
            }
        }
        startCell = nil
        endCell   = nil
    }

    func clearPath() {
        for r in 0..<rows {
            for c in 0..<cols {
                if grid[r][c] == .path || grid[r][c] == .visited {
                    grid[r][c] = .road
                }
            }
        }
    }

    func setCell(row: Int, col: Int, type: CellType) {
        guard row >= 0, row < rows, col >= 0, col < cols else { return }
        grid[row][col] = type
    }

    func snapshot(grassWalkable: Bool = false) -> GridSnapshot {
        GridSnapshot(rows: rows, cols: cols, grid: grid, grassWalkable: grassWalkable)
    }
}
