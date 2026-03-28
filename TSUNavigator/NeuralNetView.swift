import SwiftUI

struct NeuralNetView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)

                Text("Оценка заведения")
                    .font(.title2).bold()

                Text("Нарисуйте оценку от 0 до 9 на сетке 5×5 пикселей. Нейронная сеть определит нарисованную цифру.\n\nСкоро будет готово!")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .navigationTitle("Оценка")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NeuralNetView()
}
