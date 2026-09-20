import Display
import EngineCore
import Foundation
import Images

#if canImport(Metal)
  import CoreGraphics
  import CoreText
  import Metal

  public struct MetalFrameStats: Hashable, Sendable {
    public var cpuMilliseconds: Double
    public var gpuMilliseconds: Double
    public var draws: Int
    public var triangles: Int
    public var textureUploads: Int

    public init(
      cpuMilliseconds: Double = 0, gpuMilliseconds: Double = 0, draws: Int = 0,
      triangles: Int = 0, textureUploads: Int = 0
    ) {
      self.cpuMilliseconds = cpuMilliseconds
      self.gpuMilliseconds = gpuMilliseconds
      self.draws = draws
      self.triangles = triangles
      self.textureUploads = textureUploads
    }
  }

  public struct MetalVideoLayer {
    public var texture: MTLTexture
    public var rect: Rect
    public var opacity: Double

    public init(texture: MTLTexture, rect: Rect, opacity: Double = 1) {
      self.texture = texture
      self.rect = rect
      self.opacity = opacity
    }
  }

  public final class MetalRenderer: @unchecked Sendable {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let colorPipeline: MTLRenderPipelineState
    private let texturePipeline: MTLRenderPipelineState
    private let lock = NSLock()
    private var retained: MTLTexture?
    private var retainedSize: Size = Size()
    private let textCache = MetalTextCache()
    private let sampler: MTLSamplerState

    public init?() {
      guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
      else { return nil }
      let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float2 p; float2 uv; float4 c; };
        struct O { float4 p [[position]]; float2 uv; float4 c; };
        vertex O vmain(const device V* v [[buffer(0)]], uint id [[vertex_id]]) {
          O o; o.p = float4(v[id].p, 0, 1); o.uv = v[id].uv; o.c = v[id].c; return o;
        }
        fragment float4 fcolor(O in [[stage_in]]) { return in.c; }
        fragment float4 ftexture(O in [[stage_in]], texture2d<float> t [[texture(0)]],
                                 sampler s [[sampler(0)]]) {
          float4 tex = t.sample(s, in.uv);
          return float4(tex.rgb, tex.a * in.c.a);
        }
        """
      guard let library = try? device.makeLibrary(source: source, options: nil),
        let vertex = library.makeFunction(name: "vmain"),
        let colorFragment = library.makeFunction(name: "fcolor"),
        let textureFragment = library.makeFunction(name: "ftexture")
      else { return nil }
      func pipeline(fragment: MTLFunction) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
      }
      guard let color = pipeline(fragment: colorFragment),
        let textured = pipeline(fragment: textureFragment),
        let samplerDescriptor: MTLSamplerDescriptor = {
          let descriptor = MTLSamplerDescriptor()
          descriptor.minFilter = .linear
          descriptor.magFilter = .linear
          descriptor.mipFilter = .notMipmapped
          return descriptor
        }(),
        let sampler = device.makeSamplerState(descriptor: samplerDescriptor)
      else { return nil }
      self.device = device
      self.queue = queue
      self.colorPipeline = color
      self.texturePipeline = textured
      self.sampler = sampler
    }

    public func renderRectangles(_ displayList: DisplayList, viewport: Size) throws -> MTLTexture {
      try renderFrame(displayList, viewport: viewport).texture
    }

    @discardableResult
    public func renderFrame(
      _ displayList: DisplayList, viewport: Size, origin: Point = .zero,
      dirty: [Rect]? = nil, videoLayers: [MetalVideoLayer] = []
    ) throws -> (texture: MTLTexture, stats: MetalFrameStats) {
      let cpuStart = Date()
      let width = max(1, Int(ceil(viewport.width)))
      let height = max(1, Int(ceil(viewport.height)))
      let texture: MTLTexture = try lock.withLock {
        if let retained, Int(retainedSize.width) == width, Int(retainedSize.height) == height {
          return retained
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let created = device.makeTexture(descriptor: descriptor) else {
          throw RendererError.renderingFailed
        }
        retained = created
        retainedSize = Size(width: Double(width), height: Double(height))
        return created
      }
      guard let commandBuffer = queue.makeCommandBuffer() else {
        throw RendererError.renderingFailed
      }
      var stats = MetalFrameStats()
      let regions: [(Rect?, Bool)] =
        dirty == nil ? [(nil, true)] : dirty!.map { ($0, false) }
      let firstFullClear = dirty == nil
      for (passIndex, (region, _)) in regions.enumerated() {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction =
          (firstFullClear && passIndex == 0) ? .clear : .load
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
          throw RendererError.renderingFailed
        }
        if let region {
          encoder.setScissorRect(metalScissor(region, viewport: viewport))
        }
        var clips: [Rect] = []
        for command in displayList.commands {
          switch command {
          case .rect(let rect):
            guard intersects(rect.rect, region) else { continue }
            drawColor(
              encoder: encoder, viewport: viewport, origin: origin,
              quads: quad(
                rect: offset(rect.rect, by: origin), color: rect.color, opacity: rect.opacity,
                viewport: viewport),
              stats: &stats)
          case .image(let image):
            guard intersects(image.rect, region) else { continue }
            if let uploaded = upload(
              rgba: image.image.rgba, width: image.image.width, height: image.image.height,
              stats: &stats)
            {
              drawTexture(
                encoder: encoder, viewport: viewport, texture: uploaded,
                rect: offset(image.rect, by: origin), opacity: image.opacity,
                clip: clips.last, stats: &stats)
            }
          case .text(let text):
            guard intersects(text.rect, region) else { continue }
            if let (uploaded, size) = textCache.texture(
              for: text, device: device, stats: &stats)
            {
              drawTexture(
                encoder: encoder, viewport: viewport, texture: uploaded,
                rect: Rect(
                  x: text.rect.origin.x + origin.x, y: text.rect.origin.y + origin.y,
                  width: size.width, height: size.height),
                opacity: text.opacity, clip: clips.last, stats: &stats)
            }
          case .pushClip(let clip):
            clips.append(clip.rect)
            if let active = clips.last {
              encoder.setScissorRect(metalScissor(active, viewport: viewport))
            }
          case .popClip:
            _ = clips.popLast()
            if let active = clips.last {
              encoder.setScissorRect(metalScissor(active, viewport: viewport))
            } else if let region {
              encoder.setScissorRect(metalScissor(region, viewport: viewport))
            } else {
              encoder.setScissorRect(
                MTLScissorRect(x: 0, y: 0, width: width, height: height))
            }
          }
        }
        for layer in videoLayers {
          drawTexture(
            encoder: encoder, viewport: viewport, texture: layer.texture,
            rect: offset(layer.rect, by: origin), opacity: layer.opacity, clip: nil,
            stats: &stats)
        }
        encoder.endEncoding()
      }
      commandBuffer.commit()
      commandBuffer.waitUntilCompleted()
      stats.cpuMilliseconds = Date().timeIntervalSince(cpuStart) * 1000
      if commandBuffer.status == .completed {
        stats.gpuMilliseconds =
          (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1000
      }
      return (texture, stats)
    }

    public func rgba8(_ texture: MTLTexture) -> [UInt8] {
      var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
      bytes.withUnsafeMutableBytes { pointer in
        texture.getBytes(
          pointer.baseAddress!, bytesPerRow: texture.width * 4,
          from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
      }
      return bytes
    }

    private func drawColor(      encoder: MTLRenderCommandEncoder, viewport: Size, origin: Point,
      quads: [MetalVertex], stats: inout MetalFrameStats
    ) {
      guard !quads.isEmpty,
        let buffer = device.makeBuffer(
          bytes: quads, length: MemoryLayout<MetalVertex>.stride * quads.count)
      else { return }
      encoder.setRenderPipelineState(colorPipeline)
      encoder.setVertexBuffer(buffer, offset: 0, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quads.count)
      stats.draws += 1
      stats.triangles += quads.count / 3
    }

    private func drawTexture(
      encoder: MTLRenderCommandEncoder, viewport: Size, texture: MTLTexture, rect: Rect,
      opacity: Double, clip: Rect?, stats: inout MetalFrameStats
    ) {
      var visible = rect
      if let clip { visible = intersect(visible, clip) ?? Rect() }
      guard visible.size.width > 0.5, visible.size.height > 0.5 else { return }
      let u0 = max(0, (visible.origin.x - rect.origin.x) / max(1, rect.size.width))
      let v0 = max(0, (visible.origin.y - rect.origin.y) / max(1, rect.size.height))
      let u1 = min(1, (visible.origin.x + visible.size.width - rect.origin.x) / max(
        1, rect.size.width))
      let v1 = min(1, (visible.origin.y + visible.size.height - rect.origin.y) / max(
        1, rect.size.height))
      let quads = texturedQuad(rect: visible, uv: (u0, v0, u1, v1), opacity: opacity,
        viewport: viewport)
      guard let buffer = device.makeBuffer(
        bytes: quads, length: MemoryLayout<MetalVertex>.stride * quads.count)
      else { return }
      encoder.setRenderPipelineState(texturePipeline)
      encoder.setVertexBuffer(buffer, offset: 0, index: 0)
      encoder.setFragmentTexture(texture, index: 0)
      encoder.setFragmentSamplerState(sampler, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quads.count)
      stats.draws += 1
      stats.triangles += quads.count / 3
    }

    private func upload(rgba: [UInt8], width: Int, height: Int, stats: inout MetalFrameStats)
      -> MTLTexture?
    {
      guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
      descriptor.usage = [.shaderRead]
      descriptor.storageMode = .shared
      guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
      rgba.withUnsafeBytes { pointer in
        texture.replace(
          region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
          withBytes: pointer.baseAddress!, bytesPerRow: width * 4)
      }
      stats.textureUploads += 1
      return texture
    }

    private func metalScissor(_ rect: Rect, viewport: Size) -> MTLScissorRect {
      MTLScissorRect(
        x: max(0, Int(rect.origin.x)), y: max(0, Int(rect.origin.y)),
        width: min(Int(viewport.width), max(0, Int(rect.size.width))),
        height: min(Int(viewport.height), max(0, Int(rect.size.height))))
    }

    private func intersects(_ rect: Rect, _ region: Rect?) -> Bool {
      guard let region else { return true }
      return intersect(rect, region) != nil
    }

    private func intersect(_ a: Rect, _ b: Rect) -> Rect? {
      let x0 = max(a.origin.x, b.origin.x)
      let y0 = max(a.origin.y, b.origin.y)
      let x1 = min(a.origin.x + a.size.width, b.origin.x + b.size.width)
      let y1 = min(a.origin.y + a.size.height, b.origin.y + b.size.height)
      guard x1 > x0, y1 > y0 else { return nil }
      return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func offset(_ rect: Rect, by origin: Point) -> Rect {
      Rect(
        x: rect.origin.x + origin.x, y: rect.origin.y + origin.y, width: rect.size.width,
        height: rect.size.height)
    }

    private func point(_ x: Double, _ y: Double, viewport: Size) -> SIMD2<Float> {
      SIMD2(Float((x / viewport.width) * 2 - 1), Float(1 - (y / viewport.height) * 2))
    }

    private func quad(rect: Rect, color: RGBAColor, opacity: Double, viewport: Size)
      -> [MetalVertex]
    {
      let c = SIMD4(
        Float(color.red), Float(color.green), Float(color.blue), Float(color.alpha * opacity))
      let uv = SIMD2<Float>(0, 0)
      let a = MetalVertex(position: point(rect.minX, rect.minY, viewport: viewport), uv: uv, color: c)
      let b = MetalVertex(position: point(rect.maxX, rect.minY, viewport: viewport), uv: uv, color: c)
      let c1 = MetalVertex(position: point(rect.maxX, rect.maxY, viewport: viewport), uv: uv, color: c)
      let d = MetalVertex(position: point(rect.minX, rect.maxY, viewport: viewport), uv: uv, color: c)
      return [a, b, c1, a, c1, d]
    }

    private func texturedQuad(
      rect: Rect, uv: (Double, Double, Double, Double), opacity: Double, viewport: Size
    ) -> [MetalVertex] {
      let c = SIMD4<Float>(1, 1, 1, Float(opacity))
      let a = MetalVertex(
        position: point(rect.minX, rect.minY, viewport: viewport),
        uv: SIMD2(Float(uv.0), Float(uv.1)), color: c)
      let b = MetalVertex(
        position: point(rect.maxX, rect.minY, viewport: viewport),
        uv: SIMD2(Float(uv.2), Float(uv.1)), color: c)
      let c1 = MetalVertex(
        position: point(rect.maxX, rect.maxY, viewport: viewport),
        uv: SIMD2(Float(uv.2), Float(uv.3)), color: c)
      let d = MetalVertex(
        position: point(rect.minX, rect.maxY, viewport: viewport),
        uv: SIMD2(Float(uv.0), Float(uv.3)), color: c)
      return [a, b, c1, a, c1, d]
    }
  }

  private struct MetalVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>
  }

  private final class MetalTextCache: @unchecked Sendable {
    private struct Key: Hashable {
      var text: String
      var size: Double
      var weight: Int
      var red: Double
      var green: Double
      var blue: Double
      var alpha: Double
    }

    private let cache = NSCache<NSString, MTLTexture>()
    private let lock = NSLock()

    init() {
      cache.countLimit = 512
    }

    func texture(for command: DrawTextCommand, device: MTLDevice, stats: inout MetalFrameStats)
      -> (MTLTexture, Size)?
    {
      guard !command.text.isEmpty, command.fontSize > 0 else { return nil }
      let key = Key(
        text: command.text, size: command.fontSize, weight: command.fontWeight,
        red: command.color.red, green: command.color.green, blue: command.color.blue,
        alpha: command.color.alpha)
      let identifier = "\(key.text)\n\(key.size)\n\(key.weight)\n\(key.red)\n\(key.green)\n\(key.blue)\n\(key.alpha)" as NSString
      if let cached = lock.withLock({ cache.object(forKey: identifier) }) {
        return (cached, Size(width: Double(cached.width) / 2, height: Double(cached.height) / 2))
      }
      guard let (rgba, width, height) = rasterize(command),
        let uploaded = upload(rgba: rgba, width: width, height: height, device: device)
      else { return nil }
      lock.withLock { cache.setObject(uploaded, forKey: identifier) }
      stats.textureUploads += 1
      return (uploaded, Size(width: Double(width) / 2, height: Double(height) / 2))
    }

    private func upload(rgba: [UInt8], width: Int, height: Int, device: MTLDevice)
      -> MTLTexture?
    {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
      descriptor.usage = [.shaderRead]
      descriptor.storageMode = .shared
      guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
      rgba.withUnsafeBytes { pointer in
        texture.replace(
          region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
          withBytes: pointer.baseAddress!, bytesPerRow: width * 4)
      }
      return texture
    }

    private func rasterize(_ command: DrawTextCommand) -> ([UInt8], Int, Int)? {
      let scale: CGFloat = 2
      let fontSize = CGFloat(max(1, command.fontSize)) * scale
      var traits: CTFontSymbolicTraits = []
      if command.fontWeight >= 700 { traits.insert(.boldTrait) }
      let base = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
      let font: CTFont
      if let derived = CTFontCreateCopyWithSymbolicTraits(base, 0, nil, traits, traits) {
        font = derived
      } else {
        font = base
      }
      let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: command.text, attributes: attributes))
      let ascent = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
      let descent = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
      let leading = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
      defer {
        ascent.deallocate()
        descent.deallocate()
        leading.deallocate()
      }
      let advance = CGFloat(CTLineGetTypographicBounds(line, ascent, descent, leading))
      let width = max(1, Int(ceil(advance)))
      let height = max(1, Int(ceil(ascent.pointee + descent.pointee + leading.pointee)))
      guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      context.setFillColor(
        red: CGFloat(command.color.red), green: CGFloat(command.color.green),
        blue: CGFloat(command.color.blue), alpha: CGFloat(command.color.alpha))
      context.textPosition = CGPoint(x: 0, y: descent.pointee + leading.pointee)
      CTLineDraw(line, context)
      guard let data = context.data else { return nil }
      let count = width * height * 4
      var rgba = [UInt8](repeating: 0, count: count)
      rgba.withUnsafeMutableBytes { target in
        target.baseAddress!.copyMemory(from: data, byteCount: count)
      }
      return (rgba, width, height)
    }
  }
#else
  public struct MetalFrameStats: Hashable, Sendable {
    public var cpuMilliseconds: Double = 0
    public var gpuMilliseconds: Double = 0
    public var draws: Int = 0
    public var triangles: Int = 0
    public var textureUploads: Int = 0
  }

  public struct MetalRenderer: Sendable {
    public init?() { return nil }
  }
#endif
