import CSS
import EngineCore
import HTML
import Layout
import Style
import Testing
import Text

@Test func opacityOnlyChangeIsCompositeOnly() {
  let old = ComputedStyle()
  var updated = ComputedStyle()
  updated.opacity = 0.5
  let flags = PipelineInvalidation.dirtyFlags(old: old, new: updated)
  #expect(!flags.needsLayout)
  #expect(!flags.needsPaint)
  #expect(flags.isCompositeOnly)
}

@Test func widthChangeNeedsLayout() {
  var updated = ComputedStyle()
  updated.width = .px(100)
  let flags = PipelineInvalidation.dirtyFlags(old: ComputedStyle(), new: updated)
  #expect(flags.needsLayout)
  #expect(flags.needsPaint)
  #expect(!flags.isCompositeOnly)
}

@Test func colorChangeNeedsPaintWithoutLayout() {
  var updated = ComputedStyle()
  updated.color = RGBAColor(red: 1, green: 0, blue: 0)
  let flags = PipelineInvalidation.dirtyFlags(old: ComputedStyle(), new: updated)
  #expect(!flags.needsLayout)
  #expect(flags.needsPaint)
  #expect(!flags.isCompositeOnly)
}

@Test func identicalStylesProduceNoWork() {
  #expect(PipelineInvalidation.dirtyFlags(old: ComputedStyle(), new: ComputedStyle()) == [])
}

@Test func pipelineStateCoalescesAndDrains() {
  var state = FramePipelineState()
  #expect(state.isClean)
  state.markDirty([.paint], mutationVersion: 3)
  state.markDirty([.composite], mutationVersion: 4)
  #expect(state.sourceMutationVersion == 4)
  let taken = state.takePending()
  #expect(taken.contains(.paint) && taken.contains(.composite))
  #expect(state.isClean)
}

@Test func scrollViewportAndCulling() {
  let document = HTMLParser.parse("<div class='s'><div class='inner'>x</div></div>").document
  let sheet = CSSParser.parse(
    ".s{display:block;overflow:scroll;width:100px;height:100px}.inner{display:block;height:400px}")
  let styled = StyleResolver.resolve(
    document: document, stylesheets: [sheet], viewport: Size(width: 800, height: 600))
  let tree = LayoutEngine().layout(styled, viewport: Size(width: 800, height: 600))
  #expect(tree.scrollViewports().count == 1)
  #expect(tree.fragments().count == tree.boxes.count)
  let full = tree.paintOrder(culledTo: Rect(x: 0, y: 0, width: 800, height: 600))
  #expect(full.count == tree.paintOrder.count)
  let tiny = tree.paintOrder(culledTo: Rect(x: 790, y: 590, width: 5, height: 5))
  #expect(tiny.count <= full.count)
}

@Test func textCacheMeasuresOncePerKey() {
  var cache = TextRunCache(capacity: 4)
  var calls = 0
  let key = TextCacheKey(text: "hello", fontSize: 16, fontWeight: 400, maxWidth: nil)
  let first = cache.metrics(for: key) { _ in
    calls += 1
    return TextRunMetrics(size: Size(width: 30, height: 19), ascent: 13, descent: 4)
  }
  let second = cache.metrics(for: key) { _ in
    calls += 1
    return TextRunMetrics(size: Size(width: 1, height: 1), ascent: 1, descent: 1)
  }
  #expect(calls == 1)
  #expect(first == second)
  #expect(cache.hits == 1 && cache.misses == 1)
  #expect(cache.hitRate == 0.5)
}

@Test func textCacheEvictsOldest() {
  var cache = TextRunCache(capacity: 2)
  func key(_ text: String) -> TextCacheKey {
    TextCacheKey(text: text, fontSize: 16, fontWeight: 400, maxWidth: nil)
  }
  func value() -> TextRunMetrics {
    TextRunMetrics(size: Size(width: 1, height: 1), ascent: 1, descent: 1)
  }
  _ = cache.metrics(for: key("a")) { _ in value() }
  _ = cache.metrics(for: key("b")) { _ in value() }
  _ = cache.metrics(for: key("c")) { _ in value() }
  #expect(cache.count == 2)
}
