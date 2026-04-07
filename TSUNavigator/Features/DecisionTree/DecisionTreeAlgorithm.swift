import Foundation

enum PlaceFeature: String, CaseIterable, Identifiable {
    case budget
    case hotFood
    case coffee
    case quickService
    case fullMeal
    case weekends

    var id: String { rawValue }

    var question: String {
        switch self {
        case .budget:       return "Какой у вас бюджет?"
        case .hotFood:      return "Нужна горячая еда?"
        case .coffee:       return "Хотите кофе?"
        case .quickService: return "Нужно быстро перекусить?"
        case .fullMeal:     return "Хотите полноценный обед?"
        case .weekends:     return "Ищете место на выходные?"
        }
    }

    var icon: String {
        switch self {
        case .budget:       return "rublesign.circle"
        case .hotFood:      return "flame"
        case .coffee:       return "cup.and.saucer.fill"
        case .quickService: return "bolt"
        case .fullMeal:     return "fork.knife"
        case .weekends:     return "calendar"
        }
    }

    func extract(from place: FoodPlace) -> String {
        switch self {
        case .budget:
            return place.priceLevel.label
        case .hotFood:
            let has = place.menu.contains { $0.category == .hotMeal || $0.category == .soup }
            return has ? "Да" : "Нет"
        case .coffee:
            let has = place.menu.contains { $0.category == .coffee }
            return has ? "Да" : "Нет"
        case .quickService:
            let quick: Set<PlaceCategory> = [.vending, .buffet, .fastfood, .shop]
            return quick.contains(place.category) ? "Да" : "Нет"
        case .fullMeal:
            let cats = Set(place.menu.map { $0.category })
            let has = cats.contains(.hotMeal) && (cats.contains(.salad) || cats.contains(.soup))
            return has ? "Да" : "Нет"
        case .weekends:
            if let note = place.schedule.note {
                let lower = note.lowercased()
                return (lower.contains("ежедневно") || lower.contains("круглосуточно")) ? "Да" : "Нет"
            }
            return place.schedule.weekends != nil ? "Да" : "Нет"
        }
    }

    var possibleAnswers: [String] {
        switch self {
        case .budget: return [PriceLevel.low.label, PriceLevel.medium.label, PriceLevel.high.label]
        default:      return ["Да", "Нет"]
        }
    }
}

final class DecisionTreeNode: Identifiable {
    let id = UUID()
    let entropy: Double
    let sampleCount: Int
    let samples: [FoodPlace]

    enum NodeType {
        case leaf
        case split(feature: PlaceFeature, gain: Double,
                   children: [(value: String, node: DecisionTreeNode)])
    }

    let type: NodeType

    init(entropy: Double, samples: [FoodPlace], type: NodeType) {
        self.entropy = entropy
        self.sampleCount = samples.count
        self.samples = samples
        self.type = type
    }

    var isLeaf: Bool {
        if case .leaf = type { return true }
        return false
    }

    var depth: Int {
        switch type {
        case .leaf: return 0
        case .split(_, _, let children):
            return 1 + (children.map { $0.node.depth }.max() ?? 0)
        }
    }

    var totalNodes: Int {
        switch type {
        case .leaf: return 1
        case .split(_, _, let children):
            return 1 + children.reduce(0) { $0 + $1.node.totalNodes }
        }
    }
}

struct TreeBuildStep: Identifiable {
    let id = UUID()
    let depth: Int
    let sampleCount: Int
    let entropy: Double
    let featureGains: [(feature: PlaceFeature, gain: Double)]
    let chosen: PlaceFeature?
    let description: String
}

final class DecisionTreeBuilder {
    private(set) var buildSteps: [TreeBuildStep] = []
    private let minSamplesLeaf: Int

    init(minSamplesLeaf: Int = 2) {
        self.minSamplesLeaf = minSamplesLeaf
    }

    func buildTree(places: [FoodPlace],
                   features: [PlaceFeature] = PlaceFeature.allCases) -> DecisionTreeNode {
        buildSteps = []
        return build(places: places, features: features, depth: 0)
    }

    private func build(places: [FoodPlace],
                       features: [PlaceFeature],
                       depth: Int) -> DecisionTreeNode {
        let ent = entropy(places)

        if places.count <= minSamplesLeaf || features.isEmpty || ent < 0.001 {
            buildSteps.append(TreeBuildStep(
                depth: depth, sampleCount: places.count, entropy: ent,
                featureGains: [], chosen: nil,
                description: "Лист: \(places.count) мест, H=\(String(format: "%.3f", ent))"
            ))
            return DecisionTreeNode(entropy: ent, samples: places, type: .leaf)
        }

        let gains: [(PlaceFeature, Double)] = features.map { f in
            (f, informationGain(places: places, feature: f))
        }

        guard let best = gains.max(by: { $0.1 < $1.1 }), best.1 > 0.001 else {
            buildSteps.append(TreeBuildStep(
                depth: depth, sampleCount: places.count, entropy: ent,
                featureGains: gains.map { (feature: $0.0, gain: $0.1) },
                chosen: nil,
                description: "Лист: нет значимого gain"
            ))
            return DecisionTreeNode(entropy: ent, samples: places, type: .leaf)
        }

        buildSteps.append(TreeBuildStep(
            depth: depth, sampleCount: places.count, entropy: ent,
            featureGains: gains.map { (feature: $0.0, gain: $0.1) },
            chosen: best.0,
            description: "Разбиение по «\(best.0.question)», IG=\(String(format: "%.3f", best.1))"
        ))

        let groups = Dictionary(grouping: places) { best.0.extract(from: $0) }
        let remaining = features.filter { $0 != best.0 }

        let orderedKeys = best.0.possibleAnswers.filter { groups[$0] != nil }
        let children: [(String, DecisionTreeNode)] = orderedKeys.map { key in
            let child = build(places: groups[key]!, features: remaining, depth: depth + 1)
            return (key, child)
        }

        return DecisionTreeNode(
            entropy: ent, samples: places,
            type: .split(feature: best.0, gain: best.1,
                         children: children.map { (value: $0.0, node: $0.1) })
        )
    }

    func entropy(_ places: [FoodPlace]) -> Double {
        guard !places.isEmpty else { return 0 }
        let groups = Dictionary(grouping: places) { $0.category.rawValue }
        let total = Double(places.count)
        var h = 0.0
        for (_, group) in groups {
            let p = Double(group.count) / total
            if p > 0 { h -= p * log2(p) }
        }
        return h
    }

    func informationGain(places: [FoodPlace], feature: PlaceFeature) -> Double {
        let totalH = entropy(places)
        let groups = Dictionary(grouping: places) { feature.extract(from: $0) }
        let total = Double(places.count)
        var weightedH = 0.0
        for (_, group) in groups {
            weightedH += (Double(group.count) / total) * entropy(group)
        }
        return totalH - weightedH
    }
}
