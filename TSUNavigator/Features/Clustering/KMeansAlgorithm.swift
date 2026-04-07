import Foundation

enum DistanceMetric: String, CaseIterable, Identifiable {
    case euclidean  = "Евклидово"
    case manhattan  = "Манхэттен"

    var id: String { rawValue }
}

struct ClusterPoint: Identifiable {
    let id: UUID
    var x: Double
    var y: Double
    var cluster: Int = -1

    init(x: Double, y: Double) {
        self.id = UUID()
        self.x = x
        self.y = y
    }
}

struct Centroid: Identifiable {
    let id: Int
    var x: Double
    var y: Double
}

struct KMeansStep: Identifiable {
    let id = UUID()
    let iteration: Int
    let phase: StepPhase
    let centroids: [Centroid]
    let points: [ClusterPoint]
    let description: String

    enum StepPhase: String {
        case initial    = "Инициализация"
        case assign     = "Назначение"
        case update     = "Обновление центроидов"
        case converged  = "Сходимость"
    }
}

struct KMeansResult {
    let points: [ClusterPoint]
    let centroids: [Centroid]
    let steps: [KMeansStep]
    let iterations: Int
    let k: Int
    let wcss: Double
    let metric: DistanceMetric
}

struct MetricComparison {
    let euclidean: KMeansResult
    let manhattan: KMeansResult

    let conflictIndices: Set<Int>

    let conflicts: [(index: Int, eucCluster: Int, manCluster: Int)]
}

final class KMeansAlgorithm {

    func run(points inputPoints: [ClusterPoint], k: Int,
             metric: DistanceMetric = .euclidean,
             maxIterations: Int = 50) -> KMeansResult {
        guard inputPoints.count >= k, k > 0 else {
            return KMeansResult(points: inputPoints, centroids: [], steps: [],
                                iterations: 0, k: k, wcss: 0, metric: metric)
        }

        var points = inputPoints
        var steps: [KMeansStep] = []

        var centroids = initKMeansPP(points: points, k: k, metric: metric)

        steps.append(KMeansStep(
            iteration: 0, phase: .initial,
            centroids: centroids, points: points,
            description: "Начальные центроиды (K-Means++)"
        ))

        var iteration = 0
        var converged = false

        while iteration < maxIterations && !converged {
            iteration += 1

            for i in points.indices {
                points[i].cluster = nearest(point: points[i], centroids: centroids, metric: metric)
            }
            steps.append(KMeansStep(
                iteration: iteration, phase: .assign,
                centroids: centroids, points: points,
                description: "Итерация \(iteration): назначение (\(metric.rawValue))"
            ))

            let old = centroids
            centroids = update(points: points, k: k, old: centroids)
            converged = hasConverged(old: old, new: centroids)

            steps.append(KMeansStep(
                iteration: iteration,
                phase: converged ? .converged : .update,
                centroids: centroids, points: points,
                description: converged
                    ? "Сходимость на итерации \(iteration)"
                    : "Итерация \(iteration): центроиды сдвинулись"
            ))
        }

        let wcss = computeWCSS(points: points, centroids: centroids, metric: metric)
        return KMeansResult(points: points, centroids: centroids,
                            steps: steps, iterations: iteration,
                            k: k, wcss: wcss, metric: metric)
    }

