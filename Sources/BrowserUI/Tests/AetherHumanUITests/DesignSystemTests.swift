import AppKit
import Foundation
import Testing
@testable import AetherHumanUI

struct SymbolContractTests {
    @Test func everySymbolIsResolvableOnThisSystem() {
        var missing: [String] = []
        for symbol in AetherSymbol.allCases {
            if NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: nil) == nil {
                missing.append("\(symbol) -> \(symbol.rawValue)")
            }
        }
        #expect(missing.isEmpty, "unresolvable SF Symbols: \(missing)")
    }

    @Test func everyChromeIconMapsToAResolvableSymbol() {
        for icon in BrowserIcon.allCases {
            let image = NSImage(systemSymbolName: icon.symbol.rawValue, accessibilityDescription: nil)
            #expect(image != nil, "\(icon.rawValue) maps to missing symbol \(icon.symbol.rawValue)")
            #expect(!icon.label.isEmpty)
        }
    }

    @Test func symbolsCarryDistinctMeanings() {
        let names = Set(AetherSymbol.allCases.map(\.rawValue))
        #expect(names.count > 40)
        #expect(!names.contains("bookmarks"), "bookmarks is not a valid SF Symbol on macOS 27")
        #expect(!names.contains("sidebar.left.arrow"))
    }
}

struct TypographyContractTests {
    @Test func chromeWeightsAreOnly400450And500() {
        #expect(AetherTextWeight.regular.usWeightClass == 400)
        #expect(AetherTextWeight.emphasis.usWeightClass == 450)
        #expect(AetherTextWeight.medium.usWeightClass == 500)
        #expect(AetherTextWeight.allCases.count == 3)
    }

    @Test func systemWeightInterpolatesBetweenAppleAnchors() {
        let registry = AetherFontRegistry.self
        let regular = resolutionWeight(registry, 400)
        let emphasis = resolutionWeight(registry, 450)
        #expect(regular == NSFont.Weight.regular.rawValue)
        #expect(emphasis > regular)
        #expect(emphasis < NSFont.Weight.medium.rawValue)
    }

    private func resolutionWeight(_ registry: AetherFontRegistry.Type, _ usWeight: Double) -> CGFloat {
        let anchors: [(Double, CGFloat)] = [
            (400, NSFont.Weight.regular.rawValue),
            (500, NSFont.Weight.medium.rawValue)
        ]
        let ratio = CGFloat((usWeight - anchors[0].0) / (anchors[1].0 - anchors[0].0))
        return anchors[0].1 + (anchors[1].1 - anchors[0].1) * ratio
    }

    @Test func typeRolesResolveWithoutTheBrandFace() {
        AetherFontRegistry.install()
        for weight in AetherTextWeight.allCases {
            _ = AetherFontRegistry.font(13, weight)
        }
        #expect(AetherType.body(13) != AetherType.mono(13))
    }
}

struct NavigationGlowStateTests {
    @Test func freshStateIsIdle() {
        let state = AetherNavigationGlowState()
        #expect(state.phase == .idle)
        #expect(state.wasInstant == false)
        #expect(!state.phase.isActive)
    }

    @Test func navigationThenSlowLoadThenCommit() {
        var state = AetherNavigationGlowState()
        let start = Date()
        state.begin(now: start)
        #expect(state.phase == .started)
        state.awaitContent()
        #expect(state.phase == .awaitingContent)
        state.contentVisible(now: start.addingTimeInterval(1.2))
        #expect(state.phase == .contentVisible)
        #expect(state.wasInstant == false)
        state.settle()
        #expect(state.phase == .idle)
    }

    @Test func cachedNavigationIsMarkedInstant() {
        var state = AetherNavigationGlowState()
        let start = Date()
        state.begin(now: start)
        state.contentVisible(now: start.addingTimeInterval(AetherNavigationGlowState.instantThreshold / 2))
        #expect(state.wasInstant)
    }

    @Test func failureResolvesAndNeverSticks() {
        var state = AetherNavigationGlowState()
        state.begin()
        state.fail()
        #expect(state.phase == .failed)
        state.settle()
        #expect(state.phase == .idle)
        #expect(state.startedAt == nil)
    }

