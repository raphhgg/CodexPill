import Foundation

/// How the menu drives a tool other than Codex: Claude Code and Cursor. rusage reads the one account each tool is
/// signed in to and never writes the tool's sign-in. Claude also offers rusage's own sign-in, kept apart from Claude
/// Code's.
///
/// A tool plugs in by conforming once and being listed in `AppComposition`. The menu never names a tool: it sends a
/// `ProviderAction`, and `ProviderUsageRuntime` runs it, then refreshes that tool. Codex is not a connection, because
/// its usage lives on each saved `CodexAccount` and adding a Codex account is an interactive sign-in panel. The
/// coordinator routes `.codex` actions to `AccountsController` instead.
protocol ProviderConnection: UsageProviderSource {
    /// The user connected this tool, so the menu shows its card before its first read lands.
    var isConnected: Bool { get }
    /// Reads with the tool's live sign-in from now on, and lets the next read show a macOS prompt because the user
    /// asked. Calling it again, as "Allow Keychain Access…" does, only allows the prompt again.
    func connect() async
    func disconnect() async
    /// Whether rusage can sign in to this tool itself, and whether it is.
    var ownSignIn: ProviderOwnSignIn { get }
    /// Runs rusage's own sign-in. A cancelled sign-in ends without a notice.
    func signIn() async throws(ProviderNotice)
    func signOut() async throws(ProviderNotice)
}

extension ProviderConnection {
    var ownSignIn: ProviderOwnSignIn { .unsupported }
    func signIn() async throws(ProviderNotice) {}
    func signOut() async throws(ProviderNotice) {}
}

enum ProviderOwnSignIn: Equatable, Sendable {
    /// The tool only offers its own app's sign-in.
    case unsupported
    case signedOut
    case signedIn
}

/// What the user should be told after an action, as a title plus at most one short line.
struct ProviderNotice: Error, Equatable {
    let title: String
    let detail: String?
}

/// One thing the user asked a tool section to do. Every tool menu item carries one, for any tool.
enum ProviderAction: Hashable, Sendable {
    case connect
    case allowKeychainAccess
    case disconnect
    /// Codex only, like using a reset: signs in to another account, which then replaces the one on this Mac.
    case addAccount
    /// Spends one reset credit on the active account.
    case useResetCredit
    /// rusage's own sign-in, for a tool that offers one.
    case signIn
    case signOut

    /// The action without its account ID, for diagnostics.
    var name: String {
        switch self {
        case .connect: "connect"
        case .allowKeychainAccess: "allowKeychainAccess"
        case .disconnect: "disconnect"
        case .addAccount: "addAccount"
        case .useResetCredit: "useResetCredit"
        case .signIn: "signIn"
        case .signOut: "signOut"
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
