import CSS
import EngineCore
import HTML
import Layout
import Style
import Testing
import Text

@Test func blockLayoutProducesGeometry() {
  let document = HTMLParser.parse("<body><div class='a'>Hello</div><div>World</div></body>")
    .document
  let sheet = CSSParser.parse("body{display:block}.a{display:block;height:40px;padding:5px}")
  let styled = StyleResolver.resolve(
    document: document, stylesheets: [sheet], viewport: Size(width: 800, height: 600))
  let tree = LayoutEngine().layout(styled, viewport: Size(width: 800, height: 600))
  let divs = document.elements(named: "div")
  #expect(tree.boxes[divs[0]] != nil)
  #expect(tree.boxes[divs[1]] != nil)
  #expect((tree.boxes[divs[0]]?.frame.height ?? 0) >= 40)
}

@Test func flexLayoutPlacesChildrenHorizontally() {
  let document = HTMLParser.parse("<div class='row'><div>A</div><div>B</div></div>").document
  let sheet = CSSParser.parse(
    ".row{display:flex;width:400px;gap:10px}.row>div{display:block;flex-grow:1}")
  let styled = StyleResolver.resolve(
    document: document, stylesheets: [sheet], viewport: Size(width: 800, height: 600))
  let tree = LayoutEngine().layout(styled, viewport: Size(width: 800, height: 600))
  let divs = document.elements(named: "div")
  #expect((tree.boxes[divs[2]]?.frame.minX ?? 0) > (tree.boxes[divs[1]]?.frame.minX ?? 0))
}

@Test func formControlsReceiveUsableIntrinsicGeometry() {
  let document = HTMLParser.parse(
    "<form><input type='text' value='hello'><input type='checkbox'><button>Submit</button><textarea>Notes</textarea></form>"
  ).document
  let styled = StyleResolver.resolve(
    document: document, stylesheets: [], viewport: Size(width: 800, height: 600))
  let tree = LayoutEngine().layout(styled, viewport: Size(width: 800, height: 600))
  let inputIDs = document.elements(named: "input")
  let buttonID = document.elements(named: "button")[0]
  let textareaID = document.elements(named: "textarea")[0]

  #expect((tree.boxes[inputIDs[0]]?.frame.width ?? 0) >= 100)
  #expect((tree.boxes[inputIDs[0]]?.frame.height ?? 0) >= 20)
  #expect((tree.boxes[inputIDs[1]]?.frame.width ?? 0) >= 12)
  #expect((tree.boxes[inputIDs[1]]?.frame.height ?? 0) >= 12)
  #expect((tree.boxes[buttonID]?.frame.height ?? 0) >= 20)
  #expect((tree.boxes[textareaID]?.frame.height ?? 0) >= 40)
}
