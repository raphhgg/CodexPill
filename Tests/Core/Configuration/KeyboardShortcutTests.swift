import Foundation
import Testing

@testable import RUsage

struct KeyboardShortcutTests {
    @Test
    func defaultRevealShortcutPreservesPersistedShape() throws {
        let shortcut = KeyboardShortcut.defaultRevealStatusItemTitle

        #expect(shortcut.keyCode == 37)
        #expect(shortcut.modifiers == [.control, .option, .command])
        #expect(shortcut.isValid)

        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: data)

        #expect(decoded == shortcut)
    }

    @Test
    func shortcutWithoutModifiersIsInvalid() {
        let shortcut = KeyboardShortcut(keyCode: 11, modifiers: [])

        #expect(!shortcut.isValid)
    }
}
