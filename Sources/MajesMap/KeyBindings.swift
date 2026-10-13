public enum BrowserAction: Equatable, Sendable {
    case selectPrevious, selectNext, pageUp, pageDown, selectFirst, selectLast
    case goUp, goBack, goForward, enter, quickLook, toggleCollector, rescanFolder, rescanAll
}

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1)
    public static let shift = KeyModifiers(rawValue: 2)
    public static let option = KeyModifiers(rawValue: 4)
    public static let control = KeyModifiers(rawValue: 8)
}

/// DaisyDisk's browsing shortcuts, by macOS virtual key code.
public enum KeyBindings {
    public static func action(keyCode: UInt16, modifiers: KeyModifiers) -> BrowserAction? {
        switch (keyCode, modifiers) {
        case (126, []): return .selectPrevious
        case (125, []): return .selectNext
        case (116, []): return .pageUp
        case (121, []): return .pageDown
        case (115, []): return .selectFirst
        case (119, []): return .selectLast
        case (126, .command): return .goUp
        case (33, .command): return .goBack
        case (30, .command): return .goForward
        case (36, []), (76, []): return .enter
        case (49, []): return .quickLook
        case (51, .command): return .toggleCollector
        case (15, .command): return .rescanFolder
        case (15, [.command, .shift]): return .rescanAll
        default: return nil
        }
    }
}
