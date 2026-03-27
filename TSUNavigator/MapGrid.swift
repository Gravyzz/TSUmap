import Foundation
import SwiftUI

struct Cell: Hashable, Equatable {
    let row: Int
    let col: Int
}


enum CellType {
    case walkable
    case obstacle
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
    @Published var endCell: Cell? = nil

    init(rows: Int = 30, cols: Int = 30) {
        self.rows = rows
        self.cols = cols
        self.grid = Array(repeating: Array(repeating: .walkable, count: cols), count: rows)
    }


    func tapCell(row: Int, col: Int) {
        let tapped = Cell(row: row, col: col)

        if startCell == nil {
            startCell = tapped
            grid[row][col] = .start
        } else if endCell == nil && tapped != startCell {
            endCell = tapped
            grid[row][col] = .end
        } else if tapped == startCell || tapped == endCell {
            return
        } else if grid[row][col] == .obstacle {
            grid[row][col] = .walkable
        } else if grid[row][col] == .walkable {
            grid[row][col] = .obstacle
        }
    }


    func isWalkable(row: Int, col: Int) -> Bool {
        guard row >= 0, row < rows, col >= 0, col < cols else { return false }
        return grid[row][col] != .obstacle
    }


    func reset() {
        grid = Array(repeating: Array(repeating: .walkable, count: cols), count: rows)
        startCell = nil
        endCell = nil
    }


    func clearPath() {
        for r in 0..= 0, row < rows, col >= 0, col < cols else { return }
        grid[row][col] = type
    }
}
