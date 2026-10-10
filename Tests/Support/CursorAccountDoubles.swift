import Foundation

@testable import CodexPill

final class CursorAccountStoreHarness: CursorAccountStore, @unchecked Sendable {
    private let lock = NSLock()
    private var accounts: [CursorSavedAccount] = []

    func load() throws -> [CursorSavedAccount] {
        lock.withLock { accounts }
    }

    func save(_ accounts: [CursorSavedAccount]) throws {
        lock.withLock { self.accounts = accounts }
    }
}

final class CursorAppProcessProbe: CursorAppProcessClient, @unchecked Sendable {
    enum Event: Equatable {
        case quit
        case open
    }

    private let lock = NSLock()
    private var recorded: [Event] = []
    var quitError: (any Error)?
    var onQuit: (() throws -> Void)?

    var events: [Event] { lock.withLock { recorded } }
    var isRunning: Bool { true }

    func quit() async throws {
        lock.withLock { recorded.append(.quit) }
        try onQuit?()
        if let quitError { throw quitError }
    }

    func open() async throws {
        lock.withLock { recorded.append(.open) }
    }
}
