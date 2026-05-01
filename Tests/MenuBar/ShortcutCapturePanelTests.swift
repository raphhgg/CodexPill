import Testing

@testable import CodexPill

struct ShortcutCapturePanelTests {
    @Test
    func startsWithoutShortcutAsUnsavable() {
        let state = ShortcutCaptureState(currentShortcut: nil)

        #expect(state.displayTitle == "Waiting for shortcut")
        #expect(!state.canSave)
        #expect(state.statusKind == .idle)
    }

    @Test
    func capturesValidShortcutForSave() {
        var state = ShortcutCaptureState(currentShortcut: nil)
        let shortcut = KeyboardShortcut(keyCode: 11, modifiers: [.control, .shift])

        state.capture(shortcut)

        #expect(state.displayTitle == "⌃⇧B")
        #expect(state.canSave)
        #expect(state.statusKind == .valid)
        #expect(state.saveResult() == .saved(shortcut))
    }

    @Test
    func rejectsShortcutWithoutModifiers() {
        var state = ShortcutCaptureState(currentShortcut: .defaultRevealStatusItemTitle)

        state.capture(KeyboardShortcut(keyCode: 11, modifiers: []))

        #expect(state.displayTitle == "Waiting for shortcut")
        #expect(!state.canSave)
        #expect(state.statusKind == .invalid)
        #expect(state.saveResult() == nil)
    }
}
