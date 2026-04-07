import Foundation
import CoreLocation

enum PlaceCategory: String, Codable, CaseIterable {
    case vending    = "vending"
    case buffet     = "buffet"
    case cafeteria  = "cafeteria"
    case canteen    = "canteen"
    case coffeeshop = "coffeeshop"
    case cafe       = "cafe"
    case fastfood   = "fastfood"
    case gastrohall = "gastrohall"
    case shop       = "shop"

    var icon: String {
        switch self {
        case .vending:    return "cup.and.saucer"
        case .buffet:     return "takeoutbag.and.cup.and.straw"
        case .cafeteria:  return "fork.knife"
        case .canteen:    return "tray"
        case .coffeeshop: return "cup.and.saucer.fill"
        case .cafe:       return "fork.knife.circle"
        case .fastfood:   return "flame"
        case .gastrohall: return "lightbulb"
        case .shop:       return "cart"
        }
    }

    var label: String {
        switch self {
        case .vending:    return "Автомат"
        case .buffet:     return "Буфет"
        case .cafeteria:  return "Кафе (корпус)"
        case .canteen:    return "Столовая"
        case .coffeeshop: return "Кофейня"
        case .cafe:       return "Кафе"
        case .fastfood:   return "Фастфуд"
        case .gastrohall: return "Гастрохол"
        case .shop:       return "Магазин"
        }
    }
}

enum PriceLevel: String, Codable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var label: String {
        switch self {
        case .low:    return "до 150 ₽"
        case .medium: return "150–350 ₽"
        case .high:   return "350–700 ₽"
        }
    }

    var short: String {
        switch self {
        case .low:    return "₽"
        case .medium: return "₽₽"
        case .high:   return "₽₽₽"
        }
    }
}

enum MenuItemCategory: String, Codable {
    case hotMeal  = "hot_meal"
    case soup     = "soup"
    case salad    = "salad"
    case sandwich = "sandwich"
    case pastry   = "pastry"
    case breakfast = "breakfast"
    case dessert  = "dessert"
    case snack    = "snack"
    case coffee   = "coffee"
    case tea      = "tea"
    case drink    = "drink"
    case grocery  = "grocery"

    var icon: String {
        switch self {
        case .hotMeal:   return "flame.fill"
        case .soup:      return "mug"
        case .salad:     return "leaf"
        case .sandwich:  return "rectangle.stack"
        case .pastry:    return "birthday.cake"
        case .breakfast: return "sun.rise"
        case .dessert:   return "star"
        case .snack:     return "bag"
        case .coffee:    return "cup.and.saucer.fill"
        case .tea:       return "leaf.fill"
        case .drink:     return "waterbottle"
        case .grocery:   return "cart.fill"
        }
    }

    var label: String {
        switch self {
        case .hotMeal:   return "Горячее"
        case .soup:      return "Супы"
        case .salad:     return "Салаты"
        case .sandwich:  return "Сэндвичи"
        case .pastry:    return "Выпечка"
        case .breakfast: return "Завтраки"
        case .dessert:   return "Десерты"
        case .snack:     return "Снеки"
        case .coffee:    return "Кофе"
        case .tea:       return "Чай"
        case .drink:     return "Напитки"
        case .grocery:   return "Продукты"
        }
    }
}

struct CampusBuildingReference: Codable, Hashable {
    let row: Int
    let col: Int
}

struct MenuItem: Codable, Identifiable {
    var id: String { name }
    let name: String
    let category: MenuItemCategory
    let priceMin: Int?
    let priceMax: Int?

    var priceText: String {
        if let min = priceMin, let max = priceMax {
            return min == max ? "\(min) ₽" : "\(min)–\(max) ₽"
        } else if let min = priceMin {
            return "от \(min) ₽"
        }
        return ""
    }
}

struct WorkSchedule: Codable {
    let weekdays: String?
    let weekends: String?
    let note: String?

    var displayText: String {
        if let note = note { return note }
        var parts: [String] = []
        if let wd = weekdays { parts.append("Пн–Пт \(wd)") }
        if let we = weekends { parts.append("Сб–Вс \(we)") }
        return parts.joined(separator: " · ")
    }
}

