import SwiftUI

struct DecisionTreeView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "lightbulb.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)

                Text("Куда пойти на обед?")
                    .font(.title2).bold()

                Text("Дерево решений подберёт кафе с учётом вашего расположения, бюджета, свободного времени и предпочтений.\n\nСкоро будет готово!")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .navigationTitle("Советник")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    DecisionTreeView()
}
