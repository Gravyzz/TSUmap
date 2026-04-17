import Foundation


struct TrainingSample: Identifiable {
    let id = UUID()
    let features: [String: String]
    let label: String
}

struct FeatureSchema {
    let name: String
    let title: String
    let icon: String
    let values: [String]
    let valueLabels: [String: String]
}


final class DTNode: Identifiable {
    let id = UUID()
    let sampleCount: Int
    let entropy: Double
    let majorityLabel: String
    let labelCounts: [String: Int]
    let type: DTNodeType

    init(sampleCount: Int, entropy: Double,
         majorityLabel: String, labelCounts: [String: Int],
         type: DTNodeType) {
        self.sampleCount = sampleCount
        self.entropy = entropy
        self.majorityLabel = majorityLabel
        self.labelCounts = labelCounts
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

    var nodeCount: Int {
        switch type {
        case .leaf: return 1
        case .split(_, _, let children):
            return 1 + children.reduce(0) { $0 + $1.node.nodeCount }
        }
    }

    var leafCount: Int {
        switch type {
        case .leaf: return 1
        case .split(_, _, let children):
            return children.reduce(0) { $0 + $1.node.leafCount }
        }
    }
}

indirect enum DTNodeType {
    case leaf
    case split(featureName: String,
               gain: Double,
               children: [(value: String, node: DTNode)])
}



struct CSVParseResult {
    let samples: [TrainingSample]
    let featureNames: [String]
    let labelName: String
    let featureValues: [String: [String]]
    let labels: [String]
    let errors: [String]
}

enum CSVParser {
    static func parse(text: String) -> CSVParseResult {
        var errors: [String] = []
        let lines = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard lines.count >= 2 else {
            return CSVParseResult(samples: [], featureNames: [],
                                  labelName: "", featureValues: [:],
                                  labels: [],
                                  errors: ["Нужен заголовок и минимум 1 строка данных"])
        }

        let header = splitLine(lines[0])
        guard header.count >= 2 else {
            return CSVParseResult(samples: [], featureNames: [],
                                  labelName: "", featureValues: [:],
                                  labels: [],
                                  errors: ["В заголовке должно быть ≥ 2 колонок"])
        }

        let featureNames = Array(header.dropLast())
        let labelName = header.last!

        var samples: [TrainingSample] = []
        var featureValues: [String: Set<String>] = [:]
        var labelSet: Set<String> = []

        for (i, line) in lines.dropFirst().enumerated() {
            let parts = splitLine(line)
            if parts.count != header.count {
                errors.append("Строка \(i + 2): ожидалось \(header.count) значений, получено \(parts.count)")
                continue
            }
            var dict: [String: String] = [:]
            for (j, name) in featureNames.enumerated() {
                let v = parts[j]
                dict[name] = v
                featureValues[name, default: []].insert(v)
            }
            let label = parts[header.count - 1]
            labelSet.insert(label)
            samples.append(TrainingSample(features: dict, label: label))
        }

        let ordered = featureValues.mapValues { Array($0).sorted() }
        return CSVParseResult(samples: samples,
                              featureNames: featureNames,
                              labelName: labelName,
                              featureValues: ordered,
                              labels: Array(labelSet).sorted(),
                              errors: errors)
    }

    private static func splitLine(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}


struct DTBuildStep {
    let depth: Int
    let sampleCount: Int
    let entropy: Double
    let gains: [(feature: String, gain: Double)]
    let chosen: String?
    let description: String
}

final class DecisionTreeBuilder {
    private(set) var steps: [DTBuildStep] = []

    var maxDepth: Int = 6
    var minSamplesLeaf: Int = 1
    var minInfoGain: Double = 0.001

    func build(samples: [TrainingSample],
               featureNames: [String]) -> DTNode {
        steps = []
        return build(samples: samples, features: featureNames, depth: 0)
    }

