import Foundation

/// A Claude Code sign-in CodexPill saved so the user can switch back to it. The tokens live in CodexPill's own
/// Keychain item for this account, never in the catalog.
struct ClaudeCodeAccount: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var email: String?
    var organizationName: String?
    /// Claude Code's `subscriptionType`, for example `max` or `pro`.
    var planName: String?
    var identity: ClaudeCodeAccountIdentity?
    let createdAt: Date
    var updatedAt: Date
}

enum ClaudeCodeAccountError: Error, Equatable, Sendable {
    case unknownAccount
    /// CodexPill's item for this account is missing.
    case savedSignInMissing
    /// CodexPill's saved-account list or one of its Keychain items could not be read.
    case savedAccountsUnreadable
    /// Claude Code has no sign-in on this Mac. Signing in once with `claude` creates the item a switch updates.
    case claudeCodeSignedOut
    /// Claude Code's global config records no account for its sign-in, so CodexPill can't tell which account it is.
    case claudeCodeAccountUnknown
    /// Claude Code's sign-in is not saved in CodexPill, so switching away would lose it.
    case currentSignInNotSaved
    /// A running Claude Code would write its old sign-in back, so switching waits until it quits.
    case claudeCodeRunning
    case keychainAccessNeeded
    /// Claude Code's credentials or its global config could not be read or parsed.
    case unreadable
    /// A write failed and everything it had changed was put back.
    case writeFailed
    /// A write failed and putting the earlier state back failed too.
    case restoreFailed
}

/// CodexPill's saved-account items, one per saved Claude Code account.
protocol ClaudeCodeAccountItemStoring: Sendable {
    /// Nil when there is no item. Throws when the item exists but can't be read.
    func read(_ id: UUID) throws(ClaudeCodeAccountError) -> Data?
    func save(_ data: Data, for id: UUID) -> Bool
    /// True when the item is gone afterwards, including when there was none.
    func delete(_ id: UUID) -> Bool
}

/// Saves Claude Code sign-ins and switches between them, the way Codex accounts switch through `auth.json`
/// snapshots. Every call is a user action, so it may show the macOS Keychain prompt for Claude Code's item.
///
/// A switch first saves the outgoing sign-in again, because Claude Code rotates its refresh token when it renews
/// the access token: the copy CodexPill saved earlier may no longer work. A switch changes CodexPill's item and
/// list, then Claude Code's credentials, then its global config. When any step fails, every earlier step is put back.
struct ClaudeCodeAccountStore: Sendable {
    let catalogFile: URL
    let items: any ClaudeCodeAccountItemStoring
    let claudeCode: ClaudeCodeSignInStore
    let processes: any ClaudeCodeProcessDetecting
    var now: @Sendable () -> Date = Date.init

    func accounts() throws(ClaudeCodeAccountError) -> [ClaudeCodeAccount] {
        do {
            guard let data = try ClaudeCredentialsSource.contentsIfPresent(of: catalogFile) else { return [] }
            return try Self.decoder.decode([ClaudeCodeAccount].self, from: data)
        } catch {
            throw .savedAccountsUnreadable
        }
    }

    /// The saved account Claude Code is signed in to, from Claude Code's account record. No Keychain read.
    func activeAccountID() throws(ClaudeCodeAccountError) -> UUID? {
        guard let identity = try claudeCode.currentIdentity() else { return nil }
        return try accounts().first { $0.identity == identity }?.id
    }

    /// Saves Claude Code's current sign-in. Saving an account that is already saved refreshes its sign-in and plan
    /// and keeps its name unless `name` is given.
    @discardableResult
    func captureCurrent(named name: String? = nil) throws(ClaudeCodeAccountError) -> ClaudeCodeAccount {
        let (current, _) = try currentSignIn()
        var catalog = try accounts()
        let index: Int
        if let existing = savedIndex(of: current, in: catalog) {
            index = existing
        } else {
            catalog.append(ClaudeCodeAccount(
                id: UUID(),
                name: current.email ?? current.organizationName ?? "Claude Account",
                createdAt: now(),
                updatedAt: now()
            ))
            index = catalog.endIndex - 1
        }
        if let name { catalog[index].name = name }

        var undo = Undo()
        do throws(ClaudeCodeAccountError) {
            try save(current, into: &catalog[index], undo: &undo)
            try write(catalog, undo: &undo)
        } catch {
            throw undo.rollBack(after: error)
        }
        return catalog[index]
    }

