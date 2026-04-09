import SwiftUI
import UIKit
import Combine

struct AStarMapView: UIViewRepresentable {

    @ObservedObject var model: MapGridModel
    var editMode: EditMode
    var brushRadius: Int = 5

    private static let mapImageSize = CGSize(width: 838, height: 686)

    private var cellW: CGFloat { Self.mapImageSize.width  / CGFloat(model.cols) }
    private var cellH: CGFloat { Self.mapImageSize.height / CGFloat(model.rows) }

    func makeUIView(context: Context) -> UIScrollView {
        let imgSize = Self.mapImageSize

        let scroll = UIScrollView()
        scroll.delegate                       = context.coordinator
        scroll.minimumZoomScale               = 0.4
        scroll.maximumZoomScale               = 15.0
        scroll.showsVerticalScrollIndicator   = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom                    = true
        scroll.backgroundColor                = .white

        let container = UIView(frame: CGRect(origin: .zero, size: imgSize))
        container.backgroundColor = .clear
        context.coordinator.container = container

        let mapImage  = UIImage(named: "mapEatTSU") ?? UIImage()
        let imageView = UIImageView(image: mapImage)
        imageView.frame         = CGRect(origin: .zero, size: imgSize)
        imageView.contentMode   = .scaleAspectFill
        imageView.clipsToBounds = true
        container.addSubview(imageView)

        let canvas = CanvasView(frame: CGRect(origin: .zero, size: imgSize))
        canvas.backgroundColor         = .clear
        canvas.isUserInteractionEnabled = true
        canvas.coordinator             = context.coordinator
        context.coordinator.canvas     = canvas
        container.addSubview(canvas)

        scroll.addSubview(container)
        scroll.contentSize = imgSize

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        canvas.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        canvas.addGestureRecognizer(longPress)

        DispatchQueue.main.async {
            context.coordinator.fitMap(in: scroll)
        }

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.editMode    = editMode
        context.coordinator.model       = model
        context.coordinator.cellW       = cellW
        context.coordinator.cellH       = cellH
        context.coordinator.brushRadius = brushRadius
        context.coordinator.canvas?.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, cellW: cellW, cellH: cellH)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {

        var model:    MapGridModel
        var editMode: EditMode = .navigate
        var cellW:    CGFloat
        var cellH:    CGFloat
        var brushRadius: Int = 5
        var zoomScale: CGFloat = 1

        private var brushAdding: Bool = true

        weak var canvas:    CanvasView?
        weak var container: UIView?

        init(model: MapGridModel, cellW: CGFloat, cellH: CGFloat) {
            self.model = model
            self.cellW = cellW
            self.cellH = cellH
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScale = scrollView.zoomScale
            centerContent(in: scrollView)
        }

        func centerContent(in scrollView: UIScrollView) {
            guard let c = container else { return }
            let offsetX = max((scrollView.bounds.width  - c.frame.width)  / 2, 0)
            let offsetY = max((scrollView.bounds.height - c.frame.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: offsetY, left: offsetX, bottom: offsetY, right: offsetX
            )
        }

        func fitMap(in scroll: UIScrollView) {
            guard scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            let imgSize = AStarMapView.mapImageSize
            let scaleX  = scroll.bounds.width  / imgSize.width
            let scaleY  = scroll.bounds.height / imgSize.height
            let scale   = min(scaleX, scaleY)
            scroll.setZoomScale(scale, animated: false)
            zoomScale = scale
            centerContent(in: scroll)
        }

        func cell(at point: CGPoint) -> Cell? {
            let col = Int(point.x / cellW)
            let row = Int(point.y / cellH)
            guard row >= 0, row < model.rows,
                  col >= 0, col < model.cols else { return nil }
            return Cell(row: row, col: col)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, editMode == .navigate else { return }
            let pt = gesture.location(in: canvas)
            guard let c = cell(at: pt) else { return }

            let cellType = model.grid[c.row][c.col]

            if model.bindingPlace != nil {
                guard cellType == .building else { return }
                if model.pendingBindingCell == c {
                    model.pendingBindingBuilding = nil
                    model.pendingBindingCell = nil
                } else {
                    model.selectBindingBuilding(from: c)
                }
                canvas?.setNeedsDisplay()
                return
            }

            if model.focusedPlace != nil, !model.routeToFocusedPlaceActive {
                if cellType == .building,
                   let focusedBuilding = model.focusedPlaceBuilding,
                   focusedBuilding.contains(c) {
                    model.clearFocusedPlaceMode()
                } else if cellType != .building {
                    model.clearFocusedPlaceMode()
                }
                canvas?.setNeedsDisplay()
                return
            }

            if cellType == .building {
                let buildingCells = model.floodFillBuilding(from: c)
                guard !buildingCells.isEmpty else { return }

                if let selectedStartBuilding = model.selectedStartBuilding,
                   selectedStartBuilding.contains(c) {
                    model.clearStartSelection()
                } else if let selectedEndBuilding = model.selectedEndBuilding,
                          selectedEndBuilding.contains(c) {
                    model.clearEndSelection()
                } else if model.startCell == nil {
                    model.selectedStartBuilding = buildingCells
                    model.startCell = c
                    model.updateSelectedBuildingPlaces(for: buildingCells)
                } else if model.endCell == nil {
                    model.selectedEndBuilding = buildingCells
                    model.endCell = c
                    model.updateSelectedBuildingPlaces(for: buildingCells)
                }
            } else {
                guard cellType != .obstacle, cellType != .barrier else { return }

                if model.startCell == c, model.selectedStartBuilding == nil {
                    model.clearStartSelection()
                } else if model.endCell == c, model.selectedEndBuilding == nil {
                    model.clearEndSelection()
                } else if model.startCell == nil {
                    model.startCell = c
                    model.grid[c.row][c.col] = .start
                    model.selectedBuildingPlaces = []
                } else if model.endCell == nil, c != model.startCell {
                    model.endCell = c
                    model.grid[c.row][c.col] = .end
                    model.selectedBuildingPlaces = []
                }
            }
            canvas?.setNeedsDisplay()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard editMode == .addBarrier else { return }
            let pt = gesture.location(in: canvas)
            guard let center = cell(at: pt) else { return }

            if gesture.state == .began {
                brushAdding = model.grid[center.row][center.col] != .barrier
            }

            guard gesture.state == .began || gesture.state == .changed else { return }

            applyBrush(at: center, adding: brushAdding)
            canvas?.setNeedsDisplay()
        }

        private func applyBrush(at center: Cell, adding: Bool) {
            let r = brushRadius
            for dr in -r...r {
                for dc in -r...r {
                    guard dr * dr + dc * dc <= r * r else { continue }
                    let nr = center.row + dr
                    let nc = center.col + dc
                    guard nr >= 0, nr < model.rows, nc >= 0, nc < model.cols else { continue }
                    let type = model.grid[nr][nc]
                    guard type != .building, type != .obstacle, type != .start, type != .end else { continue }

                    let cell = Cell(row: nr, col: nc)
                    if adding {
                        if type != .barrier {
                            model.grid[nr][nc] = .barrier
                            model.barrierCells.insert(cell)
                        }
                    } else {
                        if type == .barrier {
                            model.grid[nr][nc] = model.terrainCellType(nr, nc)
                            model.barrierCells.remove(cell)
                        }
                    }
                }
            }
        }
    }
}

final class CanvasView: UIView {

