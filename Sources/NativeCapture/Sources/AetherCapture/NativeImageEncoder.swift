import Foundation
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

public struct EncodedImage: Sendable {
    public var bytes: Data
    public var format: CaptureFormat
    public init(bytes: Data, format: CaptureFormat) { self.bytes = bytes; self.format = format }
}

public protocol AetherImageEncoder: Sendable {
    func encode(_ raster: AetherRaster, preferred: CaptureFormat, quality: Double) throws -> EncodedImage
}

/// Apple ImageIO only: whatever the Mac natively encodes is what gets saved.
/// WebP is used only when it was asked for AND the OS reports an encoder —
/// some macOS releases decode WebP without being able to encode it. The
/// fallback order is JPEG then PNG, both universally available through
/// ImageIO, so a capture always lands an image instead of an error.
/// The returned extension ALWAYS matches the successfully encoded bytes.
public struct NativeImageEncoder: AetherImageEncoder {
    public init() {}

    public func encode(_ raster: AetherRaster, preferred: CaptureFormat, quality: Double) throws -> EncodedImage {
        #if canImport(CoreGraphics) && canImport(ImageIO)
        let destinations = CGImageDestinationCopyTypeIdentifiers() as! [String]
        let webpID = destinations.first(where: { $0.lowercased().contains("webp") })
        var attempts: [(CaptureFormat, String)] = []
        func offer(_ format: CaptureFormat, _ identifier: String) {
            guard destinations.contains(identifier),
                  !attempts.contains(where: { $0.0 == format })
            else { return }
            attempts.append((format, identifier))
        }
        // What was asked for goes first, when the OS can do it.
        switch preferred {
        case .webp:
            if let webpID { attempts.append((.webp, webpID)) }
        case .png:
            offer(.png, "public.png")
        case .jpeg:
            offer(.jpeg, "public.jpeg")
        }
        // Then whatever macOS natively encodes, in a stable order.
        offer(.jpeg, "public.jpeg")
        offer(.png, "public.png")
        if let webpID { offer(.webp, webpID) }
        let provider = CGDataProvider(data: raster.rgba as CFData)
        guard let provider, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: raster.width, height: raster.height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: raster.bytesPerRow, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw CaptureFailure.invalidRaster }
        for (format, identifier) in attempts {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, identifier as CFString, 1, nil) else {
                continue
            }
            let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, image, props as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                return EncodedImage(bytes: output as Data, format: format)
            }
        }
        throw CaptureFailure.unsupportedEncoding
        #else
        throw CaptureFailure.unsupportedEncoding // Compile/test core on non-Apple hosts.
        #endif
    }
}