struct FoodPlace: Codable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case campusBuildingCell
        case address
        case description
        case schedule
        case priceLevel
        case rating
        case ratings
        case menu
        case latitude
        case longitude
    }

    let id: String
    let name: String
    let category: PlaceCategory
    let campusBuildingCell: CampusBuildingReference?
    let address: String
    let description: String
    let schedule: WorkSchedule
    let priceLevel: PriceLevel
    let ratings: [Double]
    let menu: [MenuItem]
    let latitude: Double
    let longitude: Double

    init(
        id: String,
        name: String,
        category: PlaceCategory,
        campusBuildingCell: CampusBuildingReference?,
        address: String,
        description: String,
        schedule: WorkSchedule,
        priceLevel: PriceLevel,
        ratings: [Double] = [],
        menu: [MenuItem],
        latitude: Double,
        longitude: Double
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.campusBuildingCell = campusBuildingCell
        self.address = address
        self.description = description
        self.schedule = schedule
        self.priceLevel = priceLevel
        self.ratings = ratings
        self.menu = menu
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(PlaceCategory.self, forKey: .category)
        campusBuildingCell = try container.decodeIfPresent(CampusBuildingReference.self, forKey: .campusBuildingCell)
        address = try container.decode(String.self, forKey: .address)
        description = try container.decode(String.self, forKey: .description)
        schedule = try container.decode(WorkSchedule.self, forKey: .schedule)
        priceLevel = try container.decode(PriceLevel.self, forKey: .priceLevel)
        menu = try container.decode([MenuItem].self, forKey: .menu)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)

        if let ratings = try container.decodeIfPresent([Double].self, forKey: .ratings) {
            self.ratings = ratings
        } else if let legacyRating = try container.decodeIfPresent(Double.self, forKey: .rating) {
            self.ratings = [legacyRating]
        } else {
            self.ratings = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(campusBuildingCell, forKey: .campusBuildingCell)
        try container.encode(address, forKey: .address)
        try container.encode(description, forKey: .description)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(priceLevel, forKey: .priceLevel)
        try container.encodeIfPresent(rating, forKey: .rating)
        try container.encode(ratings, forKey: .ratings)
        try container.encode(menu, forKey: .menu)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    var rating: Double? {
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    var ratingsCount: Int {
        ratings.count
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isShownOnCampusMap: Bool {
        campusBuildingCell != nil
    }

    var menuByCategory: [(category: MenuItemCategory, items: [MenuItem])] {
        let grouped = Dictionary(grouping: menu) { $0.category }
        let order: [MenuItemCategory] = [
            .breakfast, .soup, .hotMeal, .salad, .sandwich,
            .pastry, .dessert, .snack, .coffee, .tea, .drink, .grocery
        ]
        return order.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (category: cat, items: items)
        }
    }
}

private let placesFileName = "campus-places.json"

private func bundledPlacesURL() -> URL? {
    Bundle.main.url(forResource: "campus-places", withExtension: "json")
}

private func writablePlacesURL() -> URL {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return documentsURL.appendingPathComponent(placesFileName)
}

func loadPlaces() -> [FoodPlace] {
    let fileManager = FileManager.default
    let writableURL = writablePlacesURL()

    let documentsPlaces: [FoodPlace]? = {
        guard fileManager.fileExists(atPath: writableURL.path),
              let data = try? Data(contentsOf: writableURL),
              let places = try? JSONDecoder().decode([FoodPlace].self, from: data)
        else { return nil }
        return places
    }()

    let bundlePlaces: [FoodPlace]? = {
        guard let url = bundledPlacesURL(),
              let data = try? Data(contentsOf: url),
              let places = try? JSONDecoder().decode([FoodPlace].self, from: data)
        else { return nil }
        return places
    }()

    let docBindings = documentsPlaces?.filter { $0.campusBuildingCell != nil }.count ?? 0
    let bundleBindings = bundlePlaces?.filter { $0.campusBuildingCell != nil }.count ?? 0

    if let bundle = bundlePlaces, bundleBindings > docBindings {

        _ = savePlaces(bundle)
        print("✅ Обновлено из Bundle: \(bundle.count) заведений (\(bundleBindings) привязок)")
        return bundle
    }

    if let docs = documentsPlaces {
        print("✅ Загружено \(docs.count) заведений из Documents (\(docBindings) привязок)")
        return docs
    }

    if let bundle = bundlePlaces {
        print("✅ Загружено \(bundle.count) заведений из Bundle (\(bundleBindings) привязок)")
        return bundle
    }

    print("⚠️ campus-places.json не найден — используем встроенные данные")
    return []
}

@discardableResult
func savePlaces(_ places: [FoodPlace]) -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    guard let data = try? encoder.encode(places) else {
        print("⚠️ Не удалось закодировать campus-places.json")
        return false
    }

    do {
        try data.write(to: writablePlacesURL(), options: .atomic)
        print("✅ campus-places.json сохранен в Documents")
        return true
    } catch {
        print("⚠️ Не удалось сохранить campus-places.json: \(error.localizedDescription)")
        return false
    }
}

extension Array where Element == FoodPlace {

    func nearest(to cell: Cell, model: MapGridModel) -> FoodPlace? {
        let coord = model.coordinate(for: cell)
        return self.min(by: { a, b in
            let distA = distance(coord, a.coordinate)
            let distB = distance(coord, b.coordinate)
            return distA < distB
        })
    }

    func places(near cell: Cell, model: MapGridModel, radiusMeters: Double = 500) -> [FoodPlace] {
        let coord = model.coordinate(for: cell)
        return self.filter { place in
            distance(coord, place.coordinate) <= radiusMeters
        }
    }

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }
}
