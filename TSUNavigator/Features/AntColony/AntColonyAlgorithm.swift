import Foundation
import CoreGraphics

struct AntCity: Identifiable {
    let id: Int
    let name: String
    let x: Double
    let y: Double
}

struct AntStep: Identifiable {
    let id = UUID()
    let iteration: Int
    let bestDistance: Double
    let bestRoute: [Int]
    let avgDistance: Double
}

struct AntResult {
    let bestRoute: [Int]
    let bestDistance: Double
    let steps: [AntStep]
    let pheromoneMatrix: [[Double]]
    let iterations: Int
}

struct CoworkingSpot: Identifiable {
    let id: Int
    let name: String
    let position: CGPoint
    let capacity: Int
    let comfort: Double
}

struct CoworkingResult {
    let allocations: [Int]
    let pheromones: [Double]
    let distances: [Double]
    let iterations: Int
    let overflow: Int
}

final class AntColonyAlgorithm {

    private let antCount: Int
    private let alpha: Double
    private let beta: Double
    private let evaporation: Double
    private let q: Double

    init(antCount: Int = 30,
         alpha: Double = 1.0,
         beta: Double = 3.0,
         evaporation: Double = 0.4,
         q: Double = 100.0) {
        self.antCount    = antCount
        self.alpha       = alpha
        self.beta        = beta
        self.evaporation = evaporation
        self.q           = q
    }

    func runOpenTSP(distMatrix: [[Double]],
                    iterations: Int = 100,
                    onStep: ((AntStep) -> Void)? = nil) -> AntResult {
        let total = distMatrix.count
        guard total >= 2 else {
            return AntResult(bestRoute: [], bestDistance: 0,
                             steps: [], pheromoneMatrix: [], iterations: 0)
        }

        let cityCount = total - 1

        var pheromone = Array(repeating: Array(repeating: 1.0, count: total), count: total)
        var steps: [AntStep] = []
        var globalBestRoute: [Int] = Array(1...cityCount)
        var globalBestDist = Double.infinity

        for iter in 0..<iterations {
            var allRoutes: [[Int]] = []
            var allDists: [Double] = []

            for _ in 0..<antCount {
                let route = buildOpenRoute(start: 0, cityCount: cityCount,
                                           pheromone: pheromone, dist: distMatrix)
                let d = openRouteDistance(route, dist: distMatrix)
                allRoutes.append(route)
                allDists.append(d)

                if d < globalBestDist {
                    globalBestDist = d
                    globalBestRoute = route
                }
            }

            for i in 0..<total {
                for j in 0..<total {
                    pheromone[i][j] *= (1.0 - evaporation)
                    if pheromone[i][j] < 0.001 { pheromone[i][j] = 0.001 }
                }
            }

            for k in 0..<antCount {
                guard allDists[k] > 0 else { continue }
                let contribution = q / allDists[k]
                let route = allRoutes[k]
                var prev = 0
                for next in route {
                    pheromone[prev][next] += contribution
                    pheromone[next][prev] += contribution
                    prev = next
                }
            }

            if globalBestDist.isFinite {
                let elite = q / globalBestDist
                var prev = 0
                for next in globalBestRoute {
                    pheromone[prev][next] += elite
                    pheromone[next][prev] += elite
                    prev = next
                }
            }

            let avgDist = allDists.reduce(0, +) / Double(allDists.count)

            let step = AntStep(
                iteration: iter,
                bestDistance: globalBestDist,
                bestRoute: globalBestRoute,
                avgDistance: avgDist
            )

            if iter % 5 == 0 || iter == iterations - 1 {
                steps.append(step)
            }
            onStep?(step)
        }

        return AntResult(
            bestRoute: globalBestRoute,
            bestDistance: globalBestDist,
            steps: steps,
            pheromoneMatrix: pheromone,
            iterations: iterations
        )
    }

    private func buildOpenRoute(start: Int, cityCount: Int,
                                pheromone: [[Double]], dist: [[Double]]) -> [Int] {
        var visited = Set<Int>()
        visited.insert(start)
        var route: [Int] = []
        var current = start

        for _ in 0..<cityCount {
            let next = selectNext(current: current, visited: visited,
                                  total: dist.count,
                                  pheromone: pheromone, dist: dist)
            route.append(next)
            visited.insert(next)
            current = next
        }
        return route
    }

    private func openRouteDistance(_ route: [Int], dist: [[Double]]) -> Double {
        guard !route.isEmpty else { return 0 }
        var total = dist[0][route[0]]
        for i in 1..<route.count {
            total += dist[route[i - 1]][route[i]]
        }
        return total
    }

