import Foundation

class AStarNode: Comparable {
    let cell: Cell
    var parent: AStarNode?
    var g: Double
    var h: Double
    var f: Double { g + h }

    init(cell: Cell, parent: AStarNode? = nil, g: Double = 0, h: Double = 0) {
        self.cell = cell
        self.parent = parent
        self.g = g
        self.h = h
    }

    static func < (lhs: AStarNode, rhs: AStarNode) -> Bool { lhs.f < rhs.f }
    static func == (lhs: AStarNode, rhs: AStarNode) -> Bool { lhs.cell == rhs.cell }
}

class AStarAlgorithm {

    private func heuristic(from: Cell, to: Cell) -> Double {
        return Double(abs(from.row - to.row) + abs(from.col - to.col))
    }

    private func neighbors(of cell: Cell, in grid: MapGrid) -> [Cell] {
        let directions = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        var result: [Cell] = []
        for (dr, dc) in directions {
            let newRow = cell.row + dr
            let newCol = cell.col + dc
            if grid.isWalkable(row: newRow, col: newCol) {
                result.append(Cell(row: newRow, col: newCol))
            }
        }
        return result
    }

    func findPath(in grid: MapGrid, from start: Cell, to end: Cell) -> [Cell]? {
        var openList: [AStarNode] = []
        var closedSet: Set<Cell> = []

        let startNode = AStarNode(cell: start, g: 0, h: heuristic(from: start, to: end))
        openList.append(startNode)

        while !openList.isEmpty {
            openList.sort()
            let current = openList.removeFirst()

            if current.cell == end {
                return reconstructPath(from: current)
            }

            closedSet.insert(current.cell)

            for neighborCell in neighbors(of: current.cell, in: grid) {
                if closedSet.contains(neighborCell) { continue }

                let newG = current.g + 1
                let newH = heuristic(from: neighborCell, to: end)
                let neighborNode = AStarNode(cell: neighborCell, parent: current, g: newG, h: newH)

                if let existing = openList.first(where: { $0.cell == neighborCell }), existing.g <= newG {
                    continue
                }
                openList.append(neighborNode)
            }
        }
        return nil
    }

    private func reconstructPath(from node: AStarNode) -> [Cell] {
        var path: [Cell] = []
        var current: AStarNode? = node
        while let c = current {
            path.append(c.cell)
            current = c.parent
        }
        return path.reversed()
    }
}
