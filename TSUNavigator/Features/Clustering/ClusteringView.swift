import SwiftUI

struct ClusteringView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)

                Text("Кластеризация кафе")
                    .font(.title2).bold()

                Text("Алгоритм K-средних определит зоны питания вокруг кампуса ТГУ.\n\nСкоро будет готово!")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .navigationTitle("Кафе")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ClusteringView()
}
