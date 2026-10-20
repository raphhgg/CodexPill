import Testing

@testable import RUsage

struct ShortcutCapturePanelTests {
    @Test
    func startsWithoutShortcutByOfferingDefaultShortcut() {
        let state = ShortcutCaptureState(currentShortcut: nil)

        #expect(state.displayTitle == "⌃⌥⌘L")
        #expect(state.canSave)
        #expect(state.statusKind == .idle)
        #expect(state.saveResult() == .saved(.defaultRevealStatusItemTitle))
    }

    @Test
    func startsWithExistingShortcutAsUnchangedAndUnsavable() {
        let shortcut = KeyboardShortcut(keyCode: 37, modifiers: [.control, .option, .command])
        let state = ShortcutCaptureState(currentShortcut: shortcut)

        #expect(state.displayTitle == "⌃⌥⌘L")
        #expect(!state.canSave)
        #expect(state.statusKind == .idle)
        #expect(state.saveResult() == nil)
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
    func ignoresShortcutWithoutModifiers() {
        var state = ShortcutCaptureState(currentShortcut: .defaultRevealStatusItemTitle)

        state.capture(KeyboardShortcut(keyCode: 11, modifiers: []))

        #expect(state.displayTitle == "⌃⌥⌘L")
        #expect(!state.canSave)
        #expect(state.statusKind == .idle)
        #expect(state.saveResult() == nil)
    }

    @Test
    func invalidShortcutDoesNotDiscardDefaultCandidate() {
        var state = ShortcutCaptureState(currentShortcut: nil)

        state.capture(KeyboardShortcut(keyCode: 11, modifiers: []))

        #expect(state.displayTitle == "⌃⌥⌘L")
        #expect(state.canSave)
        #expect(state.statusKind == .idle)
        #expect(state.saveResult() == .saved(.defaultRevealStatusItemTitle))
    }

    @Test
    func recapturingOriginalShortcutIsAllowedButNotSaveable() {
        let original = KeyboardShortcut(keyCode: 37, modifiers: [.control, .option, .command])
        var state = ShortcutCaptureState(currentShortcut: original)

        state.capture(KeyboardShortcut(keyCode: 0, modifiers: [.control, .option, .command]))
        #expect(state.canSave)

        state.capture(original)

        #expect(state.displayTitle == "⌃⌥⌘L")
        #expect(!state.canSave)
        #expect(state.statusKind == .idle)
        #expect(state.saveResult() == nil)
    }
}
