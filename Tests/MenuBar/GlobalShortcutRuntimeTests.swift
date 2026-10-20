import Carbon
import Testing

@testable import RUsage

@MainActor
struct GlobalShortcutRuntimeTests {
    @Test
    func applyRegistersShortcutWithClient() throws {
        let client = GlobalShortcutClientProbe()
        let runtime = GlobalShortcutRuntime(client: client)
        let shortcut = KeyboardShortcut(keyCode: 37, modifiers: [.control, .option, .command])

        try runtime.apply(shortcut: shortcut)

        #expect(client.registeredShortcuts == [shortcut])
        #expect(client.didUnregisterCount == 0)
    }

    @Test
    func clearUnregistersCurrentShortcut() throws {
        let client = GlobalShortcutClientProbe()
        let runtime = GlobalShortcutRuntime(client: client)

        try runtime.apply(shortcut: .defaultRevealStatusItemTitle)
        try runtime.apply(shortcut: nil)

        #expect(client.didUnregisterCount == 1)
    }

    @Test
    func registrationFailureKeepsPreviousShortcut() throws {
        let client = GlobalShortcutClientProbe()
        let runtime = GlobalShortcutRuntime(client: client)
        let previous = KeyboardShortcut(keyCode: 37, modifiers: [.control, .option, .command])
        let next = KeyboardShortcut(keyCode: 11, modifiers: [.control, .shift])

        try runtime.apply(shortcut: previous)
        client.errorToThrow = GlobalShortcutRegistrationError.registrationFailed(status: -9878)

        #expect(throws: GlobalShortcutRegistrationError.registrationFailed(status: -9878)) {
            try runtime.apply(shortcut: next)
        }
        #expect(client.registeredShortcuts == [previous, next, previous])
    }

    @Test
    func shortcutCallbackIsForwarded() {
        let client = GlobalShortcutClientProbe()
        let runtime = GlobalShortcutRuntime(client: client)
        var triggerCount = 0

        runtime.onShortcut = {
            triggerCount += 1
        }
        runtime.triggerForTesting()

        #expect(triggerCount == 1)
    }

    @Test
    func carbonRegistrationDescriptorUsesShortcutKeyCodeAndCarbonModifiers() {
        let shortcut = KeyboardShortcut(keyCode: 11, modifiers: [.control, .shift])

        let descriptor = CarbonShortcutRegistrationDescriptor(shortcut: shortcut)

        #expect(descriptor.keyCode == 11)
        #expect(descriptor.modifierFlags == UInt32(controlKey | shiftKey))
        #expect(descriptor.options == 0)
    }
}

private final class GlobalShortcutClientProbe: GlobalShortcutClient {
    var onShortcut: (() -> Void)?
    var registeredShortcuts: [KeyboardShortcut] = []
    var didUnregisterCount = 0
    var errorToThrow: Error?

    func register(shortcut: KeyboardShortcut) throws {
        registeredShortcuts.append(shortcut)
        if let errorToThrow {
            self.errorToThrow = nil
            throw errorToThrow
        }
    }

    func unregister() {
        didUnregisterCount += 1
    }
}
