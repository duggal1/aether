import Foundation
import HTML
import Testing

@Test func parsesElementsAttributesAndText() {
  let result = HTMLParser.parse("<main id=\"x\"><p>Hello &amp; world</p></main>")
  #expect(result.document.elements(named: "main").count == 1)
  let main = result.document.elements(named: "main")[0]
  #expect(result.document.node(main)?.attribute("id") == "x")
  #expect(result.document.textContent(of: main) == "Hello & world")
}

@Test func tokenizerStreamsAcrossChunks() {
  let tokenizer = HTMLTokenizer()
  #expect(tokenizer.feed("<div cla").isEmpty)
  let tokens = tokenizer.feed("ss='a'>x</div>", isFinal: true)
  #expect(!tokens.isEmpty)
}

@Test func rawTextDoesNotTreatLessThanAsMarkup() {
  let result = HTMLParser.parse("<script>if (a < b) { x = '<div>'; }</script><p>done</p>")
  let script = result.document.elements(named: "script")[0]
  #expect(result.document.textContent(of: script) == "if (a < b) { x = '<div>'; }")
  #expect(result.document.elements(named: "div").isEmpty)
  #expect(result.document.elements(named: "p").count == 1)
}

@Test func rawTextCanSpanTokenizerChunks() {
  let result = HTMLParser.parse(chunks: [
    "<style>.x { content: '<", "tag>'; }</style><main>", "ok</main>",
  ])
  let style = result.document.elements(named: "style")[0]
  #expect(result.document.textContent(of: style) == ".x { content: '<tag>'; }")
  let main = result.document.elements(named: "main")[0]
  #expect(result.document.textContent(of: main) == "ok")
}

@Test func misNestedFormattingPreservesText() {
  let result = HTMLParser.parse("<b>1<i>2</b>3</i>")
  #expect(result.document.textContent(of: result.document.root) == "123")
  #expect(!result.document.elements(named: "b").isEmpty)
  #expect(!result.document.elements(named: "i").isEmpty)
}

@Test func nestedAnchorsDoNotNest() {
  let result = HTMLParser.parse("<a href=\"1\">one<a href=\"2\">two</a>")
  let anchors = result.document.elements(named: "a")
  #expect(anchors.count == 2)
  #expect(result.document.textContent(of: anchors[0]) == "one")
  #expect(result.document.textContent(of: anchors[1]) == "two")
}

@Test func tableTextIsFosterParented() {
  let result = HTMLParser.parse("<table>oops<tr><td>cell</td></tr></table>")
  let tables = result.document.elements(named: "table")
  #expect(tables.count == 1)
  #expect(result.document.textContent(of: tables[0]) == "cell")
  #expect(result.document.textContent(of: result.document.root).contains("oops"))
  #expect(result.document.textContent(of: result.document.root).contains("cell"))
}

@Test func tableCellsCloseImplicitly() {
  let result = HTMLParser.parse("<table><tr><td>a<td>b</tr></table>")
  #expect(result.document.elements(named: "td").count == 2)
}

@Test func listItemsCloseImplicitly() {
  let result = HTMLParser.parse("<ul><li>a<li>b</ul>")
  #expect(result.document.elements(named: "li").count == 2)
}

@Test func paragraphClosesBeforeDiv() {
  let result = HTMLParser.parse("<p>1<div>2</div>")
  let divs = result.document.elements(named: "div")
  #expect(divs.count == 1)
  #expect(result.document.textContent(of: result.document.root) == "12")
}

@Test func breakEndTagBecomesElement() {
  let result = HTMLParser.parse("<p>a</br>b</p>")
  #expect(!result.document.elements(named: "br").isEmpty)
}

@Test func cdataBecomesText() {
  let result = HTMLParser.parse("<div><![CDATA[<b>]]></div>")
  let div = result.document.elements(named: "div")[0]
  #expect(result.document.textContent(of: div) == "<b>")
}

@Test func selfClosingSlashOnDivIsIgnored() {
  let result = HTMLParser.parse("<div/>text")
  let divs = result.document.elements(named: "div")
  #expect(divs.count == 1)
  #expect(result.document.textContent(of: divs[0]) == "text")
}

@Test func entitiesDecodeCommonNamedAndNumeric() {
  let result = HTMLParser.parse("<p>&copy; &#169; &#xA9; &mdash; &amp</p>")
  let text = result.document.textContent(of: result.document.elements(named: "p")[0])
  #expect(text == "© © © — &")
}

@Test func templateParsesContents() {
  let result = HTMLParser.parse("<template><div>inner</div></template>")
  #expect(result.document.elements(named: "template").count == 1)
  #expect(result.document.elements(named: "div").count == 1)
}

@Test func bytesDecodeHandlesBOMAndMeta() {
  var bytes = Data([0xEF, 0xBB, 0xBF])
  bytes.append(contentsOf: "<p>hi</p>".utf8)
  let bom = HTMLParser.parse(bytes: bytes)
  #expect(bom.document.elements(named: "p").count == 1)
  #expect(HTMLParser.sniffCharset(in: "<meta charset=\"shift_jis\">") == "shift_jis")
}
