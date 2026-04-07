import CoreGraphics
import UIKit

enum ImagePreprocessorError: LocalizedError {
    case invalidImage
    case emptyDrawing

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Не удалось получить пиксели изображения."
        case .emptyDrawing:
            return "Рисунок пустой. Нарисуйте цифру перед распознаванием."
        }
    }
}

struct ImagePreprocessor {
    static let canvasSize = CGSize(width: 50, height: 50)
    private static let targetDimension = 50
    private static let threshold: Float = 0.05
    private static let contentInset: CGFloat = 4

    func preprocess(_ image: UIImage) throws -> [Float] {
        guard let cgImage = image.cgImage else {
            throw ImagePreprocessorError.invalidImage
        }

        let grayscale = try makeGrayscaleBuffer(from: cgImage)
        guard let boundingBox = detectBoundingBox(in: grayscale) else {
            throw ImagePreprocessorError.emptyDrawing
        }

        let cropped = crop(grayscale, to: boundingBox)
        return drawCentered(cropped, sourceSize: boundingBox.size)
    }

    private func makeGrayscaleBuffer(from cgImage: CGImage) throws -> [Float] {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var rawBytes = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rawBytes,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ImagePreprocessorError.invalidImage
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var grayscale = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let base = index * bytesPerPixel
            let red = Float(rawBytes[base]) / 255
            let green = Float(rawBytes[base + 1]) / 255
            let blue = Float(rawBytes[base + 2]) / 255
            let alpha = Float(rawBytes[base + 3]) / 255
            let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
            grayscale[index] = max(0, min(1, (1 - luminance) * alpha))
        }

        return grayscale
    }

    private func detectBoundingBox(in pixels: [Float]) -> CGRect? {
        let side = Self.targetDimension
        var minX = side
        var minY = side
        var maxX = -1
        var maxY = -1

        for y in 0..<side {
            for x in 0..<side {
                if pixels[y * side + x] > Self.threshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private func crop(_ pixels: [Float], to rect: CGRect) -> [Float] {
        let sourceWidth = Self.targetDimension
        let croppedWidth = Int(rect.width)
        let croppedHeight = Int(rect.height)
        var cropped = [Float](repeating: 0, count: croppedWidth * croppedHeight)

        for y in 0..<croppedHeight {
            for x in 0..<croppedWidth {
                let sourceX = Int(rect.minX) + x
                let sourceY = Int(rect.minY) + y
                cropped[y * croppedWidth + x] = pixels[sourceY * sourceWidth + sourceX]
            }
        }

        return cropped
    }

    private func drawCentered(_ cropped: [Float], sourceSize: CGSize) -> [Float] {
        let side = Self.targetDimension
        let croppedWidth = max(1, Int(sourceSize.width))
        let croppedHeight = max(1, Int(sourceSize.height))
        let usableSide = CGFloat(side) - Self.contentInset * 2
        let scale = min(usableSide / CGFloat(croppedWidth), usableSide / CGFloat(croppedHeight))
        let scaledWidth = max(1, Int(round(CGFloat(croppedWidth) * scale)))
        let scaledHeight = max(1, Int(round(CGFloat(croppedHeight) * scale)))
        let offsetX = (side - scaledWidth) / 2
        let offsetY = (side - scaledHeight) / 2

        var output = [Float](repeating: 0, count: side * side)
        for y in 0..<scaledHeight {
            for x in 0..<scaledWidth {
                let sourceX = min(croppedWidth - 1, Int(CGFloat(x) / scale))
                let sourceY = min(croppedHeight - 1, Int(CGFloat(y) / scale))
                let value = cropped[sourceY * croppedWidth + sourceX]
                output[(offsetY + y) * side + (offsetX + x)] = max(0, min(1, value))
            }
        }

        return output
    }
}