    func compare(points: [ClusterPoint], k: Int) -> MetricComparison {
        let eucResult = run(points: points, k: k, metric: .euclidean)

        let manResult = run(points: points, k: k, metric: .manhattan)



        let mapping = mapClusters(from: manResult.points, to: eucResult.points, k: k)
        let remappedMan = manResult.points.map { p -> ClusterPoint in
            var mp = p
            mp.cluster = mapping[p.cluster] ?? p.cluster
            return mp
        }

        var conflictIndices = Set<Int>()
        var conflicts: [(index: Int, eucCluster: Int, manCluster: Int)] = []

        for i in eucResult.points.indices {
            let ec = eucResult.points[i].cluster
            let mc = remappedMan[i].cluster
            if ec != mc {
                conflictIndices.insert(i)
                conflicts.append((index: i, eucCluster: ec, manCluster: mc))
            }
        }

        let remappedResult = KMeansResult(
            points: remappedMan,
            centroids: manResult.centroids,
            steps: manResult.steps,
            iterations: manResult.iterations,
            k: k, wcss: manResult.wcss, metric: .manhattan
        )

        return MetricComparison(
            euclidean: eucResult,
            manhattan: remappedResult,
            conflictIndices: conflictIndices,
            conflicts: conflicts
        )
    }

    private func mapClusters(from src: [ClusterPoint], to dst: [ClusterPoint], k: Int) -> [Int: Int] {
        var mapping: [Int: Int] = [:]
        var usedDst = Set<Int>()

        for srcC in 0..<k {
            let srcIndices = Set(src.indices.filter { src[$0].cluster == srcC })
            var bestDstC = 0
            var bestOverlap = 0

            for dstC in 0..<k where !usedDst.contains(dstC) {
                let dstIndices = Set(dst.indices.filter { dst[$0].cluster == dstC })
                let overlap = srcIndices.intersection(dstIndices).count
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestDstC = dstC
                }
            }
            mapping[srcC] = bestDstC
            usedDst.insert(bestDstC)
        }

        return mapping
    }

    private func dist(_ p: ClusterPoint, _ c: Centroid, metric: DistanceMetric) -> Double {
        switch metric {
        case .euclidean:
            let dx = p.x - c.x; let dy = p.y - c.y
            return dx * dx + dy * dy
        case .manhattan:
            return abs(p.x - c.x) + abs(p.y - c.y)
        }
    }

    private func initKMeansPP(points: [ClusterPoint], k: Int, metric: DistanceMetric) -> [Centroid] {
        var centroids: [Centroid] = []
        let first = points.randomElement()!
        centroids.append(Centroid(id: 0, x: first.x, y: first.y))

        for i in 1..<k {
            let dists = points.map { p in centroids.map { c in dist(p, c, metric: metric) }.min()! }
            let total = dists.reduce(0, +)
            guard total > 0 else { break }

            var r = Double.random(in: 0..<total)
            var chosen = 0
            for (idx, d) in dists.enumerated() {
                r -= d
                if r <= 0 { chosen = idx; break }
            }
            centroids.append(Centroid(id: i, x: points[chosen].x, y: points[chosen].y))
        }
        return centroids
    }

    private func nearest(point: ClusterPoint, centroids: [Centroid], metric: DistanceMetric) -> Int {
        var best = 0; var bestD = Double.infinity
        for c in centroids {
            let d = dist(point, c, metric: metric)
            if d < bestD { bestD = d; best = c.id }
        }
        return best
    }

    private func update(points: [ClusterPoint], k: Int, old: [Centroid]) -> [Centroid] {
        (0..<k).map { i in
            let members = points.filter { $0.cluster == i }
            if members.isEmpty { return old[i] }
            return Centroid(id: i,
                            x: members.map(\.x).reduce(0, +) / Double(members.count),
                            y: members.map(\.y).reduce(0, +) / Double(members.count))
        }
    }

    private func hasConverged(old: [Centroid], new: [Centroid]) -> Bool {
        for (o, n) in zip(old, new) {
            let dx = o.x - n.x
            let dy = o.y - n.y
            if dx * dx + dy * dy > 1e-6 { return false }
        }
        return true
    }

    private func computeWCSS(points: [ClusterPoint], centroids: [Centroid], metric: DistanceMetric) -> Double {
        points.reduce(0) { sum, p in
            guard let c = centroids.first(where: { $0.id == p.cluster }) else { return sum }
            return sum + dist(p, c, metric: metric)
        }
    }
}
