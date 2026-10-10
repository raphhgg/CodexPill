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
    /// CodexPill's item for this account is missing or unreadable.
    case savedSignInMissing
    /// Claude Code has no sign-in on this Mac. Signing in once with `claude` creates the item a switch updates.
    case claudeCodeSignedOut
    /// Claude Code's sign-in is not saved in CodexPill, so switching away would lose it.
    case currentSignInNotSaved
    /// A running Claude Code would write its old sign-in back, so switching waits until it quits.
    case claudeCodeRunning
    case keychainAccessNeeded
    case unreadable
    case writeFailed
}

/// CodexPill's saved-account items, one per saved Claude Code account.
protocol ClaudeCodeAccountItemStoring: Sendable {
    func read(_ id: UUID) -> Data?
    @discardableResult
    func save(_ data: Data, for id: UUID) -> Bool
    func delete(_ id: UUID)
}

/// Saves Claude Code sign-ins and switches between them, the way Codex accounts switch through `auth.json`
/// snapshots. Every call is a user action, so it may show the macOS Keychain prompt for Claude Code's item.
///
/// A switch first saves the outgoing sign-in again, because Claude Code rotates its refresh token when it renews
/// the access token: the copy CodexPill saved earlier may no longer work.
struct ClaudeCodeAccountStore: Sendable {
    let catalogFile: URL
    let items: any ClaudeCodeAccountItemStoring
    let claudeCode: ClaudeCodeSignInStore
    let processes: any ClaudeCodeProcessDetecting
    var now: @Sendable () -> Date = Date.init

    func accounts() -> [ClaudeCodeAccount] {
        guard let data = try? Data(contentsOf: catalogFile) else { return [] }
        return (try? Self.decoder.decode([ClaudeCodeAccount].self, from: data)) ?? []
    }

    /// The saved account Claude Code is signed in to, from Claude Code's account record. No Keychain read.
    func activeAccountID() -> UUID? {
        guard let identity = claudeCode.currentIdentity() else { return nil }
        return accounts().first { $0.identity == identity }?.id
    }

    /// Saves Claude Code's current sign-in. Saving an account that is already saved refreshes its sign-in and plan
    /// and keeps its name unless `name` is given.
    @discardableResult
    func captureCurrent(named name: String? = nil) throws(ClaudeCodeAccountError) -> ClaudeCodeAccount {
        let (current, _) = try currentSignIn()
        var catalog = accounts()
        if let index = catalog.firstIndex(where: { matches($0, current) }) {
            try save(current, into: &catalog[index])
            if let name { catalog[index].name = name }
            try write(catalog)
            return catalog[index]
        }

        var account = ClaudeCodeAccount(
            id: UUID(),
            name: name ?? current.email ?? current.organizationName ?? "Claude Account",
            createdAt: now(),
            updatedAt: now()
        )
        try save(current, into: &account)
        catalog.append(account)
        try write(catalog)
        return account
    }

    /// Signs Claude Code in to a saved account. The outgoing sign-in is saved again first; a sign-in that is not
    /// saved is never overwritten.
    func activate(_ id: UUID) throws(ClaudeCodeAccountError) {
        guard !processes.isClaudeCodeRunning() else { throw .claudeCodeRunning }
        var catalog = accounts()
        guard let targetIndex = catalog.firstIndex(where: { $0.id == id }) else { throw .unknownAccount }
        guard let target = items.read(id).flatMap(ClaudeCodeSignInSnapshot.init(itemData:)) else {
            throw .savedSignInMissing
        }

        let (current, item) = try currentSignIn()
        guard let outgoingIndex = catalog.firstIndex(where: { matches($0, current) }) else {
            throw .currentSignInNotSaved
        }
        try save(current, into: &catalog[outgoingIndex])
        try write(catalog)
        guard outgoingIndex != targetIndex else { return }

        try claudeCode.replace(item, with: target)
    }

    func rename(_ id: UUID, to name: String) throws(ClaudeCodeAccountError) {
        var catalog = accounts()
        guard let index = catalog.firstIndex(where: { $0.id == id }) else { throw .unknownAccount }
        catalog[index].name = name
        catalog[index].updatedAt = now()
        try write(catalog)
    }

    /// Forgets a saved account. Claude Code's own sign-in is left as it is.
    func delete(_ id: UUID) throws(ClaudeCodeAccountError) {
        let catalog = accounts()
        guard catalog.contains(where: { $0.id == id }) else { throw .unknownAccount }
        try write(catalog.filter { $0.id != id })
        items.delete(id)
    }

    private func currentSignIn() throws(ClaudeCodeAccountError) -> (ClaudeCodeSignInSnapshot, ClaudeCodeCredentialsItem) {
        switch claudeCode.current(allowingPrompt: true) {
        case .signedOut: throw .claudeCodeSignedOut
        case .keychainAccessNeeded: throw .keychainAccessNeeded
        case .unreadable: throw .unreadable
        case let .signedIn(snapshot, item): return (snapshot, item)
        }
    }

    private func matches(_ account: ClaudeCodeAccount, _ current: ClaudeCodeSignInSnapshot) -> Bool {
        if let identity = account.identity, let currentIdentity = current.identity {
            return identity == currentIdentity
        }
        return items.read(account.id)
            .flatMap(ClaudeCodeSignInSnapshot.init(itemData:))
            .map { $0.isSameAccount(as: current) } ?? false
    }

    private func save(_ signIn: ClaudeCodeSignInSnapshot, into account: inout ClaudeCodeAccount) throws(ClaudeCodeAccountError) {
        guard items.save(signIn.itemData, for: account.id) else { throw .writeFailed }
        account.email = signIn.email ?? account.email
        account.organizationName = signIn.organizationName ?? account.organizationName
        account.planName = signIn.subscriptionType ?? account.planName
        account.identity = signIn.identity ?? account.identity
        account.updatedAt = now()
    }

    private func write(_ catalog: [ClaudeCodeAccount]) throws(ClaudeCodeAccountError) {
        do {
            try FilePermissionHardening.createPrivateDirectory(at: catalogFile.deletingLastPathComponent())
            try Self.encoder.encode(catalog).write(to: catalogFile, options: .atomic)
            try FilePermissionHardening.repairPrivateFile(at: catalogFile)
        } catch {
            throw .writeFailed
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
