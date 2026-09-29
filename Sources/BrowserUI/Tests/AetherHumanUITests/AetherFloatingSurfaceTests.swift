import AppKit
import Foundation
import JavaScriptCore
import Testing
@testable import AetherHumanUI

// The two pieces of the floating-surface work that can be checked without a
// live window: that a press over the page still dismisses what is open while
// the scroll wheel is left to the page, and that the popup's own sizing page
// answers with a size.
@MainActor
struct AetherDismissSurfaceTests {
    @Test func scrollWheelIsLeftToThePage() {
        let view = AetherDismissSurface.DismissView()
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        view.currentEventType = { .scrollWheel }
        #expect(view.hitTest(NSPoint(x: 50, y: 50)) == nil)
        view.currentEventType = { .mouseMoved }
        #expect(view.hitTest(NSPoint(x: 50, y: 50)) == nil)
    }

    @Test func pressesAreClaimed() {
        let view = AetherDismissSurface.DismissView()
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        view.currentEventType = { .leftMouseDown }
        #expect(view.hitTest(NSPoint(x: 50, y: 50)) === view)
        view.currentEventType = { .rightMouseDown }
        #expect(view.hitTest(NSPoint(x: 50, y: 50)) === view)
    }

    @Test func pressesOutsideTheSurfaceAreNotClaimed() {
        let view = AetherDismissSurface.DismissView()
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        view.currentEventType = { .leftMouseDown }
        #expect(view.hitTest(NSPoint(x: 500, y: 500)) == nil)
    }
}

// The popup's sizing page is what the popup's own web view is asked, and a
// popup that is never answered with a size is never measured, never grown and
// never revealed — a blank popover over the toolbar.
@MainActor
struct AetherExtensionPopupTests {
    @Test func sizingExpressionAnswersWithThePagesSize() throws {
        let context = try #require(JSContext())
        context.evaluateScript("""
        var window = globalThis;
        var innerWidth = 300, innerHeight = 200;
        document = { documentElement: {
          style: { setProperty: function () {} },
          getAttribute: function () { return null; },
          setAttribute: function () {},
          removeAttribute: function () {},
          getBoundingClientRect: function () { return { width: 300, height: 150 }; },
          scrollWidth: 300
        } };
        """)
        let value = context.evaluateScript(AetherExtensionPopup.sizingExpression)
        #expect(context.exception == nil)
        let pair = try #require(value?.toArray() as? [NSNumber]).map(\.doubleValue)
        #expect(pair == [300, 150])
    }
}