    private func build(samples: [TrainingSample],
                       features: [String],
                       depth: Int) -> DTNode {
        let ent = entropy(samples)
        let counts = labelCounts(samples)
        let majority = counts.max(by: { $0.value < $1.value })?.key ?? "—"

        let stop = samples.count <= minSamplesLeaf
            || features.isEmpty
            || ent < 0.001
            || depth >= maxDepth

        if stop {
            steps.append(DTBuildStep(depth: depth,
                                     sampleCount: samples.count,
                                     entropy: ent, gains: [], chosen: nil,
                                     description: "Лист: \(samples.count) записей → «\(majority)»"))
            return DTNode(sampleCount: samples.count, entropy: ent,
                          majorityLabel: majority,
                          labelCounts: counts, type: .leaf)
        }

        let gains: [(String, Double)] = features.map { f in
            (f, informationGain(samples: samples, feature: f))
        }

        guard let best = gains.max(by: { $0.1 < $1.1 }), best.1 > minInfoGain else {
            steps.append(DTBuildStep(depth: depth,
                                     sampleCount: samples.count,
                                     entropy: ent,
                                     gains: gains.map { (feature: $0.0, gain: $0.1) },
                                     chosen: nil,
                                     description: "Лист: нет значимого прироста"))
            return DTNode(sampleCount: samples.count, entropy: ent,
                          majorityLabel: majority,
                          labelCounts: counts, type: .leaf)
        }

        let groups = Dictionary(grouping: samples) { $0.features[best.0] ?? "?" }
        let remaining = features.filter { $0 != best.0 }
        let sortedKeys = groups.keys.sorted()

        let children: [(String, DTNode)] = sortedKeys.map { key in
            (key, build(samples: groups[key]!, features: remaining, depth: depth + 1))
        }

        steps.append(DTBuildStep(depth: depth,
                                 sampleCount: samples.count,
                                 entropy: ent,
                                 gains: gains.map { (feature: $0.0, gain: $0.1) },
                                 chosen: best.0,
                                 description: "Ветвление по «\(best.0)», IG=\(String(format: "%.3f", best.1))"))

        return DTNode(sampleCount: samples.count, entropy: ent,
                      majorityLabel: majority,
                      labelCounts: counts,
                      type: .split(featureName: best.0, gain: best.1,
                                   children: children.map { (value: $0.0, node: $0.1) }))
    }

    func prune(_ root: DTNode, minGain: Double) -> DTNode {
        switch root.type {
        case .leaf:
            return root
        case .split(let feature, let gain, let children):
            let pruned = children.map { (v, c) -> (String, DTNode) in
                (v, prune(c, minGain: minGain))
            }
            let allLeavesSameMajority = pruned.allSatisfy { (_, c) in
                c.isLeaf && c.majorityLabel == root.majorityLabel
            }
            if allLeavesSameMajority || gain < minGain {
                return DTNode(sampleCount: root.sampleCount,
                              entropy: root.entropy,
                              majorityLabel: root.majorityLabel,
                              labelCounts: root.labelCounts, type: .leaf)
            }
            return DTNode(sampleCount: root.sampleCount,
                          entropy: root.entropy,
                          majorityLabel: root.majorityLabel,
                          labelCounts: root.labelCounts,
                          type: .split(featureName: feature, gain: gain,
                                       children: pruned.map { (value: $0.0, node: $0.1) }))
        }
    }


