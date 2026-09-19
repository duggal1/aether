import Display
import EngineCore
import Foundation

#if canImport(Metal)
  import Metal

  public final class MetalRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    public init?() {
      guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
      else { return nil }
      let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float2 p; float4 c; };
        struct O { float4 p [[position]]; float4 c; };
        vertex O vmain(const device V* v [[buffer(0)]], uint id [[vertex_id]]) { O o; o.p=float4(v[id].p,0,1); o.c=v[id].c; return o; }
        fragment float4 fmain(O in [[stage_in]]) { return in.c; }
        """
      guard let library = try? device.makeLibrary(source: source, options: nil),
        let vertex = library.makeFunction(name: "vmain"),
        let fragment = library.makeFunction(name: "fmain")
      else { return nil }
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = vertex
      descriptor.fragmentFunction = fragment
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
        return nil
      }
      self.device = device
      self.queue = queue
      self.pipeline = pipeline
    }

    public func renderRectangles(_ displayList: DisplayList, viewport: Size) throws -> MTLTexture {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: max(1, Int(viewport.width)),
        height: max(1, Int(viewport.height)), mipmapped: false)
      descriptor.usage = [.renderTarget, .shaderRead]
      descriptor.storageMode = .shared
      guard let texture = device.makeTexture(descriptor: descriptor),
        let commandBuffer = queue.makeCommandBuffer()
      else { throw RendererError.renderingFailed }
      let pass = MTLRenderPassDescriptor()
      pass.colorAttachments[0].texture = texture
      pass.colorAttachments[0].loadAction = .clear
      pass.colorAttachments[0].storeAction = .store
      pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
      guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
        throw RendererError.renderingFailed
      }
      encoder.setRenderPipelineState(pipeline)

      var vertices: [MetalVertex] = []
      for command in displayList.commands {
        guard case .rect(let rect) = command else { continue }
        vertices.append(
          contentsOf: quad(
            rect: rect.rect, color: rect.color, opacity: rect.opacity, viewport: viewport))
      }
      if !vertices.isEmpty,
        let buffer = device.makeBuffer(
          bytes: vertices, length: MemoryLayout<MetalVertex>.stride * vertices.count)
      {
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
      }
      encoder.endEncoding()
      commandBuffer.commit()
      commandBuffer.waitUntilCompleted()
      return texture
    }

    private func quad(rect: Rect, color: RGBAColor, opacity: Double, viewport: Size)
      -> [MetalVertex]
    {
      func point(_ x: Double, _ y: Double) -> SIMD2<Float> {
        SIMD2(Float((x / viewport.width) * 2 - 1), Float(1 - (y / viewport.height) * 2))
      }
      let c = SIMD4(
        Float(color.red), Float(color.green), Float(color.blue), Float(color.alpha * opacity))
      let a = MetalVertex(position: point(rect.minX, rect.minY), color: c)
      let b = MetalVertex(position: point(rect.maxX, rect.minY), color: c)
      let c1 = MetalVertex(position: point(rect.maxX, rect.maxY), color: c)
      let d = MetalVertex(position: point(rect.minX, rect.maxY), color: c)
      return [a, b, c1, a, c1, d]
    }
  }

  private struct MetalVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
  }
#else
  public struct MetalRenderer: Sendable {
    public init?() { return nil }
  }
#endif
