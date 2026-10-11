import Foundation

/// How the menu drives a tool other than Codex: Claude Code and Cursor. Each saved account is the tool's own sign-in,
/// held by CodexPill; the tool's live sign-in is the account in use.
///
/// A tool plugs in by conforming once and being listed in `AppComposition`. The menu never names a tool: it sends a
/// `ProviderAction`, and `ProviderUsageRuntime` runs it, then refreshes that tool. Codex is not a connection, because
/// its usage lives on each saved `CodexAccount` and adding a Codex account is an interactive sign-in panel. The
/// coordinator routes `.codex` actions to `AccountsController` instead.
protocol ProviderConnection: UsageProviderSource {
    /// The user connected this tool, so the menu shows its card before its first read lands.
    var isConnected: Bool { get }
    /// Reads with the tool's live sign-in from now on, and lets the next read show a macOS prompt because the user
    /// asked. Calling it again, as "Allow Keychain access…" does, only allows the prompt again.
    func connect() async
    func disconnect() async
    /// Whether `addAccount()` can run the tool's own sign-in on this Mac.
    var signInAvailability: ProviderSignInAvailability { get }

    /// Saved accounts with their last limits, marked with the one the tool uses now. Empty when this build can't switch.
    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount]
    func switchAccount(to id: UUID) async throws(ProviderNotice)
    /// Runs the tool's own sign-in away from its live sign-in and saves the account. Returns false when the calling
    /// task was cancelled, which stops the sign-in.
    func addAccount() async throws(ProviderNotice) -> Bool
    /// Saves the sign-in the tool uses now, so the user can switch back to it.
    func addCurrentAccount() async throws(ProviderNotice)
    /// Forgets a saved account. The tool stays signed in.
    func removeAccount(_ id: UUID) async throws(ProviderNotice)
    /// Reads the limits of a saved account the tool is not signed in to, with that account's own sign-in. The live
    /// sign-in is never read or changed.
    func refreshInactiveAccount(_ id: UUID, now: Date) async
    /// Lets the tool renew its own expired live sign-in while the tool is not running. True when the sign-in changed,
    /// so the tool should be read again.
    func renewLiveSignInIfNeeded(now: Date) async -> Bool
}

extension ProviderConnection {
    func refreshInactiveAccount(_: UUID, now _: Date) async {}
    func renewLiveSignInIfNeeded(now _: Date) async -> Bool { false }
}

enum ProviderSignInAvailability: Equatable, Sendable {
    case available
    /// The tool's command-line sign-in is not on this Mac.
    case notInstalled
    /// The tool adds accounts only by saving its current sign-in.
    case unsupported
}

/// A saved account as the menu may show it. It never carries tokens.
struct ProviderAccount: Equatable, Identifiable, Sendable {
    let id: UUID
    var email: String?
    /// What to call an account without an email, such as its organization.
    var name: String? = nil
    var isActive: Bool
    /// The last limits read with this account's own sign-in. Nil until the first read.
    var usage: UsageSnapshot? = nil
}

/// One thing the user asked a tool section to do. Every tool menu item carries one, for any tool.
enum ProviderAction: Hashable, Sendable {
    case connect
    case allowKeychainAccess
    case cancelSignIn
    case disconnect
    case switchAccount(UUID)
    case addAccount
    case saveCurrentAccount
    case removeAccount(UUID)
    /// Codex only: spends one reset credit on the active account.
    case useResetCredit

    /// The action without its account ID, for diagnostics.
    var name: String {
        switch self {
        case .connect: "connect"
        case .allowKeychainAccess: "allowKeychainAccess"
        case .cancelSignIn: "cancelSignIn"
        case .disconnect: "disconnect"
        case .switchAccount: "switchAccount"
        case .addAccount: "addAccount"
        case .saveCurrentAccount: "saveCurrentAccount"
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