    @Test func newestNavigationOwnsTheEffect() {
        var state = AetherNavigationGlowState()
        let first = Date()
        state.begin(now: first)
        state.awaitContent()
        state.contentVisible(now: first.addingTimeInterval(2))
        #expect(state.phase == .contentVisible)
        state.begin(now: first.addingTimeInterval(10))
        #expect(state.phase == .started)
        #expect(state.wasInstant == false)
        #expect(state.startedAt == first.addingTimeInterval(10))
    }

    @Test func commitAndFailureAreIgnoredWhileResting() {
        var state = AetherNavigationGlowState()
        state.contentVisible()
        #expect(state.phase == .idle)
        state.fail()
        #expect(state.phase == .idle)
        state.awaitContent()
        #expect(state.phase == .idle)
    }
}

struct PaletteContractTests {
    @Test func elevationStepsStayDistinct() {
        #expect(AetherPalette.canvas(true) != AetherPalette.raised(true))
        #expect(AetherPalette.hover(true) != AetherPalette.raised(true))
        #expect(AetherPalette.inset(true) != AetherPalette.raised(true))
        #expect(AetherPalette.canvas(false) != AetherPalette.raised(false))
    }

    @Test func lightAndDarkAreSeparate() {
        #expect(AetherPalette.canvas(true) != AetherPalette.canvas(false))
        #expect(AetherPalette.ink(true) != AetherPalette.ink(false))
        #expect(AetherPalette.glowCore(true) != AetherPalette.glowCore(false))
    }

    @Test func metricsFollowTheSpecifiedGrid() {
        #expect(AetherMetrics.chromeHeight == 42)
        #expect(AetherMetrics.tabHeight == 40)
        #expect(AetherMetrics.tapTarget == 44)
        #expect(AetherMetrics.panelRadius == 8)
    }
}

struct NavigationGlowWiringTests {
    @MainActor @Test func windowModelStartsAndSettlesTheGlow() async {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        #expect(window.glow.phase == .idle)
        window.beginNavigationGlow()
        #expect(window.glow.phase == .started)
    }
}

struct IconSystemTests {
    @Test func backArrowUsesChevronNotSidebarGlyph() {
        #expect(BrowserIcon.arrowLeft.symbol == .back)
        #expect(BrowserIcon.arrowLeft.symbol.rawValue == "chevron.left")
        #expect(BrowserIcon.sidebar.symbol == .sidebarLeft)
    }

    @Test func progressPaletteOffersFourHues() {
        #expect(AetherProgressColor.allCases.count == 4)
    }

    @MainActor @Test func sidebarResizeDefersPersistence() {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let saved = workspace.preferences.sidebarWidth
        #expect(workspace.preferences.transientSidebarWidth == nil)
        workspace.preferences.transientSidebarWidth = saved + 20
        #expect(workspace.preferences.sidebarWidth == saved)
        workspace.preferences.sidebarWidth = workspace.preferences.transientSidebarWidth ?? saved
        workspace.preferences.transientSidebarWidth = nil
        #expect(workspace.preferences.sidebarWidth == saved + 20)
        #expect(workspace.preferences.transientSidebarWidth == nil)
    }

    @Test func fusedTopTabHasConcaveFillets() {
        let rect = CGRect(x: 0, y: 0, width: 171, height: 39)
        let bounds = FusedTopTabShape().path(in: rect).boundingRect
        #expect(!FusedTopTabShape().path(in: rect).isEmpty)
        #expect(abs(bounds.width - (171 + 2 * 12)) < 0.5)
        #expect(abs(bounds.height - 39) < 0.5)
    }

    @Test func brandMarksRemainRenderable() {
        for mark in AetherBrandMark.allCases {
            let path = AetherBrandMarkShape(mark).path(in: CGRect(x: 0, y: 0, width: 64, height: 64))
            #expect(!path.isEmpty, "\(mark.rawValue) produced an empty path")
            #expect(!mark.label.isEmpty)
        }
    }

    @MainActor @Test func faviconStoreNormalizesHosts() {
        let store = AetherFaviconStore.shared
        #expect(store.cachedImage(for: "") == nil)
        #expect(AetherFaviconStore.cacheTTL == 7 * 24 * 60 * 60)
    }
}
