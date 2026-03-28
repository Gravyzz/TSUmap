import SwiftUI

struct AStarView: View {
    @StateObject private var map = MapGrid(rows: 20, cols: 20)
    @State private var pathLength = 0
    @State private var noPath = false
    @State private var isRunning = false

    private let algo = AStarAlgorithm()
    private let cellSize: CGFloat = 16

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Сетка
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 1) {
                        ForEach(0..<map.rows, id: \.self) { row in
                            HStack(spacing: 1) {
                                ForEach(0..<map.cols, id: \.self) { col in
                                    Rectangle()
                                        .fill(cellColor(map.grid[row][col]))
                                        .frame(width: cellSize, height: cellSize)
                                        .cornerRadius(2)
                                        .onTapGesture {
                                            guard !isRunning else { return }
                                            map.tapCell(row: row, col: col)
                                            pathLength = 0
                                            noPath = false
                                        }
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                // Статус
                Group {
                    if noPath {
                        Text("❌ Путь не найден")
                            .foregroundColor(.red).bold()
                    } else if pathLength > 0 {
                        Text("✅ Длина пути: \(pathLength) шагов")
                            .foregroundColor(.green).bold()
                    } else {
                        Text(" ").foregroundColor(.clear)
                    }
                }

                // Кнопки
                HStack(spacing: 16) {
                    Button {
                        runAStar()
                    } label: {
                        Label("Найти путь", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(map.startCell == nil || map.endCell == nil || isRunning)

                    Button {
                        map.reset()
                        pathLength = 0
                        noPath = false
                    } label: {
                        Label("Сброс", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal)

                // Легенда
                HStack(spacing: 10) {
                    legendItem(.green,             "Старт")
                    legendItem(.red,               "Финиш")
                    legendItem(Color(.systemGray), "Стена")
                    legendItem(.yellow,            "Путь")
                }
                .font(.caption2)
                .padding(.bottom, 8)
            }
            .navigationTitle("A* — Маршрут")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func cellColor(_ type: CellType) -> Color {
        switch type {
        case .walkable: return Color(.systemGray6)
        case .obstacle: return Color(.systemGray)
        case .start:    return .green
        case .end:      return .red
        case .path:     return .yellow
        case .visited:  return .blue.opacity(0.3)
        }
    }

    func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 12, height: 12).cornerRadius(2)
            Text(label)
        }
    }

    var hint: String {
        if map.startCell == nil    { return "Нажми на клетку — поставь СТАРТ (зелёный)" }
        else if map.endCell == nil { return "Нажми ещё раз — поставь ФИНИШ (красный)" }
        else                       { return "Ставь стены нажатием. Потом «Найти путь»" }
    }

    func runAStar() {
        guard let start = map.startCell, let end = map.endCell else { return }
        isRunning = true
        noPath = false
        map.clearPath()

        let path = algo.findPath(in: map, from: start, to: end) ?? []

        guard !path.isEmpty else {
            noPath = true
            isRunning = false
            return
        }

        for (i, cell) in path.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                if cell != self.map.startCell && cell != self.map.endCell {
                    self.map.setCell(row: cell.row, col: cell.col, type: .path)
                }
                if i == path.count - 1 {
                    self.pathLength = path.count - 1
                    self.isRunning = false
                }
            }
        }
    }
}

#Preview {
    AStarView()
}
