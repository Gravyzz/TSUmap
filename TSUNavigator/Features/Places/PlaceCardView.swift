import SwiftUI

struct PlaceCardView: View {
    let place: FoodPlace
    let onShowOnMap: () -> Void
    let onBindBuilding: () -> Void
    let onRatePlace: () -> Void
    let onResetRating: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showResetAlert = false
    @State private var resetPassword = ""
    @State private var resetErrorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    headerSection

                    Divider()

                    infoChips

                    Divider()

                    Text(place.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Divider()

                    scheduleSection

                    Button {
                        dismiss()
                        onShowOnMap()
                    } label: {
                        Label("Показать на карте", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!place.isShownOnCampusMap)

                    if !place.isShownOnCampusMap {
                        Text("Это заведение не привязано к карте кампуса.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        dismiss()
                        onRatePlace()
                    } label: {
                        Label("Поставить оценку", systemImage: "pencil.and.scribble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        dismiss()
                        onBindBuilding()
                    } label: {
                        Label("Привязать здание", systemImage: "building.2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Divider()
                    menuSection

                    Divider()

                    Button(role: .destructive) {
                        resetPassword = ""
                        resetErrorMessage = nil
                        showResetAlert = true
                    } label: {
                        Label("Сбросить оценку", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if let resetErrorMessage {
                        Text(resetErrorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Сбросить оценку", isPresented: $showResetAlert) {
                TextField("Пароль", text: $resetPassword)
                Button("Отмена", role: .cancel) {}
                Button("Сбросить", role: .destructive) {
                    if resetPassword == "Денис Змеев" {
                        dismiss()
                        onResetRating()
                    } else {
                        resetErrorMessage = "Неверный пароль."
                    }
                }
            } message: {
                Text("Для сброса всех оценок введите пароль.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: place.category.icon)
                    .font(.title2)
                    .foregroundColor(categoryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(place.category.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(categoryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.12))
                    .clipShape(Capsule())

                Text(place.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let rating = place.rating {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(String(format: "%.1f", rating))
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }
                    Text("\(place.ratingsCount) оценок")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var infoChips: some View {
        HStack(spacing: 8) {
            chipView(
                icon: "banknote",
                text: place.priceLevel.label,
                color: priceColor
            )

            Text(place.priceLevel.short)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(priceColor)

            Spacer()

            chipView(
                icon: isLikelyOpen ? "clock.badge.checkmark" : "clock.badge.xmark",
                text: isLikelyOpen ? "Открыто" : "Закрыто",
                color: isLikelyOpen ? .green : .red
            )
        }
    }

    private func chipView(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var scheduleSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundColor(.blue)
            Text(place.schedule.displayText)
                .font(.subheadline)
            Spacer()
        }
    }

    private var menuSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Меню")
                .font(.headline)

            ForEach(place.menuByCategory, id: \.category) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: group.category.icon)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(group.category.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.top, 4)

                    ForEach(group.items) { item in
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                            Spacer()
                            if !item.priceText.isEmpty {
                                Text(item.priceText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if group.category != place.menuByCategory.last?.category {
                    Divider().padding(.leading, 20)
                }
            }
        }
    }

    private var categoryColor: Color {
        switch place.category {
        case .vending:    return .purple
        case .buffet:     return .orange
        case .cafeteria:  return .blue
        case .canteen:    return .green
        case .coffeeshop: return .brown
        case .cafe:       return .red
        case .fastfood:   return .red
        case .gastrohall: return .yellow
        case .shop:       return .teal
        }
    }

    private var priceColor: Color {
        switch place.priceLevel {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }

    private var isLikelyOpen: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isWeekend = (weekday == 1 || weekday == 7)

        if place.schedule.note?.contains("Круглосуточно") == true { return true }
        if place.schedule.note?.contains("Ежедневно") == true {
            return parseHours(place.schedule.note, hour: hour)
        }

        if isWeekend {
            guard let we = place.schedule.weekends else { return false }
            return parseHours(we, hour: hour)
        } else {
            guard let wd = place.schedule.weekdays else { return false }
            return parseHours(wd, hour: hour)
        }
    }

    private func parseHours(_ text: String?, hour: Int) -> Bool {
        guard let text = text else { return false }
        let pattern = #"(\d{1,2}):(\d{2})\s*[–-]\s*(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 5 else { return false }

        func intAt(_ i: Int) -> Int? {
            guard let range = Range(match.range(at: i), in: text) else { return nil }
            return Int(text[range])
        }

        guard let openH = intAt(1), let closeH = intAt(3) else { return false }
        return hour >= openH && hour < closeH
    }
}

struct PlacesListView: View {
    let places: [FoodPlace]
    let onShowOnMap: (FoodPlace) -> Void
    let onBindBuilding: (FoodPlace) -> Void
    let onRatePlace: (FoodPlace) -> Void
    let onResetRating: (FoodPlace) -> Void
    @State private var selectedPlace: FoodPlace? = nil
    @State private var searchText = ""
    @State private var selectedCategory: PlaceCategory? = nil

    var filteredPlaces: [FoodPlace] {
        var result = places
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.description.lowercased().contains(q) ||
                $0.menu.contains(where: { $0.name.lowercased().contains(q) })
            }
        }
        return result
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, "Все")
                        ForEach(PlaceCategory.allCases, id: \.self) { cat in
                            filterChip(cat, cat.label)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                List(filteredPlaces) { place in
                    Button {
                        selectedPlace = place
                    } label: {
                        PlaceRowView(place: place)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
            }
            .navigationTitle("Заведения")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск по названию или блюду")
            .sheet(item: $selectedPlace) { place in
                PlaceCardView(place: place) {
                    onShowOnMap(place)
                } onBindBuilding: {
                    onBindBuilding(place)
                } onRatePlace: {
                    onRatePlace(place)
                } onResetRating: {
                    onResetRating(place)
                }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func filterChip(_ category: PlaceCategory?, _ label: String) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

struct PlaceRowView: View {
    let place: FoodPlace

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.category.icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(place.address)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text(place.priceLevel.short)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)

                    Text(place.schedule.displayText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let r = place.rating {
                        HStack(spacing: 1) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                            Text(String(format: "%.1f", r))
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
