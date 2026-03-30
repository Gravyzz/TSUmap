import SwiftUI

enum EditMode { case navigate, addBarrier }

struct AStarView: View {

    @StateObject private var model: MapGridModel = loadGridModel(filename: "campus-grid")

    @State private var editMode:          EditMode = .navigate
    @State private var grassWalkable:     Bool     = false
    @State private var pathLength:        Int      = 0
    @State private var noPath:            Bool     = false
    @State private var isRunning:         Bool     = false
    @State private var visitedCount:      Int      = 0
    @State private var animationGen:      Int      = 0
    @State private var showResetSheet:    Bool     = false

    private let algo = AStarAlgorithm()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                hintBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                statusBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                AStarMapView(model: model, editMode: editMode)
                    .ignoresSafeArea(edges: .horizontal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                grassToggle
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                controlButtons
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                legendBar
                    .padding(.bottom, 8)
            }
            .navigationTitle("A* — Маршрут")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .confirmationDialog("Сброс", isPresented: $showResetSheet) {
                Button("Удалить маршрут") {
                    cancelAnimations()
                    model.reset(removeBarriers: false)
                    pathLength = 0; noPath = false; visitedCount = 0
                }
                Button("Удалить всё", role: .destructive) {
                    cancelAnimations()
                    model.reset(removeBarriers: true)
                    pathLength = 0; noPath = false; visitedCount = 0
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Picker("", selection: $editMode) {
                Image(systemName: "mappin").tag(EditMode.navigate)
                Image(systemName: "pencil").tag(EditMode.addBarrier)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
        }
    }

    var grassToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: grassWalkable ? "leaf.fill" : "leaf")
                .foregroundColor(grassWalkable ? .green : .secondary)
                .font(.caption)
            Text(grassWalkable ? "По газону: можно" : "По газону: нельзя")
                .font(.caption)
                .foregroundColor(grassWalkable ? .green : .secondary)
            Spacer()
            Toggle("", isOn: $grassWalkable)
                .labelsHidden()
                .tint(.green)
        }
    }

    var hintBar: some View {
        HStack(spacing: 6) {
            if editMode == .addBarrier {
                Image(systemName: "pencil").foregroundColor(.orange)
                Text("Долгий тап — добавить/убрать барьер")
                    .font(.caption).foregroundColor(.orange)
            } else {
                Image(systemName: "mappin").foregroundColor(.blue)
                Text(
                    model.startCell == nil ? "Тапни на карту или здание — СТАРТ" :
                    model.endCell   == nil ? "Тапни на карту или здание — ФИНИШ" :
                                             "Нажми «Найти путь»"
                )
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }


    var statusBar: some View {
        Group {
            if isRunning {
                HStack {
                    ProgressView()
                    Text("Ищу путь… просмотрено \(visitedCount) клеток")
                        .font(.caption2).foregroundColor(.secondary)
                }
            } else if noPath {
                Label("Путь не найден", systemImage: "xmark.circle")
                    .foregroundColor(.red).font(.caption).bold()
            } else if pathLength > 0 {
                Label(
                    "Путь: \(pathLength) шагов · просмотрено \(visitedCount)",
                    systemImage: "checkmark.circle"
                )
                .foregroundColor(.green).font(.caption).bold()
            } else {
                Color.clear.frame(height: 16)
            }
        }
    }


    var controlButtons: some View {
        HStack(spacing: 12) {
            Button {
                runAStar()
            } label: {
                Label("Найти путь", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.startCell == nil || model.endCell == nil || isRunning)

            Button {
                showResetSheet = true
            } label: {
                Label("Сброс", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.red)
            .disabled(isRunning)
        }
    }

    var legendBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                legendItem(.green,                          "Старт")
                legendItem(.red,                            "Финиш")
                legendItem(Color.black.opacity(0.55),       "Здание")
                legendItem(Color.green.opacity(0.35),       "Газон")
                legendItem(Color(red: 0.25, green: 0.56, blue: 1.0), "Маршрут")
                legendItem(.blue.opacity(0.15),             "Просмотрено")
            }
            .padding(.horizontal, 12)
        }
        .font(.caption2)
    }

    func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )
            Text(label)
        }
    }

    func cancelAnimations() {
        animationGen += 1
        isRunning = false
    }

    func runAStar() {
        guard let start = model.startCell,
              let end   = model.endCell else { return }

        isRunning    = true
        noPath       = false
        visitedCount = 0
        model.clearPath()

        let generation = animationGen + 1
        animationGen   = generation

        var actualStart = start
        var actualEnd   = end

        if let startBuilding = model.selectedStartBuilding {
            if let edge = model.nearestWalkableEdge(of: startBuilding,
                                                     to: end,
                                                     grassWalkable: grassWalkable) {
                actualStart = edge
            }
        }
        if let endBuilding = model.selectedEndBuilding {
            if let edge = model.nearestWalkableEdge(of: endBuilding,
                                                     to: start,
                                                     grassWalkable: grassWalkable) {
                actualEnd = edge
            }
        }

        let snapshot = model.snapshot(grassWalkable: grassWalkable)
        let capturedStart = actualStart
        let capturedEnd   = actualEnd

        DispatchQueue.global(qos: .userInitiated).async {
            var visited: [Cell] = []
            visited.reserveCapacity(50_000)

            let path = algo.findPath(in: snapshot, from: capturedStart, to: capturedEnd) { cell in
                visited.append(cell)
            } ?? []

            DispatchQueue.main.async {
                guard generation == self.animationGen else { return }

                guard !path.isEmpty else {
                    self.noPath    = true
                    self.isRunning = false
                    return
                }

                let batchSize = max(visited.count / 80, 100)
                let totalBatches = (visited.count + batchSize - 1) / batchSize

                for batchIdx in 0..<totalBatches {
                    let batchStart = batchIdx * batchSize
                    let batchEnd   = min(batchStart + batchSize, visited.count)

                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(batchIdx) * 0.03) {
                        guard generation == self.animationGen else { return }
                        for i in batchStart..<batchEnd {
                            let cell = visited[i]
                            let t = self.model.grid[cell.row][cell.col]
                            if t == .road || t == .grass {
                                self.model.visitedCells.append(cell)
                            }
                        }
                        self.visitedCount = batchEnd
                    }
                }

                let visitedDelay = Double(totalBatches) * 0.03 + 0.1
                let pathBatchSize = max(path.count / 40, 10)
                let pathBatches   = (path.count + pathBatchSize - 1) / pathBatchSize

                for batchIdx in 0..<pathBatches {
                    let batchStart = batchIdx * pathBatchSize
                    let batchEnd   = min(batchStart + pathBatchSize, path.count)

                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + visitedDelay + Double(batchIdx) * 0.04
                    ) {
                        guard generation == self.animationGen else { return }
                        for i in batchStart..<batchEnd {
                            self.model.pathCells.append(path[i])
                        }
                        if batchEnd == path.count {
                            self.pathLength = path.count - 1
                            self.isRunning  = false
                        }
                    }
                }
            }
        }
    }
}

#Preview { AStarView() }
