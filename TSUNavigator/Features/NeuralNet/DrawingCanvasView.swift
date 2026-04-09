import SwiftUI
import UIKit

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var image: UIImage?
    @Binding var isEmpty: Bool
    @Binding var isDrawing: Bool
    let clearToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(image: $image, isEmpty: $isEmpty, isDrawing: $isDrawing)
    }

    func makeUIView(context: Context) -> PixelCanvasView {
        let view = PixelCanvasView()
        view.onImageChanged = { image, isEmpty in
            context.coordinator.image.wrappedValue = image
            context.coordinator.isEmpty.wrappedValue = isEmpty
        }
        view.onDrawingChanged = { isDrawing in
            context.coordinator.isDrawing.wrappedValue = isDrawing
        }
        return view
    }

    func updateUIView(_ uiView: PixelCanvasView, context: Context) {
        if uiView.clearToken != clearToken {
            uiView.clearToken = clearToken
            uiView.clearCanvas()
        }
    }

    final class Coordinator {
        var image: Binding<UIImage?>
        var isEmpty: Binding<Bool>
        var isDrawing: Binding<Bool>

        init(image: Binding<UIImage?>, isEmpty: Binding<Bool>, isDrawing: Binding<Bool>) {
            self.image = image
            self.isEmpty = isEmpty
            self.isDrawing = isDrawing
        }
    }
}

final class PixelCanvasView: UIView {
    var onImageChanged: ((UIImage?, Bool) -> Void)?
    var onDrawingChanged: ((Bool) -> Void)?
    var clearToken = 0

    private let gridSize = 50
    private let brushDiameter = 4
    private var pixels = Array(repeating: Array(repeating: false, count: 50), count: 50)
    private var previousCell: CGPoint?

    private var blockingPan: UIPanGestureRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isMultipleTouchEnabled = false
        contentMode = .redraw
        isExclusiveTouch = true

        blockingPan = UIPanGestureRecognizer(target: nil, action: nil)
        blockingPan.cancelsTouchesInView = false
        blockingPan.delaysTouchesEnded = false
        addGestureRecognizer(blockingPan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = 16
        layer.masksToBounds = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let scroll = enclosingScrollView() {
            scroll.panGestureRecognizer.require(toFail: blockingPan)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let cell = cellPoint(for: touches.first?.location(in: self)) else { return }
        setDrawing(true)
        previousCell = cell
        stampBrush(at: cell)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let cell = cellPoint(for: touches.first?.location(in: self)) else { return }
        defer { previousCell = cell }

        guard let previousCell else {
            stampBrush(at: cell)
            return
        }

        drawLine(from: previousCell, to: cell)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let cell = cellPoint(for: touches.first?.location(in: self)) {
            drawLine(from: previousCell ?? cell, to: cell)
        }
        previousCell = nil
        setDrawing(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        previousCell = nil
        setDrawing(false)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)

        let pixelWidth = bounds.width / CGFloat(gridSize)
        let pixelHeight = bounds.height / CGFloat(gridSize)

        context.setFillColor(UIColor.black.cgColor)
        for row in 0..<gridSize {
            for column in 0..<gridSize where pixels[row][column] {
                context.fill(
                    CGRect(
                        x: CGFloat(column) * pixelWidth,
                        y: CGFloat(row) * pixelHeight,
                        width: pixelWidth,
                        height: pixelHeight
                    )
                )
            }
        }

        context.saveGState()
        context.setStrokeColor(UIColor.systemGray4.withAlphaComponent(0.25).cgColor)
        context.setLineWidth(0.5)

        for index in 0...gridSize {
            let x = CGFloat(index) * pixelWidth
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))

            let y = CGFloat(index) * pixelHeight
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }

        context.strokePath()
        context.restoreGState()
    }

    func clearCanvas() {
        pixels = Array(repeating: Array(repeating: false, count: gridSize), count: gridSize)
        previousCell = nil
        setDrawing(false)
        setNeedsDisplay()
        publishSnapshot()
    }

    private func cellPoint(for point: CGPoint?) -> CGPoint? {
        guard let point else { return nil }
        let pixelWidth = bounds.width / CGFloat(gridSize)
        let pixelHeight = bounds.height / CGFloat(gridSize)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let x = min(max(Int(point.x / pixelWidth), 0), gridSize - 1)
        let y = min(max(Int(point.y / pixelHeight), 0), gridSize - 1)
        return CGPoint(x: x, y: y)
    }

    private func drawLine(from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let steps = max(abs(dx), abs(dy))

        if steps == 0 {
            stampBrush(at: end)
            return
        }

        for step in 0...Int(steps) {
            let progress = CGFloat(step) / steps
            let x = start.x + dx * progress
            let y = start.y + dy * progress
            stampBrush(at: CGPoint(x: round(x), y: round(y)), shouldPublish: false)
        }

        setNeedsDisplay()
        publishSnapshot()
    }

    private func stampBrush(at point: CGPoint, shouldPublish: Bool = true) {
        let radius = Double(brushDiameter) / 2.0
        let radiusSquared = radius * radius
        let centerX = Int(point.x)
        let centerY = Int(point.y)
        let minOffset = -Int(ceil(radius))
        let maxOffset = Int(ceil(radius))

        for rowOffset in minOffset...maxOffset {
            for columnOffset in minOffset...maxOffset {
                let dx = Double(columnOffset)
                let dy = Double(rowOffset)
                guard dx * dx + dy * dy <= radiusSquared else { continue }

                let row = centerY + rowOffset
                let column = centerX + columnOffset
                guard row >= 0, row < gridSize, column >= 0, column < gridSize else { continue }
                pixels[row][column] = true
            }
        }

        setNeedsDisplay()
        if shouldPublish {
            publishSnapshot()
        }
    }

    private func publishSnapshot() {
        onImageChanged?(snapshotImage(), pixels.allSatisfy { row in row.allSatisfy { !$0 } })
    }

    private func setDrawing(_ isDrawing: Bool) {
        onDrawingChanged?(isDrawing)
        enclosingScrollView()?.isScrollEnabled = !isDrawing
    }

    private func snapshotImage() -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: ImagePreprocessor.canvasSize, format: format)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: ImagePreprocessor.canvasSize))

            UIColor.black.setFill()
            let pixelSide = ImagePreprocessor.canvasSize.width / CGFloat(gridSize)

            for row in 0..<gridSize {
                for column in 0..<gridSize where pixels[row][column] {
                    context.fill(
                        CGRect(
                            x: CGFloat(column) * pixelSide,
                            y: CGFloat(row) * pixelSide,
                            width: pixelSide,
                            height: pixelSide
                        )
                    )
                }
            }
        }
    }

    private func enclosingScrollView() -> UIScrollView? {
        var currentView = superview
        while let view = currentView {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            currentView = view.superview
        }
        return nil
    }

}
