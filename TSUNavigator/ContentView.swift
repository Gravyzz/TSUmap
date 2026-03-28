import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            AStarView()
                .tabItem {
                    Label("Маршрут", systemImage: "map")
                }

            ClusteringView()
                .tabItem {
                    Label("Кафе", systemImage: "fork.knife")
                }

            GeneticView()
                .tabItem {
                    Label("Обед", systemImage: "bag")
                }

            AntView()
                .tabItem {
                    Label("Прогулка", systemImage: "figure.walk")
                }

            DecisionTreeView()
                .tabItem {
                    Label("Советник", systemImage: "lightbulb")
                }

            NeuralNetView()
                .tabItem {
                    Label("Оценка", systemImage: "hand.draw")
                }
        }
    }
}

#Preview {
    ContentView()
}
