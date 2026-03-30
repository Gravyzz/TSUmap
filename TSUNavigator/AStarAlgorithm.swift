import Foundation


final class AStarNode: Comparable, Hashable {
    let cell:   Cell
    var parent: AStarNode?
    var g:      Double
    var h:      Double
    var f:      Double { g + h }

    init(cell: Cell, parent: AStarNode? = nil, g: Double = 0, h: Double = 0) {
        self.cell   = cell
        self.parent = parent
        self.g      = g
        self.h      = h
    }

    static func < (lhs: AStarNode, rhs: AStarNode) -> Bool { lhs.f < rhs.f }
    static func == (lhs: AStarNode, rhs: AStarNode) -> Bool { lhs.cell == rhs.cell }
    func hash(into hasher: inout Hasher) { hasher.combine(cell) }
}

struct GridSnapshot {
    let rows: Int
    let cols: Int
    let grid: [[CellType]]
    let grassWalkable: Bool

    func isWalkable(row: Int, col: Int) -> Bool {
        guard row >= 0, row < rows, col >= 0, col < cols else { return false }
        let t = grid[row][col]
        switch t {
        case .road, .start, .end, .path, .visited:
            return true
        case .grass:
            return grassWalkable
        case .building, .obstacle, .barrier:
            return false
        }
    }
}

final class AStarAlgorithm {

    private func heuristic(from a: Cell, to b: Cell) -> Double {
        let dx = abs(a.col - b.col)
        let dy = abs(a.row - b.row)
        return Double(max(dx, dy)) + (sqrt(2.0) - 1.0) * Double(min(dx, dy))
    }

    private let directions: [(dr: Int, dc: Int, cost: Double)] = [
        (-1,  0, 1.0),
        ( 1,  0, 1.0),
        ( 0, -1, 1.0),
        ( 0,  1, 1.0),
        (-1, -1, 1.41421),
        (-1,  1, 1.41421),
        ( 1, -1, 1.41421),
        ( 1,  1, 1.41421),
    ]

    func findPath(
        in snapshot:     GridSnapshot,
        from start:      Cell,
        to end:          Cell,
        visitedCallback: ((Cell) -> Void)? = nil
    ) -> [Cell]? {

        let total = snapshot.rows * snapshot.cols
        var gScore  = [Double](repeating: .infinity, count: total)
        var inOpen  = [Bool](repeating: false, count: total)
        var closed  = [Bool](repeating: false, count: total)
        var parentMap = [Int: AStarNode]()

        func idx(_ c: Cell) -> Int { c.row * snapshot.cols + c.col }

        var heap = [AStarNode]()
        heap.reserveCapacity(4096)

        func heapPush(_ node: AStarNode) {
            heap.append(node)
            var i = heap.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if heap[parent].f <= heap[i].f { break }
                heap.swapAt(parent, i)
                i = parent
            }
        }

        func heapPop() -> AStarNode {
            let top = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = 2 * i + 2
                    var smallest = i
                    if l < heap.count && heap[l].f < heap[smallest].f { smallest = l }
                    if r < heap.count && heap[r].f < heap[smallest].f { smallest = r }
                    if smallest == i { break }
                    heap.swapAt(i, smallest)
                    i = smallest
                }
            }
            return top
        }

        let startNode = AStarNode(cell: start, g: 0, h: heuristic(from: start, to: end))
        gScore[idx(start)] = 0
        inOpen[idx(start)] = true
        parentMap[idx(start)] = startNode
        heapPush(startNode)

        while !heap.isEmpty {
            let current = heapPop()
            let ci = idx(current.cell)

            if closed[ci] { continue }
            closed[ci] = true
            inOpen[ci] = false

            if current.cell == end {
                return reconstructPath(from: current)
            }

            visitedCallback?(current.cell)

            for dir in directions {
                let nr = current.cell.row + dir.dr
                let nc = current.cell.col + dir.dc

                guard snapshot.isWalkable(row: nr, col: nc) else { continue }

                if dir.cost > 1.0 {
                    let freeA = snapshot.isWalkable(row: current.cell.row + dir.dr, col: current.cell.col)
                    let freeB = snapshot.isWalkable(row: current.cell.row, col: current.cell.col + dir.dc)
                    guard freeA && freeB else { continue }
                }

                let neighbor = Cell(row: nr, col: nc)
                let ni = idx(neighbor)

                if closed[ni] { continue }


                var moveCost = dir.cost
                if snapshot.grid[nr][nc] == .grass {
                    moveCost *= 1.5
                }
                let newG = current.g + moveCost

                if newG < gScore[ni] {
                    gScore[ni] = newG
                    let newH = heuristic(from: neighbor, to: end)
                    let node = AStarNode(cell: neighbor, parent: current, g: newG, h: newH)
                    parentMap[ni] = node
                    heapPush(node)
                }
            }
        }

        return nil
    }

    private func reconstructPath(from node: AStarNode) -> [Cell] {
        var path    = [Cell]()
        var current: AStarNode? = node
        while let c = current {
            path.append(c.cell)
            current = c.parent
        }
        return path.reversed()
    }
}
