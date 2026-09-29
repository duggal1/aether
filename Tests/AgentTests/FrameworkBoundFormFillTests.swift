import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

/// Regression coverage for the defect that made framework-bound forms undrivable by an
/// agent, found while driving a live Google signup in Aether.
///
/// Google (Polymer), and most modern signups, keep their own copy of every input value
/// and rewrite the DOM from that copy on re-render. A fill that only assigns the DOM
/// node is therefore silently discarded: the agent reads the value back, clicks Next,
/// and the field is empty again — with no error anywhere.
///
/// The fixture reproduces exactly that: listeners own the state, and `__rerender()`
/// writes the inputs back from it. A value only survives if the fill emitted a real,
/// composed `InputEvent`.
struct FrameworkBoundFormFillTests {
    private static let fixture = """
        <!doctype html><meta charset="utf-8"><title>framework form</title>
        <form id="f" onsubmit="event.preventDefault()">
          <input name="user" aria-label="User">
          <input name="pass" type="password" aria-label="Password">
          <input name="pass2" type="password" aria-label="Confirm">
          <button type="submit">Sign in</button>
        </form>
        <script>
          const state = {};
          for (const el of document.querySelectorAll('input')) {
            el.addEventListener('input', e => { state[el.name] = e.target.value; });
            el.addEventListener('change', e => { state[el.name] = e.target.value; });
          }
          window.__rerender = () => {
            for (const el of document.querySelectorAll('input')) {
              if (state[el.name] !== undefined) el.value = state[el.name];
            }
          };
          window.__state = state;
        </script>
        """

    private func makePage() async throws -> (BrowserRuntime, PageID, ContextID) {
        let runtime = BrowserRuntime()
        let context = await runtime.createContext(name: "framework-form")
        let page = try await runtime.createPage(contextID: context.id)
        _ = try await runtime.loadHTML(
            pageID: page, html: Self.fixture, url: URL(string: "https://form.test/")!)
        return (runtime, page, context.id)
    }

    private func string(_ runtime: BrowserRuntime, _ page: PageID, _ source: String) async throws -> String
    {
        try await runtime.evaluate(pageID: page, source: source).value
    }

    /// The core regression: a fill must be observed by the framework, not just written
    /// to the node, or the next re-render discards it.
    @Test("fill is observed by framework state and survives a re-render")
    func fillSurvivesReRender() async throws {
        let (runtime, page, context) = try await makePage()

        let node = try #require(
            try await runtime.query(pageID: page, selector: "input[name=user]")?.id)
        try await runtime.setValue(pageID: page, nodeID: node, value: "aetheragentkilo")

        // The framework's own copy must have seen the write — this is what a non-composed
        // Event, or a bare value assignment, fails to do.
        let mirrored = try await string(runtime, page, "JSON.stringify(window.__state.user ?? null)")
        #expect(mirrored.contains("aetheragentkilo"), "framework did not observe the fill")

        _ = try await string(runtime, page, "window.__rerender(); 'ok'")
        let after = try await string(
            runtime, page, "document.querySelector('[name=user]').value")
        #expect(after == "aetheragentkilo", "value was reverted on re-render")

        try await runtime.destroyContext(context)
    }

    /// Signup and change-password forms pair the entry with a confirm field. Both must
    /// end up populated, otherwise the form cannot be submitted.
    @Test("every password field is filled, including the confirm field")
    func fillsConfirmField() async throws {
        let (runtime, page, context) = try await makePage()

        for name in ["pass", "pass2"] {
            let node = try #require(
                try await runtime.query(pageID: page, selector: "input[name=\(name)]")?.id)
            try await runtime.setValue(pageID: page, nodeID: node, value: "S3cret-for-test")
        }

        let lengths = try await string(
            runtime, page,
            "JSON.stringify(Array.from(document.querySelectorAll('input[type=password]'))"
                + ".map(e => e.value.length))")
        let observed = try #require(
            try JSONSerialization.jsonObject(with: Data(lengths.utf8)) as? [Int])
        #expect(observed.count == 2, "expected an entry and a confirm password field")
        #expect(observed.allSatisfy { $0 == 15 }, "both password fields must be filled")

        try await runtime.destroyContext(context)
    }
}
