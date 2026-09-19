import CSS
import DOM
import HTML
import Style
import Testing

@Test func parsesSelectorsAndDeclarations() {
  let sheet = CSSParser.parse("#app > .card[data-x='1'] { color: #fff; width: 40px !important; }")
  #expect(sheet.rules.count == 1)
  #expect(sheet.rules[0].selectors[0].specificity.ids == 1)
  #expect(sheet.rules[0].declarations.count == 2)
  #expect(sheet.rules[0].declarations[1].important)
}

@Test func parsesLengths() {
  #expect(CSSLength.parse("12px") == .px(12))
  #expect(CSSLength.parse("50%") == .percent(50))
  #expect(CSSLength.parse("auto") == .auto)
}

@Test func siblingCombinatorsMatchNeighbors() {
  let document = HTMLParser.parse("<ul><li id=\"a\">a</li><li id=\"b\">b</li><li id=\"c\">c</li></ul>").document
  let adjacent = CSSParser.parseSelector("li + li")!
  let general = CSSParser.parseSelector("li ~ li")!
  let first = document.element(withID: "a")!
  let second = document.element(withID: "b")!
  let third = document.element(withID: "c")!
  #expect(!SelectorMatcher.matches(adjacent, node: first, document: document))
  #expect(SelectorMatcher.matches(adjacent, node: second, document: document))
  #expect(SelectorMatcher.matches(adjacent, node: third, document: document))
  #expect(!SelectorMatcher.matches(general, node: first, document: document))
  #expect(SelectorMatcher.matches(general, node: third, document: document))
}

@Test func attributeOperatorsMatch() {
  let document = HTMLParser.parse(
    "<main><a href=\"https://example.com/page\" lang=\"en-US\" data-tags=\"x y\">t</a></main>"
  ).document
  let anchor = document.elements(named: "a")[0]
  for (source, expected) in [
    ("a[href]", true), ("a[href^=\"https\"]", true), ("a[href$=\"page\"]", true),
    ("a[href*=\"example\"]", true), ("a[lang|=\"en\"]", true),
    ("a[data-tags~=\"y\"]", true), ("a[href$=\"other\"]", false),
  ] {
    #expect(
      SelectorMatcher.matches(CSSParser.parseSelector(source)!, node: anchor, document: document)
        == expected)
  }
}

@Test func structuralPseudosMatch() {
  let document = HTMLParser.parse("<ul><li id=\"a\">a</li><li id=\"b\">b</li></ul>").document
  let first = document.element(withID: "a")!
  let second = document.element(withID: "b")!
  #expect(
    SelectorMatcher.matches(
      CSSParser.parseSelector("li:first-child")!, node: first, document: document))
  #expect(
    !SelectorMatcher.matches(
      CSSParser.parseSelector("li:first-child")!, node: second, document: document))
  #expect(
    SelectorMatcher.matches(
      CSSParser.parseSelector("li:last-child")!, node: second, document: document))
  #expect(
    SelectorMatcher.matches(
      CSSParser.parseSelector("li:nth-child(2)")!, node: second, document: document))
  #expect(
    !SelectorMatcher.matches(
      CSSParser.parseSelector("a:hover")!, node: first, document: document))
}
