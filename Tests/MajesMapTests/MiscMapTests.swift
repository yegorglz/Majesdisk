import Foundation
import Testing
@testable import MajesCore
@testable import MajesMap

private func seg(_ kind: SegmentKind, at angle: Double = 0, depth: Int = 1) -> SunburstSegment {
    SunburstSegment(node: 1, aggregateStartIndex: nil, kind: kind, depth: depth, startAngle: angle, endAngle: angle + 0.2)
}

@Test func paletteRules() {
    let file = SunburstPalette.color(for: seg(.file), highlighted: false)
    #expect(file.r == file.g && file.g == file.b)
    #expect(SunburstPalette.color(for: seg(.smallerObjects), highlighted: false).a == 0.35)
    #expect(SunburstPalette.color(for: seg(.restricted), highlighted: false) == RGBA.hsb(0.77, 0.45, 0.75))
    let dir = SunburstPalette.color(for: seg(.directory), highlighted: false)
    let lit = SunburstPalette.color(for: seg(.directory), highlighted: true)
    #expect(lit.r + lit.g + lit.b > dir.r + dir.g + dir.b)
    #expect(SunburstPalette.color(for: seg(.directory, at: 0), highlighted: false) != SunburstPalette.color(for: seg(.directory, at: .pi), highlighted: false))
    #expect(SunburstPalette.color(for: seg(.directory, depth: 1), highlighted: false) != SunburstPalette.color(for: seg(.directory, depth: 3), highlighted: false))
}

@Test func transitionEndpoints() {
    #expect(MapTransition.frame(t: 0, direction: .zoomIn) == TransitionFrame(outgoingScale: 1, outgoingAlpha: 1, incomingScale: 0.6, incomingAlpha: 0))
    #expect(MapTransition.frame(t: 1, direction: .zoomIn) == TransitionFrame(outgoingScale: 1.5, outgoingAlpha: 0, incomingScale: 1, incomingAlpha: 1))
    #expect(MapTransition.frame(t: 1, direction: .zoomOut) == TransitionFrame(outgoingScale: 0.6, outgoingAlpha: 0, incomingScale: 1, incomingAlpha: 1))
    #expect(MapTransition.frame(t: 7, direction: .zoomIn) == MapTransition.frame(t: 1, direction: .zoomIn))
    let mid = MapTransition.frame(t: 0.5, direction: .zoomIn)
    #expect(mid.incomingAlpha > 0 && mid.incomingAlpha < 1)
}

@Test func historyBackForward() {
    var h = NavigationHistory(start: 0)
    h.visit(1); h.visit(2)
    #expect(h.goBack() == 1 && h.goBack() == 0 && h.goBack() == nil)
    #expect(h.goForward() == 1 && h.canGoForward)
    h.visit(5)
    #expect(!h.canGoForward && h.current == 5)
    h.visit(5)
    #expect(h.goBack() == 1)
}

@Test func keyTable() {
    #expect(KeyBindings.action(keyCode: 126, modifiers: []) == .selectPrevious)
    #expect(KeyBindings.action(keyCode: 125, modifiers: []) == .selectNext)
    #expect(KeyBindings.action(keyCode: 126, modifiers: .command) == .goUp)
    #expect(KeyBindings.action(keyCode: 33, modifiers: .command) == .goBack)
    #expect(KeyBindings.action(keyCode: 30, modifiers: .command) == .goForward)
    #expect(KeyBindings.action(keyCode: 49, modifiers: []) == .quickLook)
    #expect(KeyBindings.action(keyCode: 36, modifiers: []) == .enter)
    #expect(KeyBindings.action(keyCode: 51, modifiers: .command) == .toggleCollector)
    #expect(KeyBindings.action(keyCode: 15, modifiers: .command) == .rescanFolder)
    #expect(KeyBindings.action(keyCode: 15, modifiers: [.command, .shift]) == .rescanAll)
    #expect(KeyBindings.action(keyCode: 116, modifiers: []) == .pageUp)
    #expect(KeyBindings.action(keyCode: 119, modifiers: []) == .selectLast)
    #expect(KeyBindings.action(keyCode: 49, modifiers: .command) == nil)
}
