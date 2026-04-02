import SwiftUI

struct DecisionTreeView: View {
    let places: [FoodPlace]

    @State private var mode = 0
    @State private var tree: DecisionTreeNode?
    @State private var buildSteps: [TreeBuildStep] = []
    @State private var builder = DecisionTreeBuilder()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Режим", selection: $mode) {
                    Text("Подбор").tag(0)
                    Text("Дерево").tag(1)
                    Text("Алгоритм").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if let tree = tree {
                    switch mode {
                    case 0:  WizardView(root: tree)
                    case 1:  TreeDiagramView(root: tree)
                    default: AlgorithmStepsView(steps: buildSteps, builder: builder, places: places)
                    }
                } else {
                    ProgressView("Строим дерево...")
                }
            }
            .navigationTitle("Советник")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { buildTreeIfNeeded() }
        }
    }

    private func buildTreeIfNeeded() {
        guard tree == nil else { return }
        let root = builder.buildTree(places: places)
        buildSteps = builder.buildSteps
        tree = root
    }
}


private struct WizardView: View {
    let root: DecisionTreeNode
    @State private var path: [DecisionTreeNode] = []
    @State private var answers: [(question: String, answer: String)] = []

    private var current: DecisionTreeNode {
        path.last ?? root
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !answers.isEmpty {
                    AnswerHistoryView(answers: answers, onReset: reset, onBack: goBack)
                }

                switch current.type {
                case .leaf:
                    LeafResultView(places: current.samples, onReset: reset)

                case .split(let feature, _, let children):
                    QuestionCardView(
                        feature: feature,
                        children: children,
                        onAnswer: { value, node in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                answers.append((question: feature.question, answer: value))
                                path.append(node)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }

    private func reset() {
        withAnimation {
            path = []
            answers = []
        }
    }

    private func goBack() {
        guard !path.isEmpty else { return }
        withAnimation {
            path.removeLast()
            answers.removeLast()
        }
    }
}


private struct AnswerHistoryView: View {
    let answers: [(question: String, answer: String)]
    let onReset: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ваши ответы")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Назад", action: onBack)
                    .font(.caption)
                Button("Сбросить", action: onReset)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            ForEach(Array(answers.enumerated()), id: \.offset) { i, a in
                HStack(spacing: 6) {
                    Image(systemName: "\(i + 1).circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(a.question)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(a.answer)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


private struct QuestionCardView: View {
    let feature: PlaceFeature
    let children: [(value: String, node: DecisionTreeNode)]
    let onAnswer: (String, DecisionTreeNode) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: feature.icon)
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text(feature.question)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text("Выберите вариант, чтобы продолжить")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                ForEach(children, id: \.value) { child in
                    Button {
                        onAnswer(child.value, child.node)
                    } label: {
                        HStack {
                            Text(child.value)
                                .font(.body.bold())
                            Spacer()
                            Text("\(child.node.sampleCount) мест")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}


private struct LeafResultView: View {
    let places: [FoodPlace]
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("Рекомендации")
                .font(.title3.bold())

            Text("Найдено мест: \(places.count)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                ForEach(places) { place in
                    PlaceResultRow(place: place)
                }
            }

            Button(action: onReset) {
                Label("Начать заново", systemImage: "arrow.counterclockwise")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

private struct PlaceResultRow: View {
    let place: FoodPlace

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.category.icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline.bold())
                Text(place.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(place.priceLevel.short)
                    .font(.caption.bold())
                    .foregroundColor(.orange)
                if let r = place.rating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", r))
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}


private struct TreeDiagramView: View {
    let root: DecisionTreeNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    StatBadge(label: "Глубина", value: "\(root.depth)")
                    StatBadge(label: "Узлов", value: "\(root.totalNodes)")
                    StatBadge(label: "Мест", value: "\(root.sampleCount)")
                }
                .padding(.horizontal)
                .padding(.top, 8)

                TreeNodeRow(node: root, depth: 0, prefix: "")
            }
            .padding(.bottom, 20)
        }
    }
}

private struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TreeNodeRow: View {
    let node: DecisionTreeNode
    let depth: Int
    let prefix: String

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    nodeIcon
                    nodeContent
                    Spacer()
                    entropyBadge
                    if !node.isLeaf {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(nodeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, CGFloat(depth) * 20)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)

            if isExpanded, case .split(_, _, let children) = node.type {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundColor(.purple)
                        Text(child.value)
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                        Text("(\(child.node.sampleCount))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, CGFloat(depth + 1) * 20 + 12)
                    .padding(.horizontal, 8)

                    TreeNodeRow(node: child.node, depth: depth + 1, prefix: child.value)
                }
            }
        }
    }

    @ViewBuilder
    private var nodeIcon: some View {
        switch node.type {
        case .leaf:
            Image(systemName: "leaf.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .split(let feature, _, _):
            Image(systemName: feature.icon)
                .font(.caption)
                .foregroundColor(.blue)
        }
    }

    @ViewBuilder
    private var nodeContent: some View {
        switch node.type {
        case .leaf:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(node.sampleCount) мест")
                    .font(.caption.bold())
                    .foregroundColor(.green)
                Text(node.samples.map { $0.name }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        case .split(let feature, let gain, _):
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.question)
                    .font(.caption.bold())
                Text("IG = \(String(format: "%.3f", gain))")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private var entropyBadge: some View {
        Text("H=\(String(format: "%.2f", node.entropy))")
            .font(.system(size: 9, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .clipShape(Capsule())
    }

    private var nodeBackground: Color {
        switch node.type {
        case .leaf:  return Color.green.opacity(0.08)
        case .split: return Color.blue.opacity(0.06)
        }
    }
}


private struct AlgorithmStepsView: View {
    let steps: [TreeBuildStep]
    let builder: DecisionTreeBuilder
    let places: [FoodPlace]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                theorySection

                Divider()

                initialEntropySection

                Divider()

                Text("Шаги построения дерева")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    StepCardView(index: i, step: step)
                }
            }
            .padding(.vertical)
        }
    }

    private var theorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Алгоритм ID3", systemImage: "graduationcap")
                .font(.headline)

            Text("Алгоритм строит дерево рекурсивно, на каждом шаге выбирая признак с максимальным **Information Gain** — приростом информации.")
                .font(.caption)
                .foregroundColor(.secondary)

            FormulaRow(label: "Энтропия:", formula: "H(S) = -\u{2211} p\u{1D62} \u{00B7} log\u{2082}(p\u{1D62})")
            FormulaRow(label: "Information Gain:", formula: "IG(S,A) = H(S) - \u{2211} |S\u{1D65}|/|S| \u{00B7} H(S\u{1D65})")
        }
        .padding(.horizontal)
    }

    private var initialEntropySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Исходные данные")
                .font(.headline)

            let totalH = builder.entropy(places)
            let groups = Dictionary(grouping: places) { $0.category.label }

            HStack {
                Text("Всего мест: \(places.count)")
                    .font(.subheadline)
                Spacer()
                Text("H = \(String(format: "%.3f", totalH)) бит")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
            }

            FlowLayout(spacing: 6) {
                ForEach(groups.sorted(by: { $0.key < $1.key }), id: \.key) { cat, items in
                    Text("\(cat): \(items.count)")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal)
    }
}

private struct FormulaRow: View {
    let label: String
    let formula: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
            Text(formula)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct StepCardView: View {
    let index: Int
    let step: TreeBuildStep

    @State private var showGains = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Шаг \(index + 1)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(step.chosen != nil ? Color.blue : Color.green)
                    .foregroundColor(.white)
                    .clipShape(Capsule())

                Text("Глубина \(step.depth)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(step.sampleCount) мест")
                    .font(.caption)

                Text("H=\(String(format: "%.3f", step.entropy))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.orange)
            }

            Text(step.description)
                .font(.caption)

            if !step.featureGains.isEmpty {
                Button {
                    withAnimation { showGains.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showGains ? "Скрыть IG" : "Показать IG")
                            .font(.caption2)
                        Image(systemName: showGains ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }

                if showGains {
                    GainBarsView(gains: step.featureGains, chosen: step.chosen)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

private struct GainBarsView: View {
    let gains: [(feature: PlaceFeature, gain: Double)]
    let chosen: PlaceFeature?

    var body: some View {
        let maxGain = gains.map { $0.gain }.max() ?? 1

        VStack(spacing: 4) {
            ForEach(gains.sorted(by: { $0.gain > $1.gain }), id: \.feature) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.feature.icon)
                        .font(.caption2)
                        .frame(width: 14)

                    Text(item.feature.question)
                        .font(.system(size: 9))
                        .frame(width: 100, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.feature == chosen ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: maxGain > 0
                                   ? max(2, geo.size.width * item.gain / maxGain)
                                   : 2)
                    }
                    .frame(height: 10)

                    Text(String(format: "%.3f", item.gain))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(item.feature == chosen ? .blue : .secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}



private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
#Preview {
    DecisionTreeView(places: loadPlaces())
}