    func entropy(_ samples: [TrainingSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let counts = labelCounts(samples)
        let total = Double(samples.count)
        var h = 0.0
        for (_, c) in counts {
            let p = Double(c) / total
            if p > 0 { h -= p * log2(p) }
        }
        return h
    }

    func informationGain(samples: [TrainingSample], feature: String) -> Double {
        let total = Double(samples.count)
        let h = entropy(samples)
        let groups = Dictionary(grouping: samples) { $0.features[feature] ?? "?" }
        var weighted = 0.0
        for (_, group) in groups {
            weighted += (Double(group.count) / total) * entropy(group)
        }
        return h - weighted
    }

    func labelCounts(_ samples: [TrainingSample]) -> [String: Int] {
        var d: [String: Int] = [:]
        for s in samples { d[s.label, default: 0] += 1 }
        return d
    }

    func trainingAccuracy(tree: DTNode, samples: [TrainingSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var correct = 0
        for s in samples {
            let pred = DecisionTreePredictor.predict(tree: tree, query: s.features)
            if pred.label == s.label { correct += 1 }
        }
        return Double(correct) / Double(samples.count)
    }
}


struct PredictionStep {
    let nodeId: UUID
    let childId: UUID
    let feature: String
    let value: String
}

struct PredictionResult {
    let label: String
    let path: [PredictionStep]
    let leafId: UUID
    let leafDistribution: [String: Int]
    let confidence: Double
    let unknownBranch: Bool
}

enum DecisionTreePredictor {
    static func predict(tree: DTNode, query: [String: String]) -> PredictionResult {
        var node = tree
        var path: [PredictionStep] = []
        var unknown = false

        while true {
            switch node.type {
            case .leaf:
                let total = node.labelCounts.values.reduce(0, +)
                let conf = total > 0
                    ? Double(node.labelCounts[node.majorityLabel] ?? 0) / Double(total)
                    : 0
                return PredictionResult(label: node.majorityLabel,
                                        path: path,
                                        leafId: node.id,
                                        leafDistribution: node.labelCounts,
                                        confidence: conf,
                                        unknownBranch: unknown)
            case .split(let feature, _, let children):
                let value = query[feature] ?? ""
                let chosen: DTNode
                if let match = children.first(where: { $0.value == value }) {
                    chosen = match.node
                    path.append(PredictionStep(nodeId: node.id, childId: chosen.id,
                                               feature: feature, value: value))
                } else {
                    unknown = true
                    guard let best = children.max(by: { $0.node.sampleCount < $1.node.sampleCount }) else {
                        return PredictionResult(label: node.majorityLabel,
                                                path: path,
                                                leafId: node.id,
                                                leafDistribution: node.labelCounts,
                                                confidence: 0.0,
                                                unknownBranch: true)
                    }
                    chosen = best.node
                    path.append(PredictionStep(nodeId: node.id, childId: chosen.id,
                                               feature: feature,
                                               value: value.isEmpty ? "—" : value))
                }
                node = chosen
            }
        }
    }
}

enum DecisionTreeDefaults {
    static let spec: [FeatureSchema] = [
        FeatureSchema(name: "location", title: "Где находится",
                      icon: "location.fill",
                      values: ["main_building", "second_building",
                               "bus_stop", "campus_center", "off_campus"],
                      valueLabels: [
                        "main_building": "Главный корпус",
                        "second_building": "2-й корпус",
                        "bus_stop": "Остановка",
                        "campus_center": "Центр кампуса",
                        "off_campus": "Вне кампуса"
                      ]),
        FeatureSchema(name: "budget", title: "Бюджет",
                      icon: "rublesign.circle.fill",
                      values: ["low", "medium", "high"],
                      valueLabels: ["low": "Низкий", "medium": "Средний", "high": "Высокий"]),
        FeatureSchema(name: "time_available", title: "Сколько времени",
                      icon: "clock.fill",
                      values: ["very_short", "short", "medium"],
                      valueLabels: [
                        "very_short": "Очень мало",
                        "short": "Мало",
                        "medium": "Средне"
                      ]),
        FeatureSchema(name: "food_type", title: "Что хочется",
                      icon: "fork.knife",
                      values: ["coffee", "pancakes", "full_meal", "snack"],
                      valueLabels: [
                        "coffee": "Кофе",
                        "pancakes": "Блинчики",
                        "full_meal": "Полноценно",
                        "snack": "Перекус"
                      ]),
        FeatureSchema(name: "queue_tolerance", title: "Готов ждать очередь",
                      icon: "person.2.wave.2.fill",
                      values: ["low", "medium", "high"],
                      valueLabels: ["low": "Нет", "medium": "Средне", "high": "Да"]),
        FeatureSchema(name: "weather", title: "Погода",
                      icon: "cloud.sun.fill",
                      values: ["good", "bad"],
                      valueLabels: ["good": "Хорошая", "bad": "Плохая"])
    ]

    static let sampleCSV: String = """
location,budget,time_available,food_type,queue_tolerance,weather,recommended_place
main_building,low,very_short,snack,low,bad,Автомат (Главный корпус)
main_building,low,very_short,snack,low,good,Автомат (Главный корпус)
main_building,low,very_short,snack,medium,bad,Автомат (Главный корпус)
main_building,low,very_short,snack,medium,good,Автомат (Главный корпус)
main_building,medium,short,pancakes,low,good,Сибирские блины
main_building,medium,short,pancakes,medium,good,Сибирские блины
main_building,medium,short,pancakes,high,good,Сибирские блины
main_building,medium,short,pancakes,medium,bad,Сибирские блины
main_building,low,medium,full_meal,high,good,Столовая ТГУ
main_building,low,medium,full_meal,medium,bad,Столовая ТГУ
main_building,low,medium,full_meal,medium,good,Столовая ТГУ
main_building,medium,medium,full_meal,high,bad,Столовая ТГУ
main_building,low,short,snack,low,good,Автомат (Главный корпус)
main_building,medium,short,coffee,low,good,Сибирские блины
main_building,medium,medium,coffee,low,good,Сибирские блины
second_building,low,very_short,snack,low,bad,Автомат (2-й корпус)
second_building,low,very_short,snack,low,good,Автомат (2-й корпус)
second_building,low,very_short,snack,medium,bad,Автомат (2-й корпус)
second_building,low,short,snack,low,good,Буфет (2-й корпус)
second_building,low,short,snack,medium,good,Буфет (2-й корпус)
second_building,low,short,snack,medium,bad,Буфет (2-й корпус)
second_building,medium,short,coffee,medium,good,Буфет (2-й корпус)
second_building,medium,medium,full_meal,medium,good,Кафе (2-й корпус)
second_building,medium,medium,full_meal,high,good,Кафе (2-й корпус)
second_building,medium,medium,full_meal,medium,bad,Кафе (2-й корпус)
second_building,medium,medium,pancakes,medium,good,Кафе (2-й корпус)
second_building,low,medium,full_meal,high,bad,Столовая ТГУ
second_building,low,medium,full_meal,high,good,Столовая ТГУ
campus_center,low,very_short,snack,low,bad,Автомат (Главный корпус)
campus_center,low,very_short,snack,medium,good,Автомат (Главный корпус)
campus_center,low,short,pancakes,low,good,Сибирские блины
campus_center,low,short,pancakes,medium,good,Сибирские блины
campus_center,medium,short,pancakes,medium,bad,Сибирские блины
campus_center,low,medium,full_meal,high,good,Столовая ТГУ
campus_center,low,medium,full_meal,medium,good,Столовая ТГУ
campus_center,low,medium,full_meal,medium,bad,Столовая ТГУ
campus_center,medium,short,coffee,low,good,Сибирские блины
campus_center,low,short,snack,medium,good,Буфет (2-й корпус)
bus_stop,low,very_short,snack,low,bad,Автомат (Главный корпус)
bus_stop,low,very_short,snack,low,good,Автомат (Главный корпус)
bus_stop,low,short,pancakes,medium,good,Сибирские блины
bus_stop,low,short,pancakes,low,good,Сибирские блины
bus_stop,medium,short,coffee,low,good,Сибирские блины
bus_stop,low,medium,full_meal,high,good,Столовая ТГУ
bus_stop,low,medium,full_meal,medium,good,Столовая ТГУ
bus_stop,low,medium,full_meal,medium,bad,Столовая ТГУ
off_campus,medium,short,coffee,low,good,Baba Roma
off_campus,medium,short,coffee,medium,good,Baba Roma
off_campus,high,short,coffee,low,good,Территория Кофе
off_campus,high,short,coffee,medium,good,Территория Кофе
off_campus,high,medium,coffee,low,good,Территория Кофе
off_campus,medium,short,pancakes,medium,good,Багет Омлет
off_campus,high,short,pancakes,low,good,Багет Омлет
off_campus,high,medium,pancakes,medium,good,Багет Омлет
off_campus,medium,short,snack,medium,good,Наш Гастроном
off_campus,low,short,snack,low,good,Абрикос
off_campus,medium,short,snack,low,good,Наш Гастроном
off_campus,high,medium,full_meal,medium,good,Rostic's
off_campus,high,medium,full_meal,high,good,Rostic's
off_campus,high,short,full_meal,medium,bad,Rostic's
off_campus,medium,medium,full_meal,medium,good,Сып-Бор
off_campus,medium,medium,full_meal,high,good,Сып-Бор
off_campus,medium,medium,full_meal,medium,bad,Сып-Бор
off_campus,medium,medium,full_meal,high,good,Укромное местечко
off_campus,medium,medium,full_meal,medium,good,Укромное местечко
off_campus,low,medium,full_meal,high,good,Столовая НИ ТПУ
off_campus,low,medium,full_meal,medium,good,Столовая НИ ТПУ
off_campus,high,medium,full_meal,high,good,Лампочка
off_campus,high,medium,full_meal,medium,good,Лампочка
off_campus,high,medium,full_meal,high,bad,Лампочка
"""

    static func schema(for featureName: String,
                       parsed values: [String]? = nil) -> FeatureSchema {
        if let spec = spec.first(where: { $0.name == featureName }) {
            return spec
        }
        let vs = values ?? []
        return FeatureSchema(name: featureName,
                             title: featureName,
                             icon: "questionmark.circle",
                             values: vs,
                             valueLabels: Dictionary(uniqueKeysWithValues: vs.map { ($0, $0) }))
    }
}
