import Foundation

/// How the menu drives a tool that CodexPill reads with that tool's own sign-in: Claude Code and Cursor.
///
/// A tool plugs in by conforming once and being listed in `AppComposition`. The menu never names a tool: it sends a
/// `ProviderAction`, and `ProviderUsageRuntime` runs it, then refreshes that tool. Codex is not a connection, because
/// its usage lives on each saved `CodexAccount` and adding a Codex account is an interactive sign-in panel. The
/// coordinator routes `.codex` actions to `AccountsController` instead.
protocol ProviderConnection: UsageProviderSource {
    /// Reads with the tool's sign-in from now on, and lets the next read show a macOS prompt because the user asked.
    /// Calling it again, as "Allow Keychain access…" does, only allows the prompt again. Returns false when the tool
    /// has no sign-in to read, so the user has to sign in with `signIn` first.
    @discardableResult
    func connect() async -> Bool
    func disconnect() async throws(ProviderNotice)
    /// CodexPill's own browser sign-in for this tool, or nil when it reads only the tool's sign-in.
    var signIn: (any ProviderSignIn)? { get }

    /// Saved sign-ins, marked with the one the tool uses now. Empty when this build can't switch.
    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount]
    func switchAccount(to id: UUID) async throws(ProviderNotice)
    /// Saves the sign-in the tool uses now, so the user can switch back to it.
    func addCurrentAccount() async throws(ProviderNotice)
    /// Forgets a saved sign-in. The tool stays signed in.
    func removeAccount(_ id: UUID) async throws(ProviderNotice)
}

/// CodexPill's own sign-in for a tool, in the browser.
protocol ProviderSignIn: Sendable {
    /// Returns true once the user signed in, or false when they cancelled.
    func run() async throws(ProviderNotice) -> Bool
    func cancel() async
}

/// A saved sign-in as the menu may show it. It never carries tokens.
struct ProviderAccount: Equatable, Identifiable, Sendable {
    let id: UUID
    var email: String?
    var isActive: Bool
}

/// One thing the user asked a tool section to do. Every tool menu item carries one, for any tool.
enum ProviderAction: Hashable, Sendable {
    case connect
    case allowKeychainAccess
    case signIn
    case cancelSignIn
    case disconnect
    case switchAccount(UUID)
    case addAccount
    case removeAccount(UUID)
    /// Codex only: spends one reset credit on the active account.
    case useResetCredit

    /// The action without its account ID, for diagnostics.
    var name: String {
        switch self {
        case .connect: "connect"
        case .allowKeychainAccess: "allowKeychainAccess"
        case .signIn: "signIn"
        case .cancelSignIn: "cancelSignIn"
        case .disconnect: "disconnect"
        case .switchAccount: "switchAccount"
        case .addAccount: "addAccount"
        case .removeAccount: "removeAccount"
        case .useResetCredit: "useResetCredit"
        }
    }
}

/// The `representedObject` of every tool menu item.
struct ProviderMenuAction: Hashable, Sendable {
    let provider: UsageProvider
    let action: ProviderAction
}

/// An alert a tool asks the menu to show: a title and at most one short line.
struct ProviderNotice: Error, Equatable, Sendable {
    let title: String
    let detail: String?
}

/// A question the menu asks before it runs an action.
struct ProviderPrompt: Equatable, Sendable {
    let title: String
    let detail: String
    let confirmTitle: String
}
