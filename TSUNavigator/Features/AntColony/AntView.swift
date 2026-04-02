import SwiftUI

struct AntView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "figure.walk.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.brown)

                Text("Прогулка по роще")
                    .font(.title2).bold()

                Text("Муравьиный алгоритм построит оптимальный маршрут обхода всех достопримечательностей университетской рощи ТГУ.\n\nСкоро будет готово!")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .navigationTitle("Прогулка")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AntView()
}
