import SwiftUI

struct DecisionTreeView: View {
    let places: [FoodPlace]

    @State private var tree: DecisionTreeNode?
    @State private var builder = DecisionTreeBuilder()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let tree = tree {
                    WizardView(root: tree)
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
        tree = builder.buildTree(places: places)
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
        withAnimation { path = []; answers = [] }
    }

    private func goBack() {
        guard !path.isEmpty else { return }
        withAnimation { path.removeLast(); answers.removeLast() }
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
                Button("Назад", action: onBack).font(.caption)
                Button("Сбросить", action: onReset).font(.caption).foregroundColor(.red)
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

#Preview {
    DecisionTreeView(places: loadPlaces())
}