    weak var coordinator: AStarMapView.Coordinator?

    override func draw(_ rect: CGRect) {
        guard let ctx   = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }

        let model = coord.model
        let cw    = coord.cellW
        let ch    = coord.cellH
        let screenWidth = coord.canvas?.window?.windowScene?.screen.bounds.width ?? 390
        let markerRadius = selectionMarkerRadius(zoomScale: coord.zoomScale, screenWidth: screenWidth)

        drawBuildingHighlight(ctx: ctx, cells: model.selectedStartBuilding,
                              cw: cw, ch: ch,
                              color: UIColor.systemGreen.withAlphaComponent(0.35))
        drawBuildingHighlight(ctx: ctx, cells: model.selectedEndBuilding,
                              cw: cw, ch: ch,
                              color: UIColor.systemRed.withAlphaComponent(0.35))
        drawBuildingHighlight(ctx: ctx, cells: model.focusedPlaceBuilding,
                              cw: cw, ch: ch,
                              color: UIColor.systemYellow.withAlphaComponent(0.4))
        drawBuildingHighlight(ctx: ctx, cells: model.pendingBindingBuilding,
                              cw: cw, ch: ch,
                              color: UIColor.systemCyan.withAlphaComponent(0.45))

        if !model.barrierCells.isEmpty {
            ctx.setFillColor(UIColor.systemOrange.withAlphaComponent(0.75).cgColor)
            for cell in model.barrierCells {
                ctx.fill(CGRect(x: CGFloat(cell.col) * cw,
                                y: CGFloat(cell.row) * ch,
                                width: cw, height: ch))
            }
            ctx.setStrokeColor(UIColor(red: 0.8, green: 0.35, blue: 0, alpha: 1).cgColor)
            ctx.setLineWidth(max(cw * 0.12, 0.5))
            for cell in model.barrierCells {
                ctx.stroke(CGRect(x: CGFloat(cell.col) * cw,
                                  y: CGFloat(cell.row) * ch,
                                  width: cw, height: ch))
            }
        }

        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.25).cgColor)
        for cell in model.visitedCells {
            ctx.fill(CGRect(x: CGFloat(cell.col) * cw,
                            y: CGFloat(cell.row) * ch,
                            width: cw, height: ch))
        }

        if !model.frontierCells.isEmpty {
            ctx.setFillColor(UIColor.systemOrange.withAlphaComponent(0.45).cgColor)
            for cell in model.frontierCells {
                ctx.fill(CGRect(x: CGFloat(cell.col) * cw,
                                y: CGFloat(cell.row) * ch,
                                width: cw, height: ch))
            }
        }

        drawSmoothPath(ctx: ctx, path: model.pathCells, cw: cw, ch: ch)

        if let s = model.startCell {
            if model.selectedStartBuilding == nil {
                drawCellHighlight(ctx: ctx, cell: s, cw: cw, ch: ch,
                                  color: UIColor.systemGreen.withAlphaComponent(0.35))
            }
            drawSelectionMarker(ctx: ctx, row: s.row, col: s.col,
                                cw: cw, ch: ch,
                                radius: markerRadius,
                                color: .systemGreen, glyph: "A")
        }
        if let e = model.endCell {
            if model.selectedEndBuilding == nil {
                drawCellHighlight(ctx: ctx, cell: e, cw: cw, ch: ch,
                                  color: UIColor.systemRed.withAlphaComponent(0.35))
            }
            drawSelectionMarker(ctx: ctx, row: e.row, col: e.col,
                                cw: cw, ch: ch,
                                radius: markerRadius,
                                color: .systemRed, glyph: "B")
        }
    }

    private func selectionMarkerRadius(zoomScale: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let desiredScreenRadius = max(12, screenWidth * 0.032)
        return desiredScreenRadius / max(zoomScale, 0.35)
    }

    private func drawCellHighlight(ctx: CGContext,
                                   cell: Cell,
                                   cw: CGFloat, ch: CGFloat,
                                   color: UIColor) {
        let rect = CGRect(x: CGFloat(cell.col) * cw,
                          y: CGFloat(cell.row) * ch,
                          width: cw,
                          height: ch)
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(max(cw * 0.12, 0.75))
        ctx.stroke(rect.insetBy(dx: 0.4, dy: 0.4))
    }

    private func drawBuildingHighlight(ctx: CGContext,
                                       cells: Set<Cell>?,
                                       cw: CGFloat, ch: CGFloat,
                                       color: UIColor) {
        guard let cells = cells, !cells.isEmpty else { return }

        ctx.setFillColor(color.cgColor)
        for cell in cells {
            ctx.fill(CGRect(x: CGFloat(cell.col) * cw,
                            y: CGFloat(cell.row) * ch,
                            width: cw, height: ch))
        }

        guard let minR = cells.min(by: { $0.row < $1.row })?.row,
              let maxR = cells.max(by: { $0.row < $1.row })?.row,
              let minC = cells.min(by: { $0.col < $1.col })?.col,
              let maxC = cells.max(by: { $0.col < $1.col })?.col else { return }

        let boundingRect = CGRect(
            x: CGFloat(minC) * cw - 1,
            y: CGFloat(minR) * ch - 1,
            width:  CGFloat(maxC - minC + 1) * cw + 2,
            height: CGFloat(maxR - minR + 1) * ch + 2
        )
        ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(boundingRect)
    }

    private func drawSmoothPath(ctx: CGContext, path: [Cell],
                                cw: CGFloat, ch: CGFloat) {
        guard path.count >= 2 else { return }

        let points = path.map { cell in
            CGPoint(x: (CGFloat(cell.col) + 0.5) * cw,
                    y: (CGFloat(cell.row) + 0.5) * ch)
        }

        let simplified = douglasPeucker(points: points, epsilon: cw * 0.5)
        guard simplified.count >= 2 else { return }

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 0.8), blur: 2.5,
                      color: UIColor.black.withAlphaComponent(0.3).cgColor)

        let outerPath = CGMutablePath()
        outerPath.move(to: simplified[0])
        for i in 1..<simplified.count { outerPath.addLine(to: simplified[i]) }

        ctx.setStrokeColor(UIColor(red: 0.12, green: 0.32, blue: 0.65, alpha: 1.0).cgColor)
        ctx.setLineWidth(max(cw * 5.0, 3.5))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(outerPath)
        ctx.strokePath()
        ctx.restoreGState()

        let innerPath = CGMutablePath()
        innerPath.move(to: simplified[0])
        for i in 1..<simplified.count { innerPath.addLine(to: simplified[i]) }

        ctx.setStrokeColor(UIColor(red: 0.25, green: 0.56, blue: 1.0, alpha: 0.92).cgColor)
        ctx.setLineWidth(max(cw * 3.0, 2.0))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(innerPath)
        ctx.strokePath()
    }

    private func douglasPeucker(points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var maxDist: CGFloat = 0
        var maxIdx = 0
        let first = points[0]
        let last  = points[points.count - 1]

        for i in 1..<(points.count - 1) {
            let dist = perpendicularDist(point: points[i], lineA: first, lineB: last)
            if dist > maxDist {
                maxDist = dist
                maxIdx  = i
            }
        }

        if maxDist > epsilon {
            let left  = douglasPeucker(points: Array(points[...maxIdx]), epsilon: epsilon)
            let right = douglasPeucker(points: Array(points[maxIdx...]), epsilon: epsilon)
            return left.dropLast() + right
        } else {
            return [first, last]
        }
    }

    private func perpendicularDist(point p: CGPoint,
                                   lineA a: CGPoint,
                                   lineB b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let num = abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x)
        return num / sqrt(lenSq)
    }

    private func drawSelectionMarker(ctx: CGContext,
                         row: Int, col: Int,
                         cw: CGFloat, ch: CGFloat,
                         radius: CGFloat,
                         color: UIColor, glyph: String) {
        let cx = (CGFloat(col) + 0.5) * cw
        let cy = (CGFloat(row) + 0.5) * ch

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: radius * 0.16), blur: radius * 0.35,
                      color: UIColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(max(radius * 0.2, 1.5))
        ctx.strokeEllipse(in: CGRect(x: cx - radius, y: cy - radius,
                                     width: radius * 2, height: radius * 2))

        let font  = UIFont.systemFont(ofSize: radius * 1.08, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let str = glyph as NSString
        let sz  = str.size(withAttributes: attrs)
        str.draw(
            at: CGPoint(x: cx - sz.width / 2, y: cy - sz.height / 2),
            withAttributes: attrs
        )
    }
}