    private func selectNext(current: Int, visited: Set<Int>,
                            total: Int, pheromone: [[Double]], dist: [[Double]]) -> Int {
        var probs: [(city: Int, prob: Double)] = []
        var totalProb = 0.0

        for j in 0..<total {
            guard !visited.contains(j) else { continue }
            let tau = pow(pheromone[current][j], alpha)
            let d = dist[current][j]

            let eta = d > 0 ? pow(1.0 / d, beta) : 1e10
            let p = tau * eta
            probs.append((city: j, prob: p))
            totalProb += p
        }

        guard !probs.isEmpty else { return current }
        guard totalProb > 0 else { return probs[0].city }

        var r = Double.random(in: 0..<totalProb)
        for (city, prob) in probs {
            r -= prob
            if r <= 0 { return city }
        }
        return probs.last!.city
    }

    func runCoworking(distances: [Double],
                      spots: [CoworkingSpot],
                      studentCount: Int,
                      iterations: Int = 60) -> CoworkingResult {
        let n = spots.count
        guard n > 0, studentCount > 0 else {
            return CoworkingResult(allocations: Array(repeating: 0, count: n),
                                   pheromones: Array(repeating: 0, count: n),
                                   distances: distances,
                                   iterations: 0,
                                   overflow: 0)
        }

        var pheromones = Array(repeating: 1.0, count: n)
        let totalCapacity = spots.reduce(0) { $0 + $1.capacity }

        for _ in 0..<iterations {

            var roundAssigned = Array(repeating: 0, count: n)

            for _ in 0..<antCount {
                let chosen = selectCoworking(pheromones: pheromones,
                                             distances: distances,
                                             spots: spots,
                                             assigned: roundAssigned)
                roundAssigned[chosen] += 1
            }

            for j in 0..<n {
                pheromones[j] *= (1.0 - evaporation)
                if pheromones[j] < 0.001 { pheromones[j] = 0.001 }
                if roundAssigned[j] > 0 {
                    let routeQuality = q / max(distances[j], 1.0)
                    pheromones[j] += routeQuality * spots[j].comfort * Double(roundAssigned[j])
                }
            }
        }

        let allocations = greedyDistribute(studentCount: studentCount,
                                           pheromones: pheromones,
                                           spots: spots,
                                           distances: distances,
                                           totalCapacity: totalCapacity)

        let overflow = max(0, studentCount - totalCapacity)

        return CoworkingResult(
            allocations: allocations,
            pheromones: pheromones,
            distances: distances,
            iterations: iterations,
            overflow: overflow
        )
    }

    private func selectCoworking(pheromones: [Double],
                                  distances: [Double],
                                  spots: [CoworkingSpot],
                                  assigned: [Int]) -> Int {
        var probs: [Double] = []
        var totalProb = 0.0

        for j in 0..<spots.count {
            let tau = pow(pheromones[j], alpha)
            let d = max(distances[j], 1.0)
            let eta = pow(1.0 / d, beta)
            let comfort = spots[j].comfort
            let cap = max(spots[j].capacity, 1)
            let availFactor = max(0.0, Double(cap - assigned[j]) / Double(cap))
            let p = tau * eta * comfort * (availFactor + 0.05)
            probs.append(p)
            totalProb += p
        }

        guard totalProb > 0 else { return 0 }
        var r = Double.random(in: 0..<totalProb)
        for (j, p) in probs.enumerated() {
            r -= p
            if r <= 0 { return j }
        }
        return probs.count - 1
    }

    private func greedyDistribute(studentCount: Int,
                                   pheromones: [Double],
                                   spots: [CoworkingSpot],
                                   distances: [Double],
                                   totalCapacity: Int) -> [Int] {
        let n = spots.count
        var allocations = Array(repeating: 0, count: n)

        let scores: [Double] = (0..<n).map { j in
            let d = max(distances[j], 1.0)
            return pheromones[j] * spots[j].comfort / d
        }

        let placeable = min(studentCount, totalCapacity)
        for _ in 0..<placeable {
            var bestJ = -1
            var bestScore = -Double.infinity
            for j in 0..<n {
                guard allocations[j] < spots[j].capacity else { continue }
                if scores[j] > bestScore {
                    bestScore = scores[j]
                    bestJ = j
                }
            }
            if bestJ < 0 { break }
            allocations[bestJ] += 1
        }

        var remaining = studentCount - placeable
        if remaining > 0 {
            let order = (0..<n).sorted { scores[$0] > scores[$1] }
            var idx = 0
            while remaining > 0 {
                allocations[order[idx % n]] += 1
                remaining -= 1
                idx += 1
            }
        }

        return allocations
    }
}
