import Foundation
import AetherRenderInfrastructure

public enum MetalBackendAvailability {
    public static var supported: Bool {
        #if canImport(Metal)
        true
        #else
        false
        #endif
    }
}

#if canImport(Metal)
import Metal

public enum MetalRendererError: Error {
    case deviceUnavailable, compilationFailed, pipelineFailed, allocationFailed, commandFailed, invalidTexture
}

public struct MetalRGBA: Sendable {
    public let r: Float
    public let g: Float
    public let b: Float
    public let a: Float

    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

public struct MetalQuad {
    public let rect: CaptureRect
    public let clip: CaptureRect?
    public let color: MetalRGBA
    public let texture: MTLTexture?

    public init(rect: CaptureRect, clip: CaptureRect? = nil, color: MetalRGBA = MetalRGBA(1, 1, 1), texture: MTLTexture? = nil) {
        self.rect = rect; self.clip = clip; self.color = color; self.texture = texture
    }
}

public final class MetalOffscreenRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let white: MTLTexture

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw MetalRendererError.deviceUnavailable
        }
        let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut { float4 position [[position]]; float2 uv; };
        vertex VertexOut quadVertex(const device float4 *vertices [[buffer(0)]],
                                    constant float2 &size [[buffer(1)]], uint id [[vertex_id]]) {
            float4 vertex = vertices[id];
            VertexOut result;
            result.position = float4(vertex.xy / size * float2(2.0, -2.0) + float2(-1.0, 1.0), 0, 1);
            result.uv = vertex.zw;
            return result;
        }
        fragment float4 quadFragment(VertexOut in [[stage_in]],
                                      texture2d<float> image [[texture(0)]],
                                      constant float4 &tint [[buffer(0)]]) {
            constexpr sampler sampleFilter(filter::linear, address::clamp_to_edge);
            return image.sample(sampleFilter, in.uv) * tint;
        }
        """
        let library = try device.makeLibrary(source: shader, options: nil)
        guard let vertex = library.makeFunction(name: "quadVertex"),
              let fragment = library.makeFunction(name: "quadFragment") else {
            throw MetalRendererError.compilationFailed
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let whiteDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        whiteDescriptor.usage = .shaderRead
        guard let white = device.makeTexture(descriptor: whiteDescriptor) else { throw MetalRendererError.allocationFailed }
        var pixel: [UInt8] = [255, 255, 255, 255]
        pixel.withUnsafeBytes { bytes in white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: 4) }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.white = white
    }

    public func makeImage(rgba: Data, width: Int, height: Int) throws -> MTLTexture {
        guard width > 0, height > 0, width <= Int.max / 4 / height, rgba.count == width * height * 4 else {
            throw MetalRendererError.invalidTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw MetalRendererError.allocationFailed }
        rgba.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    public func render(viewport: CaptureViewport, quads: [MetalQuad], clear: MetalRGBA = MetalRGBA(0, 0, 0, 0)) throws -> Data {
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: viewport.width, height: viewport.height, mipmapped: false)
        targetDescriptor.storageMode = .shared
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: targetDescriptor), let command = queue.makeCommandBuffer() else {
            throw MetalRendererError.allocationFailed
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(Double(clear.r), Double(clear.g), Double(clear.b), Double(clear.a))
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw MetalRendererError.commandFailed }
        encoder.setRenderPipelineState(pipeline)
        var size: [Float] = [Float(viewport.width), Float(viewport.height)]
        size.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 1) }
        for quad in quads where quad.rect.width > 0 && quad.rect.height > 0 {
            let x = Float(quad.rect.x), y = Float(quad.rect.y)
            let right = Float(quad.rect.x + quad.rect.width), bottom = Float(quad.rect.y + quad.rect.height)
            var vertices: [Float] = [
                x, y, 0, 0, right, y, 1, 0, x, bottom, 0, 1,
                right, y, 1, 0, right, bottom, 1, 1, x, bottom, 0, 1
            ]
            let clip = quad.clip ?? CaptureRect(x: 0, y: 0, width: viewport.width, height: viewport.height)
            let left = max(0, clip.x), top = max(0, clip.y)
            let clipRight = min(viewport.width, clip.x + clip.width)
            let clipBottom = min(viewport.height, clip.y + clip.height)
            guard clipRight > left, clipBottom > top else { continue }
            encoder.setScissorRect(MTLScissorRect(x: left, y: top, width: clipRight - left, height: clipBottom - top))
            vertices.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
            var color: [Float] = [quad.color.r, quad.color.g, quad.color.b, quad.color.a]
            color.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.setFragmentTexture(quad.texture ?? white, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw MetalRendererError.commandFailed }
        var result = Data(count: viewport.width * viewport.height * 4)
        result.withUnsafeMutableBytes { bytes in
            target.getBytes(bytes.baseAddress!, bytesPerRow: viewport.width * 4,
                from: MTLRegionMake2D(0, 0, viewport.width, viewport.height), mipmapLevel: 0)
        }
        return result
    }
}
#endif
