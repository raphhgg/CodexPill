import AppKit
import Testing

@testable import RUsage

struct KeyboardShortcutPresentationTests {
    @Test
    func displayTitleUsesNativeShortcutGlyphOrder() {
        let shortcut = KeyboardShortcut(keyCode: 11, modifiers: [.control, .shift])

        let presentation = KeyboardShortcutPresentation(shortcut: shortcut)

        #expect(presentation.displayTitle == "⌃⇧B")
    }

    @Test
    func nativeMenuKeyEquivalentUsesAppKitModifierFlags() {
        let shortcut = KeyboardShortcut(keyCode: 37, modifiers: [.control, .option, .command])

        let presentation = KeyboardShortcutPresentation(shortcut: shortcut)

        #expect(presentation.keyEquivalent == "l")
        #expect(presentation.modifierFlags == [.control, .option, .command])
    }

    @Test
    func unknownKeyCodeStillHasDisplayTitleButNoNativeKeyEquivalent() {
        let shortcut = KeyboardShortcut(keyCode: 999, modifiers: [.command])

        let presentation = KeyboardShortcutPresentation(shortcut: shortcut)

        #expect(presentation.displayTitle == "⌘Key 999")
        #expect(presentation.keyEquivalent == nil)
    }
}
