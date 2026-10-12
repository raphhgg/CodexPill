import Foundation

/// How the menu drives a tool other than Codex: Claude Code and Cursor. CodexPill reads the one account each tool is
/// signed in to and never writes the tool's sign-in.
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
    /// Lets the tool renew its own expired live sign-in while the tool is not running. True when the sign-in changed,
    /// so the tool should be read again.
    func renewLiveSignInIfNeeded(now: Date) async -> Bool
}

extension ProviderConnection {
    func renewLiveSignInIfNeeded(now _: Date) async -> Bool { false }
}

/// One thing the user asked a tool section to do. Every tool menu item carries one, for any tool.
enum ProviderAction: Hashable, Sendable {
    case connect
    case allowKeychainAccess
    case disconnect
    /// Codex only, like adding, removing and using a reset: Claude Code and Cursor show only their live account.
    case switchAccount(UUID)
    case addAccount
    case removeAccount(UUID)
    /// Spends one reset credit on the active account.
    case useResetCredit

    /// The action without its account ID, for diagnostics.
    var name: String {
        switch self {
        case .connect: "connect"
        case .allowKeychainAccess: "allowKeychainAccess"
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

/// A question the menu asks before it runs an action.
struct ProviderPrompt: Equatable, Sendable {
    let title: String
    let detail: String
    let confirmTitle: String
}
