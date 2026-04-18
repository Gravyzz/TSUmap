import SwiftUI

struct ContentView: View {
    @State private var places = loadPlaces()
    @StateObject private var mapModel = loadGridModel(filename: "campus-grid")
    @State private var selectedTab: Tab = .map
    @State private var selectedRatingPlaceID: String?
    @EnvironmentObject private var locale: LocaleManager

    private enum Tab {
        case map
        case food
        case cafe
        case lunch
        case walk
        case advisor
        case neuralNet
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AStarView(model: mapModel) { place, buildingReference in
                updateBuildingBinding(for: place, buildingReference: buildingReference)
            } onRatePlace: { place in
                openRating(for: place)
            } onResetRating: { place in
                resetRating(for: place)
            }
                .tag(Tab.map)
                .tabItem {
                    Label(S.content.marshrut, systemImage: "map")
                }

            PlacesListView(places: places) { place in
                mapModel.showPlace(place)
                selectedTab = .map
            } onBindBuilding: { place in
                mapModel.beginBinding(for: place)
                selectedTab = .map
            } onRatePlace: { place in
                openRating(for: place)
            } onResetRating: { place in
                resetRating(for: place)
            }
            .tag(Tab.food)
                .tabItem {
                    Label(S.content.mesta, systemImage: "mappin.and.ellipse")
                }

            ClusteringView(places: places)
                .tag(Tab.cafe)
                .tabItem {
                    Label(S.content.kafe, systemImage: "fork.knife")
                }

            GeneticView(places: places, mapModel: mapModel)
                .tag(Tab.lunch)
                .tabItem {
                    Label(S.content.obed, systemImage: "bag")
                }

            AntView(places: places, mapModel: mapModel)
                .tag(Tab.walk)
                .tabItem {
                    Label(S.content.muravi, systemImage: "ant")
                }

            DecisionTreeView(places: places)
                .tag(Tab.advisor)
                .tabItem {
                    Label(S.content.sovetnik, systemImage: "lightbulb")
                }

            NeuralNetView(
                places: places,
                selectedPlaceID: $selectedRatingPlaceID
            ) { placeID, value in
                submitRating(value, forPlaceID: placeID)
            }
                .tag(Tab.neuralNet)
                .tabItem {
                    Label(S.content.nejroset, systemImage: "hand.draw")
                }

            SettingsView()
                .tag(Tab.settings)
                .tabItem {
                    Label(S.settings.nastrojki, systemImage: "gearshape")
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
                ratings: currentPlace.ratings,
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

    private func openRating(for place: FoodPlace) {
        selectedRatingPlaceID = place.id
        selectedTab = .neuralNet
    }

    private func submitRating(_ value: Int, forPlaceID placeID: String) {
        places = places.map { place in
            guard place.id == placeID else { return place }
            return FoodPlace(
                id: place.id,
                name: place.name,
                category: place.category,
                campusBuildingCell: place.campusBuildingCell,
                address: place.address,
                description: place.description,
                schedule: place.schedule,
                priceLevel: place.priceLevel,
                ratings: place.ratings + [Double(value)],
                menu: place.menu,
                latitude: place.latitude,
                longitude: place.longitude
            )
        }
        persistPlaces()
    }

    private func resetRating(for place: FoodPlace) {
        places = places.map { currentPlace in
            guard currentPlace.id == place.id else { return currentPlace }
            return FoodPlace(
                id: currentPlace.id,
                name: currentPlace.name,
                category: currentPlace.category,
                campusBuildingCell: currentPlace.campusBuildingCell,
                address: currentPlace.address,
                description: currentPlace.description,
                schedule: currentPlace.schedule,
                priceLevel: currentPlace.priceLevel,
                ratings: [],
                menu: currentPlace.menu,
                latitude: currentPlace.latitude,
                longitude: currentPlace.longitude
            )
        }
        persistPlaces()
    }

    private func persistPlaces() {
        _ = savePlaces(places)
        mapModel.setAvailablePlaces(places)
        if let selectedRatingPlaceID,
           !places.contains(where: { $0.id == selectedRatingPlaceID }) {
            self.selectedRatingPlaceID = nil
        }
    }
}

#Preview {
    ContentView()
}
