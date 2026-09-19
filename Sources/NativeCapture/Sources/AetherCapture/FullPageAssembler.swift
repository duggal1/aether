import Foundation

/// Bounded optional whole-page composite. Tiles remain the canonical output.
/// Require identical width/stride; copy rows, never resample rendered pixels.
public enum FullPageAssembler {
    public static func join(_ tiles: [AetherRaster], maximumPixels: Int) throws -> AetherRaster? {
        guard let first = tiles.first else { return nil }
        let width = first.width
        guard width > 0, tiles.allSatisfy({ $0.width == width && $0.bytesPerRow == first.bytesPerRow }) else {
            throw CaptureFailure.invalidRaster
        }
        let height = tiles.reduce(0) { $0 + $1.height }
        guard height > 0, width <= maximumPixels / height else { return nil }
        let rowBytes = width * 4
        var buffer = Data(count: height * rowBytes)
        buffer.withUnsafeMutableBytes { dst in
            guard let target = dst.baseAddress else { return }
            var targetRow = 0
            for tile in tiles {
                tile.rgba.withUnsafeBytes { src in
                    guard let source = src.baseAddress else { return }
                    for row in 0..<tile.height {
                        memcpy(target.advanced(by: targetRow * rowBytes),
                               source.advanced(by: row * tile.bytesPerRow), rowBytes)
                        targetRow += 1
                    }
                }
            }
        }
        return try AetherRaster(rgba: buffer, width: width, height: height, bytesPerRow: rowBytes)
    }
}
