import SwiftUI

struct ContentView: View {
    private let places = loadPlaces()

    var body: some View {
        TabView {
            AStarView()
                .tabItem {
                    Label("Маршрут", systemImage: "map")
                }

            PlacesListView(places: places)
                .tabItem {
                    Label("Еда", systemImage: "takeoutbag.and.cup.and.straw")
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
