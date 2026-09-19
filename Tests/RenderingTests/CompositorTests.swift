import Display
import DOM
import EngineCore
import Graphics
import Images
import Testing

func compositorLayer(
  _ index: UInt32, frame: Rect, scrollable: Bool, content: Size, version: UInt64 = 1,
  opacity: Double = 1
) -> (NodeID, CompositorLayer) {
  let id = NodeID(index: index, generation: 1)
  let layer = CompositorLayer(
    nodeID: id, frame: frame, opacity: opacity, zIndex: 0,
    scrollOffset: Point(x: 0, y: 0), contentSize: content,
    contentVersion: version, isScrollable: scrollable)
  return (id, layer)
}

@Test func compositorScrollClampsAndDamagesExposedStrip() {
  let (id, first) = compositorLayer(
    1, frame: Rect(x: 0, y: 0, width: 100, height: 200),
    scrollable: true, content: Size(width: 100, height: 400))
  var compositor = RetainedCompositor(layers: [id: first])
  let result = compositor.scroll(id, by: Point(x: 0, y: 50))
  #expect(result?.offset == Point(x: 0, y: 50))
  #expect(result?.damage.bounds?.height == 50)
  let clamped = compositor.scroll(id, by: Point(x: 0, y: 500))
  #expect(clamped?.offset == Point(x: 0, y: 200))
}

@Test func compositorRejectsNonScrollableScroll() {
  let (id, first) = compositorLayer(
    2, frame: Rect(x: 0, y: 0, width: 100, height: 100),
    scrollable: false, content: Size(width: 100, height: 100))
  var compositor = RetainedCompositor(layers: [id: first])
  #expect(compositor.scroll(id, by: Point(x: 0, y: 10)) == nil)
}

@Test func compositorDetectsCompositeOnlyChanges() {
  let (id, first) = compositorLayer(
    3, frame: Rect(x: 0, y: 0, width: 100, height: 100),
    scrollable: false, content: Size(width: 100, height: 100))
  var dimmed = first
  dimmed.opacity = 0.5
  #expect(RetainedCompositor.isCompositeOnly(from: [id: first], to: [id: dimmed]))
  var moved = first
  moved.frame = Rect(x: 10, y: 0, width: 100, height: 200)
  #expect(!RetainedCompositor.isCompositeOnly(from: [id: first], to: [id: moved]))
}

@Test func compositorCommitDamagesAddedAndMovedLayers() {
  let (id, first) = compositorLayer(
    4, frame: Rect(x: 0, y: 0, width: 50, height: 50),
    scrollable: false, content: Size(width: 50, height: 50))
  var compositor = RetainedCompositor()
  let compositeOnly = compositor.commit([id: first])
  #expect(!compositeOnly)
  #expect(!compositor.takeDamage().isEmpty)
  #expect(compositor.takeDamage().isEmpty)
}

@Test func chunkIndexMapsDamageToCommands() {
  let near = DrawRectCommand(
    rect: Rect(x: 0, y: 0, width: 10, height: 10),
    color: RGBAColor(red: 1, green: 0, blue: 0))
  let far = DrawRectCommand(
    rect: Rect(x: 900, y: 900, width: 10, height: 10),
    color: RGBAColor(red: 0, green: 0, blue: 1))
  let list = DisplayList(commands: [.rect(near), .rect(far)], size: Size(width: 1000, height: 1000))
  let index = PaintChunkIndex.build(list, chunkSize: 512)
  var damage = DirtyRegion()
  damage.add(Rect(x: 0, y: 0, width: 20, height: 20))
  #expect(index.commandIndices(dirty: damage) == [0])
  #expect(PaintChunkIndex.build(list, chunkSize: 512).commandIndices(dirty: DirtyRegion()).isEmpty)
}

@Test func displayListCullsOutsideDamage() {
  let farRect = Rect(x: 900, y: 900, width: 10, height: 10)
  let nearRect = Rect(x: 0, y: 0, width: 10, height: 10)
  let far = DrawRectCommand(rect: farRect, color: RGBAColor(red: 0, green: 0, blue: 1))
  let near = DrawRectCommand(rect: nearRect, color: RGBAColor(red: 1, green: 0, blue: 0))
  let list = DisplayList(
    commands: [.pushClip(ClipCommand(rect: farRect)), .rect(far), .popClip, .rect(near)],
    size: Size(width: 1000, height: 1000))
  var damage = DirtyRegion()
  damage.add(Rect(x: 0, y: 0, width: 20, height: 20))
  let kept = list.commands(intersecting: damage)
  #expect(!kept.contains(.rect(far)))
  #expect(kept.contains(.rect(near)))
  #expect(kept.contains(.pushClip(ClipCommand(rect: farRect))))
  #expect(kept.contains(.popClip))
}

@Test func tileCacheCoversStoresAndInvalidates() {
  var cache = TileCache(tileSize: 256, budgetBytes: 10_000_000)
  let viewport = Rect(x: 0, y: 0, width: 500, height: 500)
  let first = cache.coverage(for: viewport)
  #expect(first.missing.count == 4)
  #expect(first.resident.isEmpty)
  for request in first.missing { #expect(cache.store(request)) }
  let second = cache.coverage(for: viewport)
  #expect(second.missing.isEmpty)
  #expect(second.resident.count == 4)
  var damage = DirtyRegion()
  damage.add(Rect(x: 0, y: 0, width: 10, height: 10))
  #expect(cache.invalidate(damage) == [TileKey(column: 0, row: 0)])
  #expect(cache.coverage(for: viewport).missing.count == 1)
}

@Test func ledgerEnforcesBudgetsAndReportsPressure() {
  var ledger = ResourceLedger(
    budget: ResourceBudget(
      maxImageBytes: 100, maxTextureBytes: 100, maxRasterBytes: 100, maxGlyphBytes: 100))
  #expect(ledger.allocate(80, category: .images))
  #expect(ledger.pressure(for: .images) == .elevated)
  #expect(!ledger.allocate(30, category: .images))
  ledger.release(80, category: .images)
  #expect(ledger.pressure(for: .images) == .nominal)
  #expect(ledger.allocate(100, category: .glyphs))
  #expect(ledger.overallPressure == .critical)
}

@Test func glyphAtlasReusesAndRejects() {
  var atlas = GlyphAtlas(width: 64, height: 64)
  let key = GlyphKey(scalar: 65, fontSizeMillipoints: 16000, fontWeight: 400)
  let first = atlas.cell(for: key, size: Size(width: 10, height: 12))
  #expect(first != nil)
  #expect(atlas.cell(for: key, size: Size(width: 10, height: 12)) == first)
  #expect(atlas.count == 1)
  let huge = atlas.cell(
    for: GlyphKey(scalar: 66, fontSizeMillipoints: 16000, fontWeight: 400),
    size: Size(width: 1000, height: 1000))
  #expect(huge == nil)
}

@Test func imagePolicyEvictsLargestUnkeptFirst() {
  let policy = ImageMemoryPolicy(maxTotalBytes: 1000, maxSingleImageBytes: 1_000_000)
  let big = DecodedImage(width: 100, height: 100, rgba: [UInt8](repeating: 255, count: 40_000))
  let small = DecodedImage(width: 2, height: 2, rgba: [UInt8](repeating: 0, count: 16))
  let keptID = NodeID(index: 7, generation: 1)
  let bigID = NodeID(index: 8, generation: 1)
  #expect(policy.evictionCandidates(images: [keptID: small, bigID: big], keep: [keptID]) == [bigID])
  #expect(policy.evictionCandidates(images: [keptID: small], keep: []) == [])
}
