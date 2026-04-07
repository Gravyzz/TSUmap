import Foundation

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

    func run(cities: [AntCity], iterations: Int = 100) -> AntResult {
        let n = cities.count
        guard n >= 2 else {
            return AntResult(bestRoute: Array(0..<n), bestDistance: 0,
                             steps: [], pheromoneMatrix: [], iterations: 0)
        }

        let dist = buildDistanceMatrix(cities: cities)
        var pheromone = Array(repeating: Array(repeating: 1.0, count: n), count: n)
        var steps: [AntStep] = []
        var globalBestRoute: [Int] = Array(0..<n)
        var globalBestDist = Double.infinity

        for iter in 0..<iterations {
            var allRoutes: [[Int]] = []
            var allDists: [Double] = []

            for _ in 0..<antCount {
                let route = buildRoute(n: n, pheromone: pheromone, dist: dist)
                let d = routeDistance(route, dist: dist)
                allRoutes.append(route)
                allDists.append(d)

                if d < globalBestDist {
                    globalBestDist = d
                    globalBestRoute = route
                }
            }

            for i in 0..<n {
                for j in 0..<n {
                    pheromone[i][j] *= (1.0 - evaporation)
                    if pheromone[i][j] < 0.001 { pheromone[i][j] = 0.001 }
                }
            }

            for k in 0..<antCount {
                let contribution = q / allDists[k]
                let route = allRoutes[k]
                for i in 0..<route.count {
                    let from = route[i]
                    let to = route[(i + 1) % route.count]
                    pheromone[from][to] += contribution
                    pheromone[to][from] += contribution
                }
            }

            let avgDist = allDists.reduce(0, +) / Double(allDists.count)

            if iter % 5 == 0 || iter == iterations - 1 {
                steps.append(AntStep(
                    iteration: iter,
                    bestDistance: globalBestDist,
                    bestRoute: globalBestRoute,
                    avgDistance: avgDist
                ))
            }
        }

        return AntResult(
            bestRoute: globalBestRoute,
            bestDistance: globalBestDist,
            steps: steps,
            pheromoneMatrix: pheromone,
            iterations: iterations
        )
    }

    private func buildRoute(n: Int, pheromone: [[Double]], dist: [[Double]]) -> [Int] {
        var visited = Set<Int>()
        let start = Int.random(in: 0..<n)
        var route = [start]
        visited.insert(start)

        for _ in 1..<n {
            let current = route.last!
            let next = selectNext(current: current, visited: visited,
                                  n: n, pheromone: pheromone, dist: dist)
            route.append(next)
            visited.insert(next)
        }

        return route
    }

    private func selectNext(current: Int, visited: Set<Int>,
                            n: Int, pheromone: [[Double]], dist: [[Double]]) -> Int {
        var probs: [(city: Int, prob: Double)] = []
        var total = 0.0

        for j in 0..<n {
            guard !visited.contains(j) else { continue }
            let tau = pow(pheromone[current][j], alpha)
            let eta = dist[current][j] > 0 ? pow(1.0 / dist[current][j], beta) : 1e10
            let p = tau * eta
            probs.append((city: j, prob: p))
            total += p
        }

        guard !probs.isEmpty else { return current }
        guard total > 0 else { return probs[0].city }

        var r = Double.random(in: 0..<total)
        for (city, prob) in probs {
            r -= prob
            if r <= 0 { return city }
        }

        return probs.last!.city
    }

    private func buildDistanceMatrix(cities: [AntCity]) -> [[Double]] {
        let n = cities.count
        var d = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in (i+1)..<n {
                let dx = cities[i].x - cities[j].x
                let dy = cities[i].y - cities[j].y
                let dist = sqrt(dx * dx + dy * dy)
                d[i][j] = dist
                d[j][i] = dist
            }
        }
        return d
    }

    private func routeDistance(_ route: [Int], dist: [[Double]]) -> Double {
        var total = 0.0
        for i in 0..<route.count {
            let from = route[i]
            let to = route[(i + 1) % route.count]
            total += dist[from][to]
        }
        return total
    }
}
