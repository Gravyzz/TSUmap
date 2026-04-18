import SwiftUI
import UIKit

struct DecisionTreeView: View {
    let places: [FoodPlace]

    private let baseCSV = DecisionTreeDefaults.sampleCSV
    @State private var additionalCSV: String = ""
    @State private var parseResult: CSVParseResult = CSVParser.parse(text: DecisionTreeDefaults.sampleCSV)
    @State private var rawTree: DTNode?
    @State private var shownTree: DTNode?

    @State private var maxDepth: Double = 6
    @State private var minSamplesLeaf: Double = 1
    @State private var minInfoGain: Double = 0.0
    @State private var postPruneEnabled: Bool = true
    @State private var postPruneGain: Double = 0.05

    @State private var stage: Stage = .query
    @State private var query: [String: String] = [:]
    @State private var prediction: PredictionResult?
    @State private var highlightedNodes: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var trainingAccuracy: Double = 0

    @State private var bottomSheetExpanded: Bool = false

    enum Stage: String, CaseIterable {
        case query = "Запрос"
        case tree = "Дерево"
        case data = "Данные"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $stage) {
                    ForEach(Stage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Group {
                    switch stage {
                    case .query: queryStageView
                    case .tree:  treeStageView
                    case .data:  dataStageView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(S.decisionTree.sovetnik)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if rawTree == nil { rebuildTree() } }
        }
    }

    private func combinedCSV() -> String {
        let header = baseCSV.split(separator: "\n").first.map(String.init) ?? ""
        let extras = additionalCSV
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != header && !$0.hasPrefix("#") }
        if extras.isEmpty { return baseCSV }
        return baseCSV + "\n" + extras.joined(separator: "\n")
    }

    private func rebuildTree() {
        parseResult = CSVParser.parse(text: combinedCSV())
        errorMessage = parseResult.errors.first
        guard !parseResult.samples.isEmpty else {
            rawTree = nil
            shownTree = nil
            return
        }
        let builder = DecisionTreeBuilder()
        builder.maxDepth = Int(maxDepth)
        builder.minSamplesLeaf = Int(minSamplesLeaf)
        builder.minInfoGain = minInfoGain
        let tree = builder.build(samples: parseResult.samples,
                                 featureNames: parseResult.featureNames)
        let displayed = postPruneEnabled ? builder.prune(tree, minGain: postPruneGain) : tree
        rawTree = tree
        shownTree = displayed
        trainingAccuracy = builder.trainingAccuracy(tree: displayed,
                                                    samples: parseResult.samples)
        prefillQuery()
        prediction = nil
        highlightedNodes = []
    }

    private func prefillQuery() {
        var q: [String: String] = [:]
        for f in parseResult.featureNames {
            if let existing = query[f],
               parseResult.featureValues[f]?.contains(existing) == true {
                q[f] = existing
            } else {
                q[f] = parseResult.featureValues[f]?.first ?? ""
            }
        }
        query = q
    }

