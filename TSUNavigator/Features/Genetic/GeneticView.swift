import SwiftUI

struct GeneticView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "bag.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("Маршрут за обедом")
                    .font(.title2).bold()

                Text("Генетический алгоритм построит оптимальный маршрут для сбора всех нужных блюд из разных кафе.\n\nСкоро будет готово!")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .navigationTitle("Обед")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    GeneticView()
}
