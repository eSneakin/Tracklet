import CoreGraphics
import Foundation
import ImageIO

enum WidgetArtworkImage {
    /// Bake monochrome into pixels: WidgetKit's remote renderer must not depend on a
    /// SwiftUI saturation effect that can work in previews but be lost on the desktop.
    /// The cached original remains untouched, so switching styles is reversible.
    static func make(data: Data, style: ArtworkStyle) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { return nil }
        guard style == .monochrome else { return image }
        guard let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: gray,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