    private var queryStageView: some View {
        VStack(spacing: 0) {
            if shownTree != nil, !parseResult.featureNames.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(parseResult.featureNames, id: \.self) { name in
                            queryRow(for: name)
                        }

                        Button {
                            runPrediction()
                        } label: {
                            Text(S.decisionTree.opredelitZavedenie)
                                .font(.body.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, 4)

                        if let p = prediction {
                            predictionCard(p)
                        }
                    }
                    .padding(12)
                }
            } else {
                emptyView(S.decisionTree.netDereva,
                          hint: S.decisionTree.perejditeNaVkladkuDannyeChtobyDobavit)
            }
        }
    }

    private func queryRow(for name: String) -> some View {
        let schema = DecisionTreeDefaults.schema(for: name,
                                                  parsed: parseResult.featureValues[name])
        let observed = parseResult.featureValues[name] ?? []
        let values = schema.values.filter { observed.contains($0) }
        let finalValues = values.isEmpty ? observed : values

        return HStack(spacing: 10) {
            Image(systemName: schema.icon)
                .font(.body)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(schema.title).font(.caption.bold())
                Text(name).font(.caption2).foregroundColor(.secondary)
            }

            Spacer()

            Menu {
                ForEach(finalValues, id: \.self) { v in
                    Button(schema.valueLabels[v] ?? v) {
                        query[name] = v
                        prediction = nil
                        highlightedNodes = []
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(schema.valueLabels[query[name] ?? ""] ?? (query[name] ?? "—"))
                        .font(.caption.bold())
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func runPrediction() {
        guard let tree = shownTree else { return }
        let result = DecisionTreePredictor.predict(tree: tree, query: query)
        prediction = result
        var ids: Set<UUID> = [tree.id, result.leafId]
        for step in result.path { ids.insert(step.nodeId); ids.insert(step.childId) }
        highlightedNodes = ids
    }

    private func predictionCard(_ r: PredictionResult) -> some View {
        let matchedPlace = places.first(where: { $0.name == r.label })
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: r.unknownBranch ? "exclamationmark.circle.fill" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundColor(r.unknownBranch ? .orange : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(S.decisionTree.rekomenduetsja)
                        .font(.caption2).foregroundColor(.secondary)
                    Text(r.label)
                        .font(.title3.bold())
                }
                Spacer()
                Text("\(Int(r.confidence * 100))%")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            }

            if r.unknownBranch {
                Text(S.decisionTree.nekotoryeOtvetyNeVstrechalisVObuchajushej)
                    .font(.caption2).foregroundColor(.orange)
            }

            if let p = matchedPlace {
                HStack(spacing: 8) {
                    Image(systemName: p.category.icon).font(.caption).foregroundColor(.blue)
                    Text(p.address).font(.caption2).foregroundColor(.secondary)
                    Spacer()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(S.decisionTree.putPoDerevu).font(.caption.bold()).foregroundColor(.secondary)
                ForEach(Array(r.path.enumerated()), id: \.offset) { i, step in
                    let schema = DecisionTreeDefaults.schema(for: step.feature,
                                                              parsed: parseResult.featureValues[step.feature])
                    HStack(spacing: 6) {
                        Image(systemName: "\(i + 1).circle.fill")
                            .font(.caption).foregroundColor(.blue)
                        Text(schema.title).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(schema.valueLabels[step.value] ?? step.value)
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundColor(.green)
                    Text(S.decisionTree.list)
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(r.label).font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private var treeStageView: some View {
        VStack(spacing: 0) {
            if let tree = shownTree {
                treeStatsBar(tree: tree)
                    .padding(.horizontal, 12).padding(.vertical, 6)

                ZoomableTreeCanvas(tree: tree, highlightedNodes: highlightedNodes)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6))

                bottomSheet
            } else {
                emptyView(S.decisionTree.netDannyh,
                          hint: S.decisionTree.perejditeNaVkladkuDannyeIDobavte)
            }
        }
    }

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    bottomSheetExpanded.toggle()
                }
            } label: {
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 40, height: 4)
                    HStack(spacing: 6) {
                        Image(systemName: bottomSheetExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption2)
                        Text(bottomSheetExpanded ? S.decisionTree.svernutParametry : S.decisionTree.parametryPostroenija)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { g in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if g.translation.height > 20 { bottomSheetExpanded = false }
                            else if g.translation.height < -20 { bottomSheetExpanded = true }
                        }
                    }
            )

            if bottomSheetExpanded {
                ScrollView {
                    VStack(spacing: 10) {
                        VStack(spacing: 6) {
                            Text(S.decisionTree.parametryPostroenija)
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            slider(S.decisionTree.maksGlubina, value: $maxDepth, range: 2...10, step: 1)
                            slider(S.decisionTree.minObrazcovVListe, value: $minSamplesLeaf, range: 1...10, step: 1)
                            slider(S.decisionTree.minIgDljaVetvlenija, value: $minInfoGain, range: 0...0.3, step: 0.01,
                                   format: "%.2f")
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(spacing: 6) {
                            Text(S.decisionTree.optimizacijaRazmeraPostObrezka)
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle(S.decisionTree.slivatIzbytochnyeVetki, isOn: $postPruneEnabled)
                                .font(.caption)
                            slider(S.decisionTree.minIgDljaSohranenija, value: $postPruneGain,
                                   range: 0...0.3, step: 0.01, format: "%.2f")
                                .disabled(!postPruneEnabled)
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
                            rebuildTree()
                        } label: {
                            Text(S.decisionTree.primenit)
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 260)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.08), radius: 5, y: -2)
    }

    private func treeStatsBar(tree: DTNode) -> some View {
        HStack(spacing: 12) {
            stat(S.decisionTree.uzlov, value: "\(tree.nodeCount)", icon: "circle.grid.2x2.fill", color: .blue)
            stat(S.decisionTree.listev, value: "\(tree.leafCount)", icon: "leaf.fill", color: .green)
            stat(S.decisionTree.glubina, value: "\(tree.depth)", icon: "arrow.down.to.line", color: .purple)
            stat(S.decisionTree.tochnost, value: "\(Int(trainingAccuracy * 100))%",
                 icon: "checkmark.seal.fill", color: .orange)
        }
    }

    private var dataStageView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.caption2).foregroundColor(.secondary)
                            Text(S.decisionTree.bazovajaVyborkaTolkoChtenie)
                                .font(.caption.bold()).foregroundColor(.secondary)
                            Spacer()
                            let baseCount = baseCSV.split(separator: "\n").count - 1
                            Text("\(baseCount) записей")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        ScrollView {
                            Text(baseCSV)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(maxHeight: 180)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption2).foregroundColor(.blue)
                            Text(S.decisionTree.dobavitNovyeZapisi)
                                .font(.caption.bold()).foregroundColor(.blue)
                            Spacer()
                            Button {
                                if let s = UIPasteboard.general.string {
                                    if additionalCSV.isEmpty {
                                        additionalCSV = s
                                    } else {
                                        additionalCSV += "\n" + s
                                    }
                                }
                            } label: {
                                Label(S.decisionTree.vstavit, systemImage: "doc.on.clipboard")
                                    .font(.caption2.bold())
                            }
                            Button {
                                additionalCSV = ""
                            } label: {
                                Label(S.decisionTree.ochistit, systemImage: "trash")
                                    .font(.caption2.bold())
                                    .foregroundColor(.red)
                            }
                            .disabled(additionalCSV.isEmpty)
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $additionalCSV)
                                .font(.system(size: 12, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .frame(minHeight: 120)
                                .padding(6)
                                .background(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                                )
                            if additionalCSV.isEmpty {
                                Text(S.decisionTree.busStopLowShortCoffeeLow)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }

                        Text(S.decisionTree.kolonkiLocationBudgetTimeAvailableFood)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if let err = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(err).font(.caption2).foregroundColor(.orange)
                        }
                    }

                    if !parseResult.samples.isEmpty {
                        let baseCount = baseCSV.split(separator: "\n").count - 1
                        let extraCount = max(0, parseResult.samples.count - baseCount)
                        HStack(spacing: 12) {
                            Label("\(parseResult.samples.count) записей", systemImage: "tray.full")
                            Label("\(parseResult.featureNames.count) признаков", systemImage: "list.bullet")
                            if extraCount > 0 {
                                Label("+\(extraCount) новых", systemImage: "plus.circle")
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(12)
            }

            Button {
                rebuildTree()
                if shownTree != nil { stage = .tree }
            } label: {
                Text(S.decisionTree.perestroitDerevo)
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(12)
        }
    }

    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double,
                        format: String = "%.0f") -> some View {
        HStack {
            Text("\(label): \(String(format: format, value.wrappedValue))")
                .font(.caption2).foregroundColor(.secondary)
                .frame(width: 170, alignment: .leading)
            Slider(value: value, in: range, step: step)
        }
    }

    private func stat(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundColor(color)
            Text(value).font(.caption.bold())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func emptyView(_ title: String, hint: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tree").font(.system(size: 40)).foregroundColor(.secondary)
            Text(title).font(.title3.bold())
            Text(hint).font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct PositionedNode: Identifiable {
    let id: UUID
    let node: DTNode
    let position: CGPoint
}

struct PositionedEdge: Identifiable {
    let id = UUID()
    let fromId: UUID
    let toId: UUID
    let from: CGPoint
    let to: CGPoint
    let label: String
}

struct TreeLayout {
    let nodes: [PositionedNode]
    let edges: [PositionedEdge]
    let width: CGFloat
    let height: CGFloat
}

enum TreeLayoutEngine {
    static func layout(_ root: DTNode,
                       hStep: CGFloat = 160,
                       vStep: CGFloat = 130) -> TreeLayout {
        var nodes: [PositionedNode] = []
        var edges: [PositionedEdge] = []
        var leafCounter: CGFloat = 0

        @discardableResult
        func walk(_ node: DTNode, depth: Int) -> CGFloat {
            let y = CGFloat(depth) * vStep + 70
            switch node.type {
            case .leaf:
                let x = leafCounter * hStep + hStep / 2
                leafCounter += 1
                nodes.append(PositionedNode(id: node.id, node: node,
                                            position: CGPoint(x: x, y: y)))
                return x
            case .split(_, _, let children):
                var childXs: [(DTNode, String, CGFloat)] = []
                for (v, c) in children {
                    let cx = walk(c, depth: depth + 1)
                    childXs.append((c, v, cx))
                }
                let x = childXs.map(\.2).reduce(0, +) / CGFloat(childXs.count)
                nodes.append(PositionedNode(id: node.id, node: node,
                                            position: CGPoint(x: x, y: y)))
                for (c, v, cx) in childXs {
                    edges.append(PositionedEdge(fromId: node.id,
                                                toId: c.id,
                                                from: CGPoint(x: x, y: y),
                                                to: CGPoint(x: cx, y: CGFloat(depth + 1) * vStep + 70),
                                                label: v))
                }
                return x
            }
        }

        walk(root, depth: 0)
        let width = max(leafCounter * hStep, hStep) + 40
        let height = CGFloat(root.depth + 1) * vStep + 100
        return TreeLayout(nodes: nodes, edges: edges, width: width, height: height)
    }
}

struct ZoomableTreeCanvas: UIViewRepresentable {
    let tree: DTNode
    let highlightedNodes: Set<UUID>

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 0.2
        scroll.maximumZoomScale = 4.0
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = true
        scroll.showsHorizontalScrollIndicator = true
        scroll.backgroundColor = .clear

        let layout = TreeLayoutEngine.layout(tree)
        let canvas = TreeCanvasUIView(frame: CGRect(origin: .zero,
                                                    size: CGSize(width: layout.width,
                                                                 height: layout.height)))
        canvas.layout = layout
        canvas.highlighted = highlightedNodes
        canvas.backgroundColor = .clear
        context.coordinator.canvas = canvas

        scroll.addSubview(canvas)
        scroll.contentSize = canvas.frame.size

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coord.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        DispatchQueue.main.async {
            fitToScreen(scroll: scroll, canvas: canvas)
            context.coordinator.centerContent(in: scroll)
        }
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let layout = TreeLayoutEngine.layout(tree)
        guard let canvas = context.coordinator.canvas else { return }
        let sizeChanged = canvas.frame.size != CGSize(width: layout.width, height: layout.height)
        canvas.frame = CGRect(origin: .zero, size: CGSize(width: layout.width, height: layout.height))
        canvas.layout = layout
        canvas.highlighted = highlightedNodes
        scroll.contentSize = canvas.frame.size
        canvas.setNeedsDisplay()

        if sizeChanged {
            DispatchQueue.main.async {
                fitToScreen(scroll: scroll, canvas: canvas)
                context.coordinator.centerContent(in: scroll)
            }
        }
    }

    private func fitToScreen(scroll: UIScrollView, canvas: UIView) {
        guard scroll.bounds.width > 0, canvas.frame.width > 0 else { return }
        let fitX = scroll.bounds.width / canvas.frame.width
        let fitY = scroll.bounds.height / canvas.frame.height
        let scale = min(fitX, fitY, 1.0)
        scroll.minimumZoomScale = min(0.2, scale * 0.6)
        scroll.setZoomScale(max(scale, scroll.minimumZoomScale), animated: false)
    }

    func makeCoordinator() -> Coord { Coord() }

    final class Coord: NSObject, UIScrollViewDelegate {
        weak var canvas: TreeCanvasUIView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
        func scrollViewDidZoom(_ sv: UIScrollView) { centerContent(in: sv) }

        func centerContent(in sv: UIScrollView) {
            guard let c = canvas else { return }
            let contentW = c.frame.width * sv.zoomScale
            let contentH = c.frame.height * sv.zoomScale
            let offsetX = max((sv.bounds.width - contentW) / 2, 0)
            let offsetY = max((sv.bounds.height - contentH) / 2, 0)
            sv.contentInset = UIEdgeInsets(top: offsetY, left: offsetX,
                                           bottom: offsetY, right: offsetX)
        }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = g.view as? UIScrollView else { return }
            if sv.zoomScale > sv.minimumZoomScale * 1.2 {
                sv.setZoomScale(sv.minimumZoomScale, animated: true)
            } else {
                let target: CGFloat = min(sv.maximumZoomScale, sv.minimumZoomScale * 2.5)
                sv.setZoomScale(target, animated: true)
            }
        }
    }
}

final class TreeCanvasUIView: UIView {
    var layout: TreeLayout = TreeLayout(nodes: [], edges: [], width: 0, height: 0) {
        didSet { setNeedsDisplay() }
    }
    var highlighted: Set<UUID> = [] {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        for edge in layout.edges {
            let isHigh = highlighted.contains(edge.fromId) && highlighted.contains(edge.toId)
            ctx.setStrokeColor((isHigh ? UIColor.systemBlue : UIColor.systemGray3).cgColor)
            ctx.setLineWidth(isHigh ? 3 : 1.5)
            ctx.setLineCap(.round)
            ctx.move(to: edge.from)
            ctx.addLine(to: edge.to)
            ctx.strokePath()

            let mid = CGPoint(x: (edge.from.x + edge.to.x) / 2,
                              y: (edge.from.y + edge.to.y) / 2)
            let label = edge.label as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: isHigh ? UIColor.white : UIColor.label
            ]
            let sz = label.size(withAttributes: attrs)
            let bgRect = CGRect(x: mid.x - sz.width / 2 - 5,
                                y: mid.y - sz.height / 2 - 2,
                                width: sz.width + 10,
                                height: sz.height + 4)
            let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 4)
            (isHigh ? UIColor.systemBlue : UIColor.systemBackground).setFill()
            bgPath.fill()
            (isHigh ? UIColor.systemBlue : UIColor.systemGray3).setStroke()
            bgPath.lineWidth = 1
            bgPath.stroke()
            label.draw(at: CGPoint(x: mid.x - sz.width / 2, y: mid.y - sz.height / 2),
                       withAttributes: attrs)
        }

        for pn in layout.nodes { drawNode(pn, ctx: ctx) }
    }

    private func drawNode(_ pn: PositionedNode, ctx: CGContext) {
        let isHigh = highlighted.contains(pn.id)
        let w: CGFloat = 130, h: CGFloat = 68
        let rect = CGRect(x: pn.position.x - w / 2,
                          y: pn.position.y - h / 2,
                          width: w, height: h)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3,
                      color: UIColor.black.withAlphaComponent(0.15).cgColor)
        switch pn.node.type {
        case .leaf:
            leafColor(for: pn.node.majorityLabel).setFill()
        case .split:
            (isHigh ? UIColor.systemBlue : UIColor.systemBackground).setFill()
        }
        path.fill()
        ctx.restoreGState()

        switch pn.node.type {
        case .leaf:
            if isHigh {
                UIColor.systemBlue.setStroke()
                path.lineWidth = 3
                path.stroke()
            }

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centerPara
            ]
            let name = pn.node.majorityLabel as NSString
            name.draw(in: CGRect(x: rect.minX + 4, y: rect.minY + 10,
                                 width: w - 8, height: 36),
                      withAttributes: titleAttrs)

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: centerPara
            ]
            ("n=\(pn.node.sampleCount)" as NSString)
                .draw(in: CGRect(x: rect.minX, y: rect.maxY - 16, width: w, height: 12),
                      withAttributes: subAttrs)

        case .split(let feature, let gain, _):
            (isHigh ? UIColor.systemBlue : UIColor.systemGray3).setStroke()
            path.lineWidth = isHigh ? 2 : 1
            path.stroke()

            let schema = DecisionTreeDefaults.schema(for: feature)
            let fg: UIColor = isHigh ? .white : .label

            if let icon = UIImage(systemName: schema.icon)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
                .withTintColor(fg, renderingMode: .alwaysOriginal) {
                let iconSize: CGFloat = 14
                icon.draw(in: CGRect(x: rect.midX - iconSize / 2,
                                     y: rect.minY + 6,
                                     width: iconSize, height: iconSize))
            }

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 11),
                .foregroundColor: fg,
                .paragraphStyle: centerPara
            ]
            (schema.title as NSString)
                .draw(in: CGRect(x: rect.minX + 4, y: rect.minY + 22,
                                 width: w - 8, height: 18),
                      withAttributes: titleAttrs)

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: isHigh ? UIColor.white.withAlphaComponent(0.9)
                                         : UIColor.secondaryLabel,
                .paragraphStyle: centerPara
            ]
            ("IG=\(String(format: "%.2f", gain))" as NSString)
                .draw(in: CGRect(x: rect.minX, y: rect.maxY - 28, width: w, height: 12),
                      withAttributes: subAttrs)
            ("n=\(pn.node.sampleCount)" as NSString)
                .draw(in: CGRect(x: rect.minX, y: rect.maxY - 16, width: w, height: 12),
                      withAttributes: subAttrs)
        }
    }

    private var centerPara: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byTruncatingTail
        return p
    }

    private func leafColor(for label: String) -> UIColor {
        let palette: [UIColor] = [
            .systemBlue, .systemGreen, .systemOrange, .systemPurple,
            .systemPink, .systemTeal, .systemIndigo, .systemRed,
            .systemBrown, .systemMint
        ]
        let hash = abs(label.hashValue)
        return palette[hash % palette.count]
    }
}

#Preview {
    DecisionTreeView(places: loadPlaces())
}
