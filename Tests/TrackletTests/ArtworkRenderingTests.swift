import AppKit
import SwiftUI
import XCTest
@testable import Tracklet

final class ArtworkRenderingTests: XCTestCase {
    @MainActor
    func testWidgetMonochromeSurvivesImageSerializationAndStyleSwitching() throws {
        let sample = try render(LinearGradient(colors: [.red, .blue], startPoint: .leading,
                                              endPoint: .trailing).frame(width: 64, height: 32))
        let original = try XCTUnwrap(sample.representation(using: .png, properties: [:]))
        // Inspect the image sent to WidgetKit, not a SwiftUI screenshot with saturation.
        for style in [ArtworkStyle.fullColor, .monochrome, .blurred, .fullColor, .monochrome] {
            let image = try XCTUnwrap(WidgetArtworkImage.make(data: original, style: style))
            let encoded = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let decoded = try XCTUnwrap(NSBitmapImageRep(data: encoded))
            XCTAssertEqual(decoded.pixelsWide, 64)
            XCTAssertEqual(decoded.pixelsHigh, 32)
            if style == .monochrome {
                XCTAssertEqual(image.colorSpace?.model, .monochrome)
                for y in 0..<decoded.pixelsHigh {
                    for x in 0..<decoded.pixelsWide {
                        let color = try XCTUnwrap(decoded.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.01)
                        XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 0.01)
                    }
                }
            } else {
                let color = try pixel(decoded)
                XCTAssertGreaterThan(abs(color.redComponent - color.blueComponent), 0.05)
            }
        }
        XCTAssertNil(WidgetArtworkImage.make(data: Data(), style: .monochrome))
        XCTAssertNil(WidgetArtworkImage.make(data: Data("invalid image".utf8), style: .fullColor))
    }

    @MainActor
    func testMonochromeAppliesToCachedArtworkAndPlaceholder() throws {
        let image = try render(Color.red.frame(width: 72, height: 72))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
        for file in [url, nil] as [URL?] {
            let color = try render(ArtworkView(url: nil, size: 72, cachedFileURL: file, style: .fullColor))
            let mono = try render(ArtworkView(url: nil, size: 72, cachedFileURL: file, style: .monochrome))
            let coloredPixel = try pixel(color)
            let grayPixel = try pixel(mono)
            XCTAssertGreaterThan(abs(coloredPixel.redComponent - coloredPixel.blueComponent), 0.05)
            XCTAssertEqual(grayPixel.redComponent, grayPixel.greenComponent, accuracy: 0.02)
            XCTAssertEqual(grayPixel.greenComponent, grayPixel.blueComponent, accuracy: 0.02)
        }
    }

    func testTimeFormattingAndInvalidProgressNeverOverflow() {
        XCTAssertEqual(PlaybackTime.format(123), "2:03")
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(PlaybackTime.format(invalid), "—")
        }
        XCTAssertEqual(PlaybackTime.format(.greatestFiniteMagnitude), "525600:00")
        let state = PlaybackState(item: nil, isPlaying: true, progressAtFetch: .nan, device: nil, fetchedAt: Date())
        XCTAssertNil(state.progress())
    }

    @MainActor
    private func render<V: View>(_ view: V) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func pixel(_ bitmap: NSBitmapImageRep) throws -> NSColor {
        // Sample away from the placeholder glyph and rounded corners.
        try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 3, y: bitmap.pixelsHigh / 3)?.usingColorSpace(.sRGB))
    }
}
