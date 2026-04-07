import Foundation

struct GeneticCity: Identifiable {
    let id: Int
    let name: String
    let x: Double
    let y: Double
}

struct SelectedDish: Identifiable, Hashable {
    let id: String
    let name: String
    let category: MenuItemCategory

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SelectedDish, rhs: SelectedDish) -> Bool { lhs.id == rhs.id }
}

struct RouteCandidate {
    let placeIndex: Int
    let place: FoodPlace
    let x: Double
    let y: Double
    let dishesOffered: Set<String>
    let closingMinutes: Double?
}

struct Individual: Identifiable {
    let id = UUID()
    var route: [Int]
    var fitness: Double = 0
}

struct GeneticStep: Identifiable {
    let id = UUID()
    let generation: Int
    let bestFitness: Double
    let bestRoute: [Int]
    let bestDistance: Double
    let bestTime: Double
    let coverage: Double
}

struct GeneticResult {
    let bestRoute: [Int]
    let bestDistance: Double
    let bestTime: Double
    let totalPlaces: Int
    let coveredDishes: Set<String>
    let missingDishes: Set<String>
    let steps: [GeneticStep]
    let generations: Int
}

final class GeneticAlgorithm {

    private let populationSize: Int
    private let mutationRate: Double
    private let eliteCount: Int
    private let metersPerPixel: Double
    private let walkingSpeedMps: Double

    init(populationSize: Int = 100,
         mutationRate: Double = 0.2,
         eliteCount: Int = 4,
         metersPerPixel: Double = 7.3) {
        self.populationSize = populationSize
        self.mutationRate   = mutationRate
        self.eliteCount     = eliteCount
        self.metersPerPixel = metersPerPixel
        self.walkingSpeedMps = 5000.0 / 3600.0
    }

    func run(candidates: [RouteCandidate],
             selectedDishes: Set<String>,
             startX: Double, startY: Double,
             generations: Int = 300,
             onGeneration: ((GeneticStep) -> Void)? = nil) -> GeneticResult {

        let n = candidates.count
        guard n >= 1 else {
            return GeneticResult(bestRoute: [], bestDistance: 0, bestTime: 0,
                                 totalPlaces: 0, coveredDishes: [],
                                 missingDishes: selectedDishes,
                                 steps: [], generations: 0)
        }

        let dist = buildDistMatrix(candidates: candidates, startX: startX, startY: startY)
        var population = initPopulation(n: n)
        var steps: [GeneticStep] = []
        var globalBestRoute: [Int] = []
        var globalBestFitness = -Double.infinity

        for gen in 0..<generations {

            evaluate(&population, candidates: candidates, selectedDishes: selectedDishes,
                     dist: dist, n: n)

            population.sort { $0.fitness > $1.fitness }

            let best = population[0]
            if best.fitness > globalBestFitness {
                globalBestFitness = best.fitness
                globalBestRoute = best.route
            }

            let decoded = decodeRoute(best.route, candidates: candidates,
                                       selectedDishes: selectedDishes)
            let totalDist = routeDistMeters(decoded, dist: dist)
            let totalTime = totalDist / walkingSpeedMps / 60.0
            let covered = coveredDishes(decoded, candidates: candidates,
                                         selectedDishes: selectedDishes)

            let step = GeneticStep(
                generation: gen,
                bestFitness: best.fitness,
                bestRoute: decoded,
                bestDistance: totalDist,
                bestTime: totalTime,
                coverage: selectedDishes.isEmpty ? 1.0 :
                    Double(covered.count) / Double(selectedDishes.count)
            )
            steps.append(step)
            onGeneration?(step)

            var newPop: [Individual] = []
            for i in 0..<min(eliteCount, population.count) {
                newPop.append(population[i])
            }

            while newPop.count < populationSize {
                let p1 = tournamentSelect(population)
                let p2 = tournamentSelect(population)
                var child = orderCrossover(p1.route, p2.route)
                if Double.random(in: 0...1) < mutationRate {
                    swapMutate(&child)
                }

                if Double.random(in: 0...1) < mutationRate * 0.5 {
                    insertMutate(&child, n: n)
                }
                newPop.append(Individual(route: child))
            }

            population = newPop
        }

        let decoded = decodeRoute(globalBestRoute, candidates: candidates,
                                   selectedDishes: selectedDishes)
        let totalDist = routeDistMeters(decoded, dist: dist)
        let totalTime = totalDist / walkingSpeedMps / 60.0
        let covered = coveredDishes(decoded, candidates: candidates,
                                     selectedDishes: selectedDishes)
        let missing = selectedDishes.subtracting(covered)

        return GeneticResult(
            bestRoute: decoded,
            bestDistance: totalDist,
            bestTime: totalTime,
            totalPlaces: decoded.count,
            coveredDishes: covered,
            missingDishes: missing,
            steps: steps,
            generations: generations
        )
    }


    private func decodeRoute(_ permutation: [Int],
                              candidates: [RouteCandidate],
                              selectedDishes: Set<String>) -> [Int] {
        var remaining = selectedDishes
        var route: [Int] = []

        for idx in permutation {
            guard idx < candidates.count else { continue }
            let candidate = candidates[idx]
            let contribution = remaining.intersection(candidate.dishesOffered)
            if !contribution.isEmpty {
                route.append(idx)
                remaining.subtract(contribution)
                if remaining.isEmpty { break }
            }
        }

        if !remaining.isEmpty {
            for idx in permutation where !route.contains(idx) {
                guard idx < candidates.count else { continue }
                let contribution = remaining.intersection(candidates[idx].dishesOffered)
                if !contribution.isEmpty {
                    route.append(idx)
                    remaining.subtract(contribution)
                    if remaining.isEmpty { break }
                }
            }
        }

        return route
    }

