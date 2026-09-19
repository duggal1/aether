import HTML
import JavaScript
import Storage
import Testing

@Test func runtimeEvaluatesFunctionsAndClosures() throws {
  let runtime = JSRuntime()
  #expect(try runtime.evaluate("function add(a,b){ return a+b; } add(19,23);").description == "42")
  #expect(
    try runtime.evaluate(
      "var x=10; function f(a){ return function(b){ return a+b+x; }; } var g=f(5); g(2);"
    ).description == "17")
}

@Test func domBindingsReadAndMutateDocument() throws {
  let document = HTMLParser.parse(
    "<html><body><input id='name' value='a'><main id='root'></main></body></html>"
  ).document
  let runtime = JSRuntime(document: document)
  #expect(try runtime.evaluate("document.getElementById('name').value").description == "a")
  _ = try runtime.evaluate("document.getElementById('name').value = 'b';")
  #expect(document.node(document.element(withID: "name")!)?.attribute("value") == "b")
  _ = try runtime.evaluate(
    "var x=document.createElement('span'); x.textContent='hello'; document.getElementById('root').appendChild(x);"
  )
  let root = document.element(withID: "root")!
  #expect(document.textContent(of: root) == "hello")
}

@Test func querySelectorAllReturnsArrayLikeObject() throws {
  let document = HTMLParser.parse("<div class='x'></div><div class='x'></div>").document
  let runtime = JSRuntime(document: document)
  #expect(try runtime.evaluate("document.querySelectorAll('.x').length").description == "2")
}

@Test func eventListenersBubbleAndCanPreventDefault() throws {
  let document = HTMLParser.parse("<div id='parent'><button id='child'>Go</button></div>").document
  let runtime = JSRuntime(document: document)
  _ = try runtime.evaluate(
    "document.getElementById('parent').addEventListener('click', function(e){ document.getElementById('parent').setAttribute('data-hit','1'); });"
  )
  _ = try runtime.evaluate(
    "document.getElementById('child').addEventListener('click', function(e){ e.preventDefault(); });"
  )
  let child = document.element(withID: "child")!
  let result = try runtime.dispatchEvent(type: "click", target: child)
  #expect(result.defaultPrevented)
  #expect(document.node(document.element(withID: "parent")!)?.attribute("data-hit") == "1")
}

@Test func localStorageBindingPersistsValues() throws {
  let document = HTMLParser.parse("<main></main>").document
  let storage = LocalStorage()
  let runtime = JSRuntime(document: document, localStorage: storage)
  _ = try runtime.evaluate("localStorage.setItem('mode','dark');")
  #expect(try runtime.evaluate("localStorage.getItem('mode')").description == "dark")
  #expect(try runtime.evaluate("window.localStorage.length").description == "1")
}

@Test func promisesResolveAndChain() throws {
  let runtime = JSRuntime()
  #expect(
    try runtime.evaluate("let out = 0; Promise.resolve(21).then(v => { out = v * 2; }); out")
      .description == "42")
  #expect(
    try runtime.evaluate("let seen = ''; Promise.reject('x').catch(e => { seen = e; }); seen")
      .description == "x")
}

@Test func asyncFunctionsAwaitValues() throws {
  let runtime = JSRuntime()
  #expect(
    try runtime.evaluate(
      "async function f() { return 40 + 2; } let out = 0; f().then(v => { out = v; }); out"
    ).description == "42")
}

@Test func bigIntArithmetic() throws {
  let runtime = JSRuntime()
  #expect(try runtime.evaluate("10n + 32n").description == "42")
  #expect(try runtime.evaluate("typeof 10n").description == "bigint")
  #expect(try runtime.evaluate("7n * 6n").description == "42")
}

@Test func classesConstructAndInherit() throws {
  let runtime = JSRuntime()
  #expect(
    try runtime.evaluate(
      "class A { constructor(x) { this.x = x; } get() { return this.x * 2; } } new A(21).get();"
    ).description == "42")
  #expect(
    try runtime.evaluate(
      "class B extends Array { first() { return this[0]; } } new B(40, 2).first();"
    ).description == "40")
}

@Test func mapAndSetBehave() throws {
  let runtime = JSRuntime()
  #expect(
    try runtime.evaluate("const m = new Map(); m.set('a', 40); m.get('a') + 2;").description
      == "42")
  #expect(try runtime.evaluate("const s = new Set([40, 1, 40]); s.size + 39;").description == "42")
}

@Test func jsonRoundTrips() throws {
  let runtime = JSRuntime()
  #expect(try runtime.evaluate("JSON.parse('{\"a\":40}').a + 2;").description == "42")
  #expect(try runtime.evaluate("JSON.parse(JSON.stringify({a:42})).a;").description == "42")
}

@Test func regexAndStringHelpers() throws {
  let runtime = JSRuntime()
  #expect(try runtime.evaluate("/4/.test('42');").description == "true")
  #expect(try runtime.evaluate("'hello'.toUpperCase();").description == "HELLO")
  #expect(try runtime.evaluate("'a,b,c'.split(',').length;").description == "3")
  #expect(try runtime.evaluate("'aaa'.replace('a', 'b');").description == "baa")
}

@Test func typedArraysStoreAndRead() throws {
  let runtime = JSRuntime()
  #expect(try runtime.evaluate("const t = new Uint8Array([40, 1]); t[0] + t[1];").description == "42")
  #expect(try runtime.evaluate("const t = new Uint8Array(3); t.length;").description == "3")
  #expect(
    try runtime.evaluate("const t = new Uint8Array([1, 2, 3]); t[0] = 40; t[0] + t[2];")
      .description == "43")
  #expect(
    try runtime.evaluate(
      "const b = new ArrayBuffer(4); const v = new DataView(b); v.setUint8(0, 42); v.getUint8(0);"
    ).description == "42")
}

@Test func modulesImportExports() throws {
  let runtime = JSRuntime()
  runtime.modules.register(path: "dep", source: "export const x = 41;")
  #expect(
    try runtime.evaluateModule("import { x } from 'dep'; x + 1;", path: "main").description
      == "42")
}

@Test func destructuringAndOptionalChaining() throws {
  let runtime = JSRuntime()
  #expect(
    try runtime.evaluate("const {a, ...rest} = {a: 40, b: 2}; a + rest.b;").description == "42")
  #expect(try runtime.evaluate("const o = null; o?.x ?? 42;").description == "42")
  #expect(try runtime.evaluate("const t = `4${2}`; t;").description == "42")
}

@Test func parserConsumesEmptyArgumentLists() throws {
  let source = "function f() { return 42; } new Map(); new Set(); f(); f?.();"
  #expect(try JSParser(source: source).parseProgram().count == 5)
  let runtime = JSRuntime()
  #expect(try runtime.evaluate("function f() { return 42; } f();").description == "42")
}
