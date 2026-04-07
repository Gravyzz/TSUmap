import SwiftUI

struct NeuralNetView: View {
    let places: [FoodPlace]
    @Binding var selectedPlaceID: String?
    let onSubmitRating: (String, Int) -> Void

    @StateObject private var viewModel = PredictionViewModel()
    @State private var canvasImage: UIImage?
    @State private var isCanvasEmpty = true
    @State private var isDrawing = false
    @State private var clearToken = 0
    @State private var submissionMessage: String?

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    let horizontalPadding: CGFloat = 16
                    let verticalPadding: CGFloat = 16
                    let availableWidth = geometry.size.width - horizontalPadding * 2
                    let canvasSide = min(availableWidth, max(220, geometry.size.height * 0.48))

                    VStack(spacing: 16) {
                        placeSelectionSection
                        canvasSection(canvasSide: canvasSide)
                        resultSection
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                }
                .scrollDisabled(isDrawing)
            }
            .navigationTitle("Нейронная сеть")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        clearToken += 1
                        canvasImage = nil
                        isCanvasEmpty = true
                        submissionMessage = nil
                        viewModel.clearMessages()
                        viewModel.clearPrediction()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .background(InteractivePopDisabledView())
            .onChange(of: canvasImage) { _, image in
                viewModel.predictLive(from: image, isCanvasEmpty: isCanvasEmpty)
            }
            .onChange(of: isCanvasEmpty) { _, empty in
                viewModel.predictLive(from: canvasImage, isCanvasEmpty: empty)
            }
        }
    }

    private func canvasSection(canvasSide: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Введите оценку")
                    .font(.headline)
                Spacer()
                Text("50×50")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            DrawingCanvasView(
                image: $canvasImage,
                isEmpty: $isCanvasEmpty,
                isDrawing: $isDrawing,
                clearToken: clearToken
            )
                .frame(width: canvasSide, height: canvasSide)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)

            Text("Нарисуйте одну цифру крупно и по центру.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .layoutPriority(1)
    }

    private var placeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Кому ставим оценку")
                .font(.headline)

            Picker("Заведение", selection: ratingPlaceBinding) {
                Text("Выберите заведение").tag(String?.none)
                ForEach(places) { place in
                    Text(place.name).tag(Optional(place.id))
                }
            }
            .pickerStyle(.menu)

            if let selectedPlace {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.orange)
                    Text(selectedPlace.rating.map { String(format: "%.1f", $0) } ?? "Нет оценок")
                        .font(.subheadline.weight(.semibold))
                    Text("· \(selectedPlace.ratingsCount) оценок")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var resultSection: some View {
        if let predictedDigit = viewModel.predictedDigit,
           let confidence = viewModel.confidence {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Предсказание: \(predictedDigit)")
                        .font(.title2.weight(.bold))
                    Text("\(String(format: "%.2f", confidence * 100))%")
                        .font(.headline)
                        .foregroundColor(.green)
                }

                VStack(spacing: 8) {
                    ForEach(Array(viewModel.probabilities.enumerated()), id: \.offset) { index, probability in
                        HStack(spacing: 10) {
                            Text("\(index)")
                                .frame(width: 20, alignment: .leading)
                                .font(.caption.monospacedDigit())

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.gray.opacity(0.15))

                                    Capsule()
                                        .fill(index == predictedDigit ? Color.blue : Color.gray.opacity(0.45))
                                        .frame(width: geometry.size.width * CGFloat(probability))
                                }
                            }
                            .frame(height: 10)

                            Text("\(String(format: "%.2f", probability * 100))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 58, alignment: .trailing)
                        }
                        .frame(height: 14)
                    }
                }

                Button {
                    submitRecognizedRating(predictedDigit)
                } label: {
                    Label("Поставить оценку", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPlace == nil)

                if let submissionMessage {
                    Text(submissionMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        } else if viewModel.model != nil {
            Text("Начните рисовать цифру, результат появится автоматически.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var ratingPlaceBinding: Binding<String?> {
        Binding(
            get: { selectedPlaceID },
            set: { newValue in
                selectedPlaceID = newValue
                submissionMessage = nil
            }
        )
    }

    private var selectedPlace: FoodPlace? {
        guard let selectedPlaceID else { return nil }
        return places.first(where: { $0.id == selectedPlaceID })
    }

    private func submitRecognizedRating(_ value: Int) {
        guard let selectedPlaceID else { return }
        onSubmitRating(selectedPlaceID, value)
        submissionMessage = "Оценка \(value) сохранена."
    }
}

private struct InteractivePopDisabledView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.popGestureBlocker = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }

    final class Controller: UIViewController {
        weak var popGestureBlocker: Coordinator?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = popGestureBlocker
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if navigationController?.interactivePopGestureRecognizer?.delegate === popGestureBlocker {
                navigationController?.interactivePopGestureRecognizer?.delegate = nil
            }
        }
    }
}

#Preview {
    NeuralNetView(places: [], selectedPlaceID: .constant(nil)) { _, _ in }
}