    private func coveredDishes(_ route: [Int],
                                candidates: [RouteCandidate],
                                selectedDishes: Set<String>) -> Set<String> {
        var covered = Set<String>()
        for idx in route {
            guard idx < candidates.count else { continue }
            covered.formUnion(candidates[idx].dishesOffered.intersection(selectedDishes))
        }
        return covered
    }


    private func buildDistMatrix(candidates: [RouteCandidate],
                                  startX: Double, startY: Double) -> [[Double]] {
        let n = candidates.count + 1
        var d = Array(repeating: Array(repeating: 0.0, count: n), count: n)

        for i in 0..<candidates.count {
            let dx = startX - candidates[i].x
            let dy = startY - candidates[i].y
            let pixDist = sqrt(dx * dx + dy * dy)
            let meters = pixDist * metersPerPixel
            d[0][i + 1] = meters
            d[i + 1][0] = meters
        }

        for i in 0..<candidates.count {
            for j in (i+1)..<candidates.count {
                let dx = candidates[i].x - candidates[j].x
                let dy = candidates[i].y - candidates[j].y
                let pixDist = sqrt(dx * dx + dy * dy)
                let meters = pixDist * metersPerPixel
                d[i + 1][j + 1] = meters
                d[j + 1][i + 1] = meters
            }
        }
        return d
    }

    private func routeDistMeters(_ route: [Int], dist: [[Double]]) -> Double {
        guard !route.isEmpty else { return 0 }
        var total = dist[0][route[0] + 1]
        for i in 1..<route.count {
            total += dist[route[i-1] + 1][route[i] + 1]
        }
        return total
    }

    private func evaluate(_ pop: inout [Individual],
                           candidates: [RouteCandidate],
                           selectedDishes: Set<String>,
                           dist: [[Double]], n: Int) {
        for i in pop.indices {
            let decoded = decodeRoute(pop[i].route, candidates: candidates,
                                       selectedDishes: selectedDishes)
            let totalDist = routeDistMeters(decoded, dist: dist)
            let totalTimeSec = totalDist / walkingSpeedMps
            let covered = coveredDishes(decoded, candidates: candidates,
                                         selectedDishes: selectedDishes)

            var penalty = 0.0

            let uncovered = selectedDishes.count - covered.count
            penalty += Double(uncovered) * 10000.0

            penalty += Double(decoded.count) * 50.0

            var cumulativeTimeSec = 0.0
            var prevIdx = -1
            for (step, candIdx) in decoded.enumerated() {
                guard candIdx < candidates.count else { continue }
                let d: Double
                if step == 0 {
                    d = dist[0][candIdx + 1]
                } else {
                    d = dist[prevIdx + 1][candIdx + 1]
                }
                cumulativeTimeSec += d / walkingSpeedMps

                if let closingMin = candidates[candIdx].closingMinutes {
                    let arrivalMin = cumulativeTimeSec / 60.0
                    if arrivalMin > closingMin {

                        penalty += 5000.0
                    } else if closingMin - arrivalMin < 15 {

                        penalty += (15 - (closingMin - arrivalMin)) * 20.0
                    }
                }
                prevIdx = candIdx
            }

            let score = 100000.0 / (1.0 + totalDist + penalty)
            pop[i].fitness = score
        }
    }

    private func initPopulation(n: Int) -> [Individual] {
        let base = Array(0..<n)
        return (0..<populationSize).map { _ in
            Individual(route: base.shuffled())
        }
    }

    private func tournamentSelect(_ pop: [Individual], size: Int = 5) -> Individual {
        let candidates = (0..<size).map { _ in pop.randomElement()! }
        return candidates.max(by: { $0.fitness < $1.fitness })!
    }

    private func orderCrossover(_ p1: [Int], _ p2: [Int]) -> [Int] {
        let n = p1.count
        guard n > 2 else { return p1 }

        let start = Int.random(in: 0..<n)
        let end   = Int.random(in: start..<n)

        var child = Array(repeating: -1, count: n)
        let segment = Set(p1[start...end])

        for i in start...end {
            child[i] = p1[i]
        }

        var pos = (end + 1) % n
        var p2pos = (end + 1) % n
        while child.contains(-1) {
            if !segment.contains(p2[p2pos]) {
                child[pos] = p2[p2pos]
                pos = (pos + 1) % n
            }
            p2pos = (p2pos + 1) % n
        }

        return child
    }

    private func swapMutate(_ route: inout [Int]) {
        guard route.count > 1 else { return }
        let i = Int.random(in: 0..<route.count)
        var j = Int.random(in: 0..<route.count)
        while j == i { j = Int.random(in: 0..<route.count) }
        route.swapAt(i, j)
    }

    private func insertMutate(_ route: inout [Int], n: Int) {
        guard route.count > 1 else { return }
        let i = Int.random(in: 0..<route.count)
        let elem = route.remove(at: i)
        let j = Int.random(in: 0...route.count)
        route.insert(elem, at: j)
    }
}
