import Foundation
import ImageIO
import Testing
@testable import AetherCapture

@Test func allFormatsDecodeAndMatchDeclaredType() throws {
    let raster = try AetherRaster(rgba: Data(repeating: 255, count: 16 * 12 * 4), width: 16, height: 12, bytesPerRow: 64)
    let destinations = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    for format in [CaptureFormat.webp, .jpeg, .png] {
        let image = try NativeImageEncoder().encode(raster, preferred: format, quality: 0.92)
        let source = try #require(CGImageSourceCreateWithData(image.bytes as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 16)
        #expect(decoded.height == 12)
        let identifier = CGImageSourceGetType(source) as String?
        switch image.format {
        case .jpeg: #expect(identifier == "public.jpeg")
        case .png: #expect(identifier == "public.png")
        case .webp: #expect(identifier?.lowercased().contains("webp") == true)
        }
        if format == .png { #expect(image.format == .png) }
        if format == .jpeg { #expect(image.format == .jpeg) }
        if format == .webp && !destinations.contains(where: { $0.lowercased().contains("webp") }) {
            #expect(image.format == .jpeg)
        }
    }
}

@Test func pngPreservesPixelsAndPaddedStride() throws {
    let raster = try AetherRaster(rgba: Data([255, 0, 0, 255, 0, 255, 0, 255, 9, 9, 9, 9, 0, 0, 255, 255, 255, 255, 255, 255, 9, 9, 9, 9]), width: 2, height: 2, bytesPerRow: 12)
    let encoded = try NativeImageEncoder().encode(raster, preferred: .png, quality: 1)
    let source = try #require(CGImageSourceCreateWithData(encoded.bytes as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let data = try #require(image.dataProvider?.data) as Data
    #expect(image.bitsPerPixel == 32)
    #expect(Array(data.prefix(8)) == [255, 0, 0, 255, 0, 255, 0, 255])
    #expect(Array(data[image.bytesPerRow..<image.bytesPerRow + 8]) == [0, 0, 255, 255, 255, 255, 255, 255])
}
