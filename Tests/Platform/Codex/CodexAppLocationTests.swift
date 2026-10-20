import Foundation
import Testing

@testable import rusage

struct CodexAppLocationTests {
    @Test(arguments: ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"])
    func findsTheCLIInEitherAppLayout(cliPath: String) throws {
        let app = try FakeCodexApp(cliPath: cliPath)
        defer { app.remove() }
        let resolver = NSWorkspaceCodexExecutableResolver(locator: .only(app.url))

        #expect(try resolver.resolveCodexExecutable() == app.url.appendingPathComponent(cliPath))
    }

    @Test
    func findsTheAppWhenLaunchServicesHasNoPreferredCopy() throws {
        let app = try FakeCodexApp(cliPath: "Contents/Resources/codex-cli/bin/codex")
        defer { app.remove() }
        let resolver = NSWorkspaceCodexExecutableResolver(
            locator: CodexAppLocator(preferredURL: { nil }, allURLs: { [app.url] }, runningURL: { nil })
        )

        #expect(try resolver.resolveCodexExecutable() == app.url.appendingPathComponent("Contents/Resources/codex-cli/bin/codex"))
    }

    @Test
    func addingWithoutTheCodexAppThrowsCodexAppNotFound() {
        let resolver = NSWorkspaceCodexExecutableResolver(locator: .only(nil))

        #expect(throws: CodexAppNotFoundError()) { try resolver.resolveCodexExecutable() }
    }

    @Test
    func relaunchingWithoutTheCodexAppSkipsTheRelaunch() async throws {
        let client = SystemCodexAppProcessClient(locator: .only(nil))

        #expect(try await client.relaunchCodex() == .appNotFound)
    }
}

private extension CodexAppLocator {
    static func only(_ url: URL?) -> CodexAppLocator {
        CodexAppLocator(preferredURL: { url }, allURLs: { url.map { [$0] } ?? [] }, runningURL: { nil })
    }
}

private struct FakeCodexApp {
    let url: URL

    init(cliPath: String) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("CodexAppLocationTests-\(UUID().uuidString)/ChatGPT.app")
        let cli = url.appendingPathComponent(cliPath)
        try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