    /// Signs Claude Code in to a saved account. The outgoing sign-in is saved again first; a sign-in that is not
    /// saved is never overwritten.
    func activate(_ id: UUID) throws(ClaudeCodeAccountError) {
        guard !processes.isClaudeCodeRunning() else { throw .claudeCodeRunning }
        var catalog = try accounts()
        guard let targetIndex = catalog.firstIndex(where: { $0.id == id }) else { throw .unknownAccount }
        guard let targetData = try items.read(id) else { throw .savedSignInMissing }
        guard let target = ClaudeCodeSignInSnapshot(itemData: targetData) else { throw .savedAccountsUnreadable }

        let (current, item) = try currentSignIn()
        guard let outgoingIndex = savedIndex(of: current, in: catalog) else {
            throw .currentSignInNotSaved
        }

        var undo = Undo()
        do throws(ClaudeCodeAccountError) {
            try save(current, into: &catalog[outgoingIndex], undo: &undo)
            try write(catalog, undo: &undo)
            if outgoingIndex != targetIndex {
                try claudeCode.replace(item, with: target)
            }
        } catch {
            throw undo.rollBack(after: error)
        }
    }

    func rename(_ id: UUID, to name: String) throws(ClaudeCodeAccountError) {
        var catalog = try accounts()
        guard let index = catalog.firstIndex(where: { $0.id == id }) else { throw .unknownAccount }
        catalog[index].name = name
        catalog[index].updatedAt = now()
        var undo = Undo()
        try write(catalog, undo: &undo)
    }

    /// Forgets a saved account. Claude Code's own sign-in is left as it is.
    func delete(_ id: UUID) throws(ClaudeCodeAccountError) {
        let catalog = try accounts()
        guard catalog.contains(where: { $0.id == id }) else { throw .unknownAccount }
        var undo = Undo()
        try write(catalog.filter { $0.id != id }, undo: &undo)
        guard items.delete(id) else { throw undo.rollBack(after: .writeFailed) }
    }

    private func currentSignIn() throws(ClaudeCodeAccountError) -> (ClaudeCodeSignInSnapshot, ClaudeCodeCredentialsItem) {
        switch claudeCode.current(allowingPrompt: true) {
        case .signedOut: throw .claudeCodeSignedOut
        case .keychainAccessNeeded: throw .keychainAccessNeeded
        case .unreadable: throw .unreadable
        case let .signedIn(snapshot, item):
            guard snapshot.identity != nil else { throw .claudeCodeAccountUnknown }
            return (snapshot, item)
        }
    }

    /// Accounts match by Claude Code's account record only. Tokens are never compared.
    private func savedIndex(of current: ClaudeCodeSignInSnapshot, in catalog: [ClaudeCodeAccount]) -> Int? {
        catalog.firstIndex { $0.identity != nil && $0.identity == current.identity }
    }

    private func save(
        _ signIn: ClaudeCodeSignInSnapshot,
        into account: inout ClaudeCodeAccount,
        undo: inout Undo
    ) throws(ClaudeCodeAccountError) {
        let id = account.id
        let previous = try items.read(id)
        guard items.save(signIn.itemData, for: id) else { throw .writeFailed }
        undo.add { [items] in
            previous.map { items.save($0, for: id) } ?? items.delete(id)
        }
        account.email = signIn.email ?? account.email
        account.organizationName = signIn.organizationName ?? account.organizationName
        account.planName = signIn.subscriptionType ?? account.planName
        account.identity = signIn.identity ?? account.identity
        account.updatedAt = now()
    }

    private func write(_ catalog: [ClaudeCodeAccount], undo: inout Undo) throws(ClaudeCodeAccountError) {
        let file = catalogFile
        let previous: Data?
        do {
            previous = try ClaudeCredentialsSource.contentsIfPresent(of: file)
            try FilePermissionHardening.createPrivateDirectory(at: file.deletingLastPathComponent())
            try Self.encoder.encode(catalog).write(to: file, options: .atomic)
            try FilePermissionHardening.repairPrivateFile(at: file)
        } catch {
            throw .writeFailed
        }
        undo.add { Self.restore(previous, at: file) }
    }

    /// Puts `data` back at `url`, or removes the file when there was none. False when that fails.
    static func restore(_ data: Data?, at url: URL) -> Bool {
        do {
            if let data {
                try data.write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// The steps a multi-write change has done so far, each with how to put it back.
private struct Undo {
    private var steps: [() -> Bool] = []

    mutating func add(_ step: @escaping () -> Bool) {
        steps.append(step)
    }

    /// Puts every done step back, last first, and returns the error to report: `restoreFailed` when any step
    /// could not be put back.
    func rollBack(after error: ClaudeCodeAccountError) -> ClaudeCodeAccountError {
        let restored = steps.reversed().map { $0() }.allSatisfy(\.self)
        return restored ? error : .restoreFailed
    }
}
