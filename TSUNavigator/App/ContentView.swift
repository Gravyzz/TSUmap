import SwiftUI

struct ContentView: View {
    @State private var places = loadPlaces()
    @StateObject private var mapModel = loadGridModel(filename: "campus-grid")
    @State private var selectedTab: Tab = .map

    private enum Tab {
        case map
        case food
        case cafe
        case lunch
        case walk
        case advisor
        case rating
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AStarView(model: mapModel) { place, buildingReference in
                updateBuildingBinding(for: place, buildingReference: buildingReference)
            }
                .tag(Tab.map)
                .tabItem {
                    Label("Маршрут", systemImage: "map")
                }

            PlacesListView(places: places) { place in
                mapModel.showPlace(place)
                selectedTab = .map
            } onBindBuilding: { place in
                mapModel.beginBinding(for: place)
                selectedTab = .map
            }
            .tag(Tab.food)
                .tabItem {
                    Label("Еда", systemImage: "takeoutbag.and.cup.and.straw")
                }

            ClusteringView(places: places)
                .tag(Tab.cafe)
                .tabItem {
                    Label("Кафе", systemImage: "fork.knife")
                }

            GeneticView()
                .tag(Tab.lunch)
                .tabItem {
                    Label("Обед", systemImage: "bag")
                }

            AntView()
                .tag(Tab.walk)
                .tabItem {
                    Label("Прогулка", systemImage: "figure.walk")
                }

            DecisionTreeView(places: places)
                .tag(Tab.advisor)
                .tabItem {
                    Label("Советник", systemImage: "lightbulb")
                }

            NeuralNetView()
                .tag(Tab.rating)
                .tabItem {
                    Label("Оценка", systemImage: "hand.draw")
                }
        }
        .onAppear {
            mapModel.setAvailablePlaces(places)
        }
    }

    private func updateBuildingBinding(for place: FoodPlace,
                                       buildingReference: CampusBuildingReference) {
        places = places.map { currentPlace in
            guard currentPlace.id == place.id else { return currentPlace }
            return FoodPlace(
                id: currentPlace.id,
                name: currentPlace.name,
                category: currentPlace.category,
                campusBuildingCell: buildingReference,
                address: currentPlace.address,
                description: currentPlace.description,
                schedule: currentPlace.schedule,
                priceLevel: currentPlace.priceLevel,
                rating: currentPlace.rating,
                menu: currentPlace.menu,
                latitude: currentPlace.latitude,
                longitude: currentPlace.longitude
            )
        }

        guard let updatedPlace = places.first(where: { $0.id == place.id }) else { return }
        _ = savePlaces(places)
        mapModel.setAvailablePlaces(places)
        mapModel.showPlace(updatedPlace)
    }
}

#Preview {
    ContentView()
}
