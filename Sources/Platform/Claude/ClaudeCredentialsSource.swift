import Foundation

/// Reads Claude Code's credentials item from the Keychain.
protocol ClaudeKeychainReading: Sendable {
    /// `allowingPrompt` is true only right after a user action, so background reads never show a Keychain prompt.
    func credentialsData(allowingPrompt: Bool) -> ClaudeKeychainRead
}

enum ClaudeKeychainRead: Sendable {
    case notFound
    /// The item exists but macOS needs the user to allow CodexPill to read it.
    case needsPermission
    case failed
    case found(Data)
}

enum ClaudeCredentialsLookup: Sendable {
    case signedOut
    case keychainAccessNeeded
    case unreadable
    case credentials(ClaudeCredentials)
}

/// Finds Claude Code's sign-in: `.credentials.json` in its config folder first, then the Keychain. Read-only.
struct ClaudeCredentialsSource: Sendable {
    let configDirectory: URL
    /// Nil in isolated runs, so they never read the real Keychain item.
    let keychain: (any ClaudeKeychainReading)?

    var credentialsFileURL: URL {
        configDirectory.appendingPathComponent(".credentials.json")
    }

    /// A credentials file without a Claude sign-in, for example one with only `mcpOAuth`, falls through to the Keychain.
    func lookup(allowingPrompt: Bool) -> ClaudeCredentialsLookup {
        do {
            if let data = try Self.contentsIfPresent(of: credentialsFileURL), let credentials = try ClaudeCredentials(json: data) {
                return .credentials(credentials)
            }
        } catch {
            return .unreadable
        }
        guard let keychain else { return .signedOut }
        switch keychain.credentialsData(allowingPrompt: allowingPrompt) {
        case .notFound: return .signedOut
        case .needsPermission: return .keychainAccessNeeded
        case .failed: return .unreadable
        case let .found(data):
            do {
                return try ClaudeCredentials(json: data).map(ClaudeCredentialsLookup.credentials) ?? .signedOut
            } catch {
                return .unreadable
            }
        }
    }

    /// Nil when the file does not exist. Any other read failure throws.
    static func contentsIfPresent(of url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// `CLAUDE_CONFIG_DIR` when set, otherwise `~/.claude`, matching Claude Code.
    static func configDirectory(environment: [String: String]) -> URL {
        if let path = environment["CLAUDE_CONFIG_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }
}
