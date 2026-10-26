import Foundation

/// Whether rusage reads Codex. On until the user hides Codex in Show Tools.
struct CodexSettings: SettingsGroup {
    static let key = "settings.codex.v1"
    static let defaults = CodexSettings()

    var isConnected = true
}

extension CodexSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isConnected = container.value(.isConnected, or: Self.defaults.isConnected)
    }
}

/// Whether Claude Code usage is connected: the user agreed that rusage may read Claude Code's sign-in and send it
/// to Anthropic to fetch limits. Off until they connect it.
struct ClaudeSettings: SettingsGroup {
    static let key = "settings.claude.v1"
    static let defaults = ClaudeSettings()

    var isConnected = false
    /// Whether usage reads use rusage's own "Sign in with Claude" instead of Claude Code's sign-in. On after a browser
    /// sign-in succeeds, off after Sign Out or disconnect.
    var usesOwnSignIn = false
    /// Whether the Claude card shows per-model weekly limits, such as "Fable this week". On until the user turns it
    /// off.
    var showsModelLimits = true
}

extension ClaudeSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        isConnected = container.value(.isConnected, or: defaults.isConnected)
        usesOwnSignIn = container.value(.usesOwnSignIn, or: defaults.usesOwnSignIn)
        showsModelLimits = container.value(.showsModelLimits, or: defaults.showsModelLimits)
    }
}

/// Whether the user agreed to let rusage read Cursor's sign-in. Off until they connect Cursor.
struct CursorSettings: SettingsGroup {
    static let key = "settings.cursor.v1"
    static let defaults = CursorSettings()

    var isConnected = false
    /// Whether usage reads use rusage's own Cursor sign-in instead of the Cursor app's. On after a browser sign-in
    /// succeeds, off after Sign Out or disconnect.
    var usesOwnSignIn = false
}

extension CursorSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isConnected = container.value(.isConnected, or: Self.defaults.isConnected)
        usesOwnSignIn = container.value(.usesOwnSignIn, or: Self.defaults.usesOwnSignIn)
    }
}
