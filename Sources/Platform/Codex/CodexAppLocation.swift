import AppKit

/// Finds the Codex desktop app by bundle ID, whatever its name: since October 2026 it installs as ChatGPT.app.
/// Launch Services can briefly miss an app that was just updated, so every registered copy and a running copy count.
struct CodexAppLocator: Sendable {
    static let bundleIdentifier = "com.openai.codex"

    var preferredURL: @Sendable () -> URL?
    var allURLs: @Sendable () -> [URL]
    var runningURL: @Sendable () -> URL?

    func appURL() -> URL? {
        preferredURL() ?? allURLs().first ?? runningURL()
    }

    static let live = CodexAppLocator(
        preferredURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) },
        allURLs: { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier) },
        runningURL: { NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.bundleURL }
    )
}

/// The Codex CLI the desktop app ships. ChatGPT.app keeps it at `codex-cli/bin/codex`, earlier Codex.app builds at
/// `codex`, both under `Contents/Resources`.
enum CodexBundledCLI {
    private static let relativePaths = ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"]

    static func executable(inAppAt appURL: URL, fileManager: FileManager = .default) -> URL? {
        relativePaths
            .map { appURL.appendingPathComponent($0, isDirectory: false) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

struct CodexAppNotFoundError: LocalizedError, Equatable {
    var errorDescription: String? { "Codex app not found" }
}
